import AVFoundation
import Foundation
import Speech

// Audio-session setup and permission mapping. Split out of the main file, which sits on the
// 250-line cap and whose remaining content is the recording state machine.
extension SpeechTranscriptionService {
    /// Ends the session when iOS takes the microphone away.
    ///
    /// Without this the service kept claiming to record after capture had already stopped: a phone
    /// call, another app grabbing the mic, or unplugging headphones interrupts the session and
    /// stops the engine, but the tap goes quiet rather than erroring, so the UI stayed in its
    /// listening state and everything said afterwards was lost. Both independent reviews of this
    /// file flagged it, which is why it is handled rather than noted.
    ///
    /// Route changes are filtered to `oldDeviceUnavailable` — a device merely *becoming* available
    /// is routine and must not abort a recording in progress.
    func observeAudioInterruptions() {
        let center = NotificationCenter.default
        let abort: @Sendable (Notification) -> Void = { [weak self] note in
            guard Self.isDisruptive(note) else { return }
            Task { @MainActor [weak self] in self?.abortForAudioLoss() }
        }
        interruptionObservers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification,
                               object: nil, queue: nil, using: abort),
            center.addObserver(forName: AVAudioSession.routeChangeNotification,
                               object: nil, queue: nil, using: abort),
            center.addObserver(forName: .AVAudioEngineConfigurationChange,
                               object: nil, queue: nil, using: abort)
        ]
    }

    nonisolated static func isDisruptive(_ note: Notification) -> Bool {
        switch note.name {
        case AVAudioSession.interruptionNotification:
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            return raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
        case AVAudioSession.routeChangeNotification:
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            return raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) == .oldDeviceUnavailable
        default:
            // An engine configuration change invalidates the installed tap.
            return true
        }
    }

    /// iOS took the microphone away mid-sentence. Tear the session down cleanly and tell the UI —
    /// anything already heard is still offered, since a partial entry beats none.
    func abortForAudioLoss() {
        guard audioEngine.isRunning || task != nil else { return }
        VoiceSessionTrace.shared.mark("interrupt.abort")
        stopObservingAudioInterruptions()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        resumeFinalContinuation(with: partialTranscript)
        onSessionInterrupted?()
    }

    /// Biases recognition toward the vocabulary this app actually hears. Without `contextualStrings`
    /// "Mobil 1" comes back as "mobile one" and "rotors" as "routers", and a mis-heard part name
    /// becomes a wrong field downstream — so the fix belongs before the transcript exists.
    static func makeRequest(contextualStrings: [String]) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = contextualStrings
        request.taskHint = .dictation
        request.addsPunctuation = true
        return request
    }

    func stopObservingAudioInterruptions() {
        interruptionObservers.forEach(NotificationCenter.default.removeObserver)
        interruptionObservers = []
    }

    /// The recognition callback for one session generation. Explicit `self.` throughout the
    /// nested closure: the CI toolchain (newer Swift than local) rejects implicit self after
    /// `guard let self` when the rebinding happens inside a closure nested in another
    /// [weak self] closure — local Xcode accepts it.
    func makeRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onUpdate: @escaping @MainActor (String) -> Void
    ) -> SFSpeechRecognitionTask {
        let generation = sessionGeneration
        return recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                // A callback from a superseded session must not touch current state: its late
                // error would otherwise wake the live session's waiter with the wrong transcript.
                guard let self, generation == self.sessionGeneration else { return }
                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                    onUpdate(self.partialTranscript)
                    // The final result is the rescored one and includes the tail of the sentence.
                    if result.isFinal { self.resumeFinalContinuation(with: self.partialTranscript) }
                }
                if error != nil {
                    // A recognition error mid-sentence is not fatal — whatever was heard so far
                    // is still worth offering. It must not hang the caller waiting for a final
                    // result that will never arrive.
                    self.resumeFinalContinuation(with: self.partialTranscript)
                }
            }
        }
    }

    /// Waits for the recogniser's final result, bounded by `finalResultTimeout`.
    ///
    /// The `pendingFinalTranscript` check is not belt-and-braces: `endAudio()` can produce the
    /// final result before this method gets a chance to store its continuation, and a callback
    /// arriving with no waiter would leave the continuation stored and never resumed — hanging the
    /// caller on a spinner forever. Recording it instead makes the race harmless in both orders.
    func awaitFinalTranscript() async -> String {
        if let alreadyArrived = pendingFinalTranscript {
            pendingFinalTranscript = nil
            return alreadyArrived
        }
        // On timeout the last partial is returned — exactly the old behaviour, so this path can
        // only match it, never do worse.
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.finalResultTimeout)
            guard !Task.isCancelled, let self else { return }
            resumeFinalContinuation(with: partialTranscript)
        }
        defer { timeout.cancel() }
        return await withCheckedContinuation { continuation in
            finalContinuation = continuation
        }
    }

    /// A `CheckedContinuation` traps if resumed twice, and both `isFinal` and an error can arrive
    /// for one session — so every resume goes through here and clears the stored continuation.
    func resumeFinalContinuation(with text: String) {
        guard let continuation = finalContinuation else {
            // Nobody is waiting yet. Hold the result so the waiter that arrives next takes it
            // rather than blocking on a callback that has already fired.
            pendingFinalTranscript = text
            return
        }
        finalContinuation = nil
        continuation.resume(returning: text)
    }

    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> SpeechPermission {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .undetermined
        @unknown default: return .denied
        }
    }
}
