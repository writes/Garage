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
