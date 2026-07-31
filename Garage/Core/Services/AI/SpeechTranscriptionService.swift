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
    func startRecording(
        contextualStrings: [String],
        onInterrupted: @escaping @MainActor () -> Void,
        onUpdate: @escaping @MainActor (String) -> Void
    ) throws
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
    // `internal` (not `private`): the +Session extension file's abortForAudioLoss needs these.
    let audioEngine = AVAudioEngine()
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    var partialTranscript = ""
    // The three below are `internal` (not `private`) because the final-transcript machinery
    // (awaitFinalTranscript / resumeFinalContinuation / makeRecognitionTask) lives in the
    // +Session extension file for the file-length cap.
    var finalContinuation: CheckedContinuation<String, Never>?
    /// A final result that arrived before anyone was waiting for it. See `awaitFinalTranscript`.
    var pendingFinalTranscript: String?
    /// Bumped by every `startRecording`. A `stopRecording` that is still suspended when a NEW
    /// session begins must not tear that session down — it belongs to a generation that is over.
    var sessionGeneration = 0
    // `internal`: registered/cleared by the +Session extension file.
    var interruptionObservers: [NSObjectProtocol] = []
    /// Called when iOS ends the session under us, so the UI can leave its listening state instead
    /// of sitting on a mic that is no longer recording. Supplied per session by `startRecording`.
    var onSessionInterrupted: (@MainActor () -> Void)?
    private var isStopping = false

    /// `nonisolated` + `@Sendable` callbacks are THE FIX for the TestFlight voice crash
    /// (both build-3 and build-4 crash logs): inside a @MainActor type, these completion
    /// closures otherwise INHERIT MainActor isolation, and iOS delivers them on a background
    /// TCC/XPC queue — the runtime's isolation assertion then traps
    /// (EXC_BREAKPOINT, dispatch_assert_queue_fail -> swift_task_checkIsolated -> closure #1
    /// in closure #1 in requestPermission). It reproduced only on device: test doubles and
    /// simulator TCC never deliver the callback off-main. This method touches no actor state,
    /// so isolation was never needed.
    nonisolated func requestPermission() async -> SpeechPermission {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return Self.map(speechStatus) }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                continuation.resume(returning: granted)
            }
        }
        return micGranted ? .authorized : .denied
    }

    func startRecording(
        contextualStrings: [String] = SpeechVocabulary.automotive,
        onInterrupted: @escaping @MainActor () -> Void = {},
        onUpdate: @escaping @MainActor (String) -> Void
    ) throws {
        onSessionInterrupted = onInterrupted
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }
        // Idempotent restart: a second start while the engine is still running is otherwise a
        // crash, not an error.
        if audioEngine.isRunning {
            VoiceSessionTrace.shared.mark("start.stopStaleEngine")
            audioEngine.stop()
        }
        sessionGeneration &+= 1
        stopObservingAudioInterruptions()
        task?.cancel()
        task = nil
        partialTranscript = ""
        resumeFinalContinuation(with: "")
        pendingFinalTranscript = nil
        isStopping = false

        VoiceSessionTrace.shared.mark("start.configureSession")
        try configureSession()
        let request = Self.makeRequest(contextualStrings: contextualStrings)
        self.request = request

        VoiceSessionTrace.shared.mark("start.recognitionTask")
        task = makeRecognitionTask(recognizer: recognizer, request: request, onUpdate: onUpdate)

        do {
            try attachTap(feeding: request)
        } catch {
            // The recognition task was already started above; leaving it running on a failed
            // audio setup leaks it and lets it fire callbacks into a session that never began.
            task?.cancel()
            task = nil
            self.request = nil
            throw error
        }
    }

    /// The audio-graph half of `startRecording`, split out to stay under the body-length cap —
    /// and because both uncatchable-crash guards live here, which makes them easier to find.
    private func attachTap(feeding request: SFSpeechAudioBufferRecognitionRequest) throws {
        VoiceSessionTrace.shared.mark("tap.inputNode")
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

        // The sample rate and channel count are the two values the uncatchable installTap
        // exceptions are about, so the trace carries them.
        VoiceSessionTrace.shared.mark("tap.install sr=\(Int(format.sampleRate)) ch=\(format.channelCount)")
        // The tap block runs on AVFAudio's realtime messenger queue, NEVER the main actor. A
        // plain closure formed here (a @MainActor context) INHERITS main-actor isolation, and
        // iOS 26.5's runtime executor check traps on entry off-main — the 2026-07-31 TestFlight
        // crash (dispatch_assert_queue_fail via _swift_task_checkIsolatedSwift in this exact
        // closure), the same Swift 6 class as build 4's TCC callback. @Sendable severs the
        // inference; `append` is thread-safe by SDK contract (its purpose is audio-queue
        // feeding), so the nonisolated(unsafe) capture states a real invariant, not a wish.
        nonisolated(unsafe) let feed = request
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { @Sendable buffer, _ in
            feed.append(buffer)
        }
        audioEngine.prepare()
        VoiceSessionTrace.shared.mark("engine.start")
        do {
            try audioEngine.start()
            observeAudioInterruptions()
            VoiceSessionTrace.shared.mark("engine.running")
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
        // A second stop while the first is still awaiting would overwrite `finalContinuation` and
        // orphan the first caller, hanging it forever. A double-tap on the mic button is enough.
        guard !isStopping else { return partialTranscript }
        isStopping = true
        defer { isStopping = false }
        let generation = sessionGeneration
        VoiceSessionTrace.shared.mark("stop.engine")
        audioEngine.stop()
        VoiceSessionTrace.shared.mark("stop.removeTap")
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()

        VoiceSessionTrace.shared.mark("stop.awaitFinal")
        let result = await awaitFinalTranscript()
        // If a new session started while this was suspended, everything below belongs to that
        // session — tearing it down here would silently kill a recording the user just began.
        guard generation == sessionGeneration else { return result }
        stopObservingAudioInterruptions()
        task?.cancel()
        request = nil
        task = nil
        pendingFinalTranscript = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        VoiceSessionTrace.shared.mark("stop.done")
        return result
    }

}
