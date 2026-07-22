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
}

/// Live dictation contract. Isolated to the main actor so the ViewModel drives it without hops;
/// the concrete `SpeechTranscriptionService` bridges the off-thread recognizer callbacks back on.
@MainActor
protocol SpeechTranscribing: AnyObject {
    func requestPermission() async -> SpeechPermission
    func startRecording(onUpdate: @escaping @MainActor (String) -> Void) throws
    func stopRecording() -> String
}

/// Wraps `SFSpeechRecognizer` + `AVAudioEngine` for on-device dictation of a single log entry.
/// It only ever produces TEXT — the transcript is handed to the voiceQuickAdd function and then
/// to the entry form for the user to confirm (Trust Pledge). It never saves anything itself.
@MainActor
final class SpeechTranscriptionService: SpeechTranscribing {
    static let shared = SpeechTranscriptionService()

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var partialTranscript = ""

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

    func startRecording(onUpdate: @escaping @MainActor (String) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }
        task?.cancel()
        task = nil
        partialTranscript = ""

        try configureSession()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor [weak self] in
                self?.partialTranscript = text
                onUpdate(text)
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopRecording() -> String {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return partialTranscript
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
