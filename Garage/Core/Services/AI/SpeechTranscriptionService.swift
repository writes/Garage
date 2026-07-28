import AVFoundation
import Foundation
import Speech

enum SpeechPermission: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case undetermined
}

enum SpeechTranscriptionError: Error, Equatable {
    /// The on-device recognizer is momentarily unavailable (offline model loading, airplane mode).
    case recognizerUnavailable
    /// The audio input reported an unusable format. Surfaced as an error instead of being passed
    /// to `installTap`, which raises an uncatchable Objective-C exception and kills the process.
    case audioInputUnavailable
}

/// Live dictation contract. Isolated to the main actor so the ViewModel drives it without hops;
/// the concrete `SpeechTranscriptionService` bridges the off-thread recognizer callbacks back on.
@MainActor
protocol SpeechTranscribing: AnyObject {
    func requestPermission() async -> SpeechPermission
    func startRecording(contextualStrings: [String], onUpdate: @escaping @MainActor (String) -> Void) throws
    /// Async because the FINAL transcript does not exist yet when recording stops — see the
    /// implementation for why returning the last partial was losing the end of every sentence.
    func stopRecording() async -> String
}

/// Wraps `SFSpeechRecognizer` + `AVAudioEngine` for dictation of a single log entry.
/// It only ever produces TEXT — the transcript is handed to the voiceQuickAdd function and then
/// to the entry form for the user to confirm (Trust Pledge). It never saves anything itself.
@MainActor
final class SpeechTranscriptionService: SpeechTranscribing {
    static let shared = SpeechTranscriptionService()

    /// How long to wait for the recogniser's final result after the audio ends. Long enough for the
    /// rescoring pass on a normal sentence, short enough that a wedged recogniser cannot leave the
    /// user staring at a spinner — on timeout the last partial is returned, which is exactly the
    /// old behaviour, so this can only improve on it.
    static let finalResultTimeout: Duration = .milliseconds(1_500)

    /// Device locale first. A hardcoded en-US recogniser transcribes en-GB or en-AU speech
    /// noticeably worse, and for any other language it is simply the wrong model.
    private let recognizer = SFSpeechRecognizer(locale: .current)
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var partialTranscript = ""
    private var finalContinuation: CheckedContinuation<String, Never>?
    /// A final result that arrived before anyone was waiting for it. See `awaitFinalTranscript`.
    private var pendingFinalTranscript: String?

    func requestPermission() async -> SpeechPermission {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return Self.map(speechStatus) }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        return micGranted ? .authorized : .denied
    }

    func startRecording(
        contextualStrings: [String] = SpeechVocabulary.automotive,
        onUpdate: @escaping @MainActor (String) -> Void
    ) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }
        // Idempotent restart: a second start while the engine is still running is otherwise a
        // crash, not an error.
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        task?.cancel()
        task = nil
        partialTranscript = ""
        resumeFinalContinuation(with: "")
        pendingFinalTranscript = nil

        try configureSession()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Biases recognition toward the vocabulary this app actually hears. Without it "Mobil 1"
        // comes back as "mobile one" and "rotors" as "routers", and a mis-heard part name becomes
        // a wrong field downstream.
        request.contextualStrings = contextualStrings
        request.taskHint = .dictation
        request.addsPunctuation = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    partialTranscript = result.bestTranscription.formattedString
                    onUpdate(partialTranscript)
                    // The final result is the rescored one and includes the tail of the sentence.
                    if result.isFinal { resumeFinalContinuation(with: partialTranscript) }
                }
                if error != nil {
                    // A recognition error mid-sentence is not fatal — whatever was heard so far is
                    // still worth offering. It must not hang the caller waiting for a final result
                    // that will never arrive.
                    resumeFinalContinuation(with: partialTranscript)
                }
            }
        }

        try attachTap(feeding: request)
    }

    /// The audio-graph half of `startRecording`, split out to stay under the body-length cap —
    /// and because both uncatchable-crash guards live here, which makes them easier to find.
    private func attachTap(feeding request: SFSpeechAudioBufferRecognitionRequest) throws {
        let inputNode = audioEngine.inputNode
        // Remove any tap left by a previous session BEFORE installing. Installing a second tap on
        // a bus that already has one raises "required condition is false: nullptr == Tap()" — an
        // Objective-C exception Swift cannot catch, so it terminates the app. The old code
        // cancelled the recognition task on re-entry but never removed the tap, so starting a
        // second dictation without a completed stop crashed.
        inputNode.removeTap(onBus: 0)

        let format = inputNode.outputFormat(forBus: 0)
        // The other uncatchable installTap crash: when the audio route is still settling, or the
        // session failed to activate, or another app holds the mic, `outputFormat(forBus:)` hands
        // back a format with a zero sample rate. Passing that to installTap raises "required
        // condition is false: format.sampleRate == hwFormat.sampleRate" and kills the process. It
        // is a recoverable condition, so it is reported as an error the UI can show.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            throw SpeechTranscriptionError.audioInputUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            // Leave nothing installed behind a failed start, or the next attempt hits the
            // double-tap crash above.
            inputNode.removeTap(onBus: 0)
            throw error
        }
    }

    /// Awaits the recogniser's FINAL transcript rather than returning the newest partial.
    ///
    /// The old version called `endAudio()`/`finish()` and immediately returned `partialTranscript`.
    /// Both of those are asynchronous: the final result — which contains the tail of the sentence
    /// and Apple's end-of-utterance rescoring — arrives afterwards, so the returned text was
    /// systematically missing the last word or two of every entry and was never the best
    /// transcription available. That text is what the extraction model sees, so the loss compounds
    /// into missing fields.
    func stopRecording() async -> String {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()

        let result = await awaitFinalTranscript()
        task?.cancel()
        request = nil
        task = nil
        pendingFinalTranscript = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return result
    }

    /// Waits for the recogniser's final result, bounded by `finalResultTimeout`.
    ///
    /// The `pendingFinalTranscript` check is not belt-and-braces: `endAudio()` can produce the
    /// final result before this method gets a chance to store its continuation, and a callback
    /// arriving with no waiter would leave the continuation stored and never resumed — hanging the
    /// caller on a spinner forever. Recording it instead makes the race harmless in both orders.
    private func awaitFinalTranscript() async -> String {
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
    private func resumeFinalContinuation(with text: String) {
        guard let continuation = finalContinuation else {
            // Nobody is waiting yet. Hold the result so the waiter that arrives next takes it
            // rather than blocking on a callback that has already fired.
            pendingFinalTranscript = text
            return
        }
        finalContinuation = nil
        continuation.resume(returning: text)
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> SpeechPermission {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .undetermined
        @unknown default: return .denied
        }
    }
}
