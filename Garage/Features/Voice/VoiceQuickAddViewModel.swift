import Foundation
import Observation

enum VoicePhase: Equatable {
    case idle
    case listening
    case thinking
    case failed(VoiceFailure)
}

enum VoiceFailure: Equatable {
    /// Speech or microphone permission was refused — the UI points the user at Settings.
    case permissionDenied
    /// Voice quick-add is a Pro feature; a free caller hit the fence — the UI upsells.
    case proRequired
    /// The Pro daily voice allowance is used up; resets at `resetAt`.
    case dailyExhausted(resetAt: Date)
    /// The on-device recognizer could not start.
    case recognizerUnavailable
    /// The microphone reported no usable input — busy in another app, or a route still switching.
    /// Kept distinct from `recognizerUnavailable` because the user fixes it differently.
    case audioInputUnavailable
    /// Nothing intelligible was captured.
    case emptyTranscript
    /// Any other failure, carrying a user-readable description.
    case generic(String)
}

/// Drives one voice quick-add capture: permission → live dictation → a Cloud-Function proposal.
/// The proposal is a SUGGESTION only. When it is ready the view routes to the matching entry form
/// with the common fields prefilled, where the user confirms/edits/saves (Trust Pledge).
@MainActor
@Observable
final class VoiceQuickAddViewModel {
    private let transcriber: any SpeechTranscribing
    private let service: any VoiceQuickAddCalling
    private let now: () -> Date

    private(set) var phase: VoicePhase = .idle
    private(set) var transcript = ""
    /// Non-nil once a proposal is ready; the view consumes it exactly once and routes to the form.
    private(set) var proposal: VoiceEntryProposal?

    init(
        transcriber: any SpeechTranscribing = SpeechTranscriptionService.shared,
        service: any VoiceQuickAddCalling = VoiceQuickAddService.shared,
        now: @escaping () -> Date = { .now }
    ) {
        self.transcriber = transcriber
        self.service = service
        self.now = now
    }

    var isListening: Bool { phase == .listening }

    /// Tap the mic to start; tap again to stop and draft the entry.
    func toggle(vehicle: Vehicle?) async {
        if isListening {
            await finishListening(vehicle: vehicle)
        } else {
            await startListening(vehicle: vehicle)
        }
    }

    func startListening(vehicle: Vehicle? = nil) async {
        transcript = ""
        proposal = nil
        let permission = await transcriber.requestPermission()
        guard permission == .authorized else {
            phase = .failed(.permissionDenied)
            return
        }
        do {
            // The user's own vehicle leads the recogniser hints — its make and model are the
            // proper nouns most likely in the sentence and the ones no generic list can hold.
            try transcriber.startRecording(
                contextualStrings: SpeechVocabulary.terms(for: vehicle)
            ) { [weak self] text in
                self?.transcript = text
            }
            phase = .listening
        } catch SpeechTranscriptionError.audioInputUnavailable {
            // Distinct from "recognizer unavailable": the mic itself is busy or still switching
            // routes, which the user resolves differently (close the other app, unplug the
            // headset) — and which used to crash the app rather than say anything at all.
            phase = .failed(.audioInputUnavailable)
        } catch {
            phase = .failed(.recognizerUnavailable)
        }
    }

    private func finishListening(vehicle: Vehicle?) async {
        let captured = await transcriber.stopRecording().trimmed
        let text = captured.isEmpty ? transcript.trimmed : captured
        guard !text.isEmpty else {
            phase = .failed(.emptyTranscript)
            return
        }
        transcript = text
        phase = .thinking
        do {
            proposal = try await service.proposeEntry(transcript: text, vehicle: vehicle, now: now())
            phase = .idle
        } catch let error as VoiceCallableError {
            phase = .failed(Self.map(error))
        } catch {
            phase = .failed(.generic(error.localizedDescription))
        }
    }

    /// One-shot handoff: returns the ready proposal and clears it so the view routes exactly once.
    func consumeProposal() -> VoiceEntryProposal? {
        defer { proposal = nil }
        return proposal
    }

    func reset() {
        phase = .idle
        transcript = ""
        proposal = nil
    }

    private static func map(_ error: VoiceCallableError) -> VoiceFailure {
        switch error {
        case .proRequired: return .proRequired
        case .dailyExhausted(let resetAt): return .dailyExhausted(resetAt: resetAt)
        }
    }
}
