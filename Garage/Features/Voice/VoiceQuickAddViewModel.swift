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
    private let analytics: any AnalyticsTracking
    private let now: () -> Date

    private(set) var phase: VoicePhase = .idle
    private(set) var transcript = ""
    /// Non-nil once a proposal is ready; the view consumes it exactly once and routes to the form.
    private(set) var proposal: VoiceEntryProposal?

    init(
        transcriber: any SpeechTranscribing = SpeechTranscriptionService.shared,
        service: any VoiceQuickAddCalling = VoiceQuickAddService.shared,
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        now: @escaping () -> Date = { .now }
    ) {
        self.transcriber = transcriber
        self.service = service
        self.analytics = analytics
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
        // Fires on mic-tap INTENT, before permission — so every failure below, including a
        // permission denial, stays inside the started -> succeeded/failed funnel.
        analytics.track(.voiceCaptureStarted)
        VoiceSessionTrace.shared.mark("vm.permission")
        let permission = await transcriber.requestPermission()
        guard permission == .authorized else {
            fail(.permissionDenied)
            return
        }
        do {
            // The user's own vehicle leads the recogniser hints — its make and model are the
            // proper nouns most likely in the sentence and the ones no generic list can hold.
            try transcriber.startRecording(
                contextualStrings: SpeechVocabulary.terms(for: vehicle),
                onInterrupted: { [weak self] in
                    // iOS took the mic (a call, another app, headphones unplugged). Leave the
                    // listening state rather than sitting on a mic that stopped capturing.
                    guard let self, isListening else { return }
                    fail(.audioInputUnavailable)
                },
                onUpdate: { [weak self] text in
                    self?.transcript = text
                }
            )
            phase = .listening
        } catch SpeechTranscriptionError.audioInputUnavailable {
            // Distinct from "recognizer unavailable": the mic itself is busy or still switching
            // routes, which the user resolves differently (close the other app, unplug the
            // headset) — and which used to crash the app rather than say anything at all.
            fail(.audioInputUnavailable)
        } catch {
            fail(.recognizerUnavailable)
        }
    }

    private func finishListening(vehicle: Vehicle?) async {
        let captured = await transcriber.stopRecording().trimmed
        let text = captured.isEmpty ? transcript.trimmed : captured
        guard !text.isEmpty else {
            fail(.emptyTranscript)
            return
        }
        transcript = text
        phase = .thinking
        VoiceSessionTrace.shared.mark("vm.propose chars=\(text.count)")
        do {
            let ready = try await service.proposeEntry(transcript: text, vehicle: vehicle, now: now())
            proposal = ready
            phase = .idle
            analytics.track(.voiceProposalSucceeded(entryType: ready.entryType))
            VoiceSessionTrace.shared.mark("vm.proposalReady")
        } catch let error as VoiceCallableError {
            fail(Self.map(error))
        } catch {
            fail(.generic(error.localizedDescription))
        }
    }

    /// Single funnel exit: every failure sets the phase, reports its closed-enum reason, and
    /// closes the crash trace — the app is alive and showing an error, not crashing.
    private func fail(_ failure: VoiceFailure) {
        phase = .failed(failure)
        analytics.track(.voiceProposalFailed(reason: failure.analyticsReason))
        VoiceSessionTrace.shared.endCleanly()
    }

    /// One-shot handoff: returns the ready proposal and clears it so the view routes exactly once.
    func consumeProposal() -> VoiceEntryProposal? {
        defer {
            proposal = nil
            // The trace stays open until the view routes so a crash between "proposal ready"
            // and the form appearing is still attributed to the voice flow.
            VoiceSessionTrace.shared.endCleanly()
        }
        return proposal
    }

    func reset() {
        phase = .idle
        transcript = ""
        proposal = nil
        VoiceSessionTrace.shared.endCleanly()
    }

    /// Sheet dismissal mid-flow: stop the mic if it is live, then clear state. Without this a
    /// dismissed sheet left the engine capturing — the red recording indicator stayed on with
    /// no UI attached to it.
    func abandon() async {
        if isListening {
            VoiceSessionTrace.shared.mark("vm.abandon")
            _ = await transcriber.stopRecording()
        }
        reset()
    }

    private static func map(_ error: VoiceCallableError) -> VoiceFailure {
        switch error {
        case .proRequired: return .proRequired
        case .dailyExhausted(let resetAt): return .dailyExhausted(resetAt: resetAt)
        }
    }
}

extension VoiceFailure {
    /// Lives next to `VoiceFailure` so adding a case here is a compile error until it maps.
    var analyticsReason: VoiceFailureReason {
        switch self {
        case .permissionDenied: return .permissionDenied
        case .proRequired: return .proRequired
        case .dailyExhausted: return .dailyExhausted
        case .recognizerUnavailable: return .recognizerUnavailable
        case .audioInputUnavailable: return .audioInputUnavailable
        case .emptyTranscript: return .emptyTranscript
        case .generic: return .serviceError
        }
    }
}
