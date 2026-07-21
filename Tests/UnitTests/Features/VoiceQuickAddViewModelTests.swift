import Foundation
import Testing
@testable import Garage

@MainActor
private final class FakeTranscriber: SpeechTranscribing {
    var permission: SpeechPermission = .authorized
    var startError: Error?
    var finalTranscript = ""
    private(set) var started = false
    private(set) var stopped = false
    private var onUpdate: (@MainActor (String) -> Void)?

    func requestPermission() async -> SpeechPermission { permission }

    func startRecording(onUpdate: @escaping @MainActor (String) -> Void) throws {
        if let startError { throw startError }
        self.onUpdate = onUpdate
        started = true
    }

    func stopRecording() -> String {
        stopped = true
        return finalTranscript
    }

    func emitPartial(_ text: String) { onUpdate?(text) }
}

@MainActor
private final class FakeVoiceService: VoiceQuickAddCalling {
    var result: Result<VoiceEntryProposal, Error>
    private(set) var lastTranscript: String?

    init(result: Result<VoiceEntryProposal, Error>) { self.result = result }

    func proposeEntry(transcript: String, vehicle: Vehicle?, now: Date) async throws -> VoiceEntryProposal {
        lastTranscript = transcript
        return try result.get()
    }
}

private let sampleProposal = VoiceEntryProposal(
    entryType: .oilChange, odometerReading: 18_120, cost: 165, shopName: nil,
    isDiy: true, entryDate: nil, notes: "Mobil 1"
)

@MainActor
private func makeViewModel(
    transcriber: FakeTranscriber,
    service: FakeVoiceService
) -> VoiceQuickAddViewModel {
    VoiceQuickAddViewModel(transcriber: transcriber, service: service, now: { Date(timeIntervalSince1970: 0) })
}

@MainActor
struct VoiceQuickAddViewModelTests {
    @Test func deniedPermissionFailsWithoutRecording() async {
        let transcriber = FakeTranscriber()
        transcriber.permission = .denied
        let service = FakeVoiceService(result: .success(sampleProposal))
        let viewModel = makeViewModel(transcriber: transcriber, service: service)

        await viewModel.startListening()

        #expect(viewModel.phase == .failed(.permissionDenied))
        #expect(transcriber.started == false)
    }

    @Test func listeningReflectsLivePartials() async {
        let transcriber = FakeTranscriber()
        let service = FakeVoiceService(result: .success(sampleProposal))
        let viewModel = makeViewModel(transcriber: transcriber, service: service)

        await viewModel.startListening()
        transcriber.emitPartial("oil change on the")

        #expect(viewModel.isListening)
        #expect(viewModel.transcript == "oil change on the")
    }

    @Test func happyPathProducesProposalFromFinalTranscript() async {
        let transcriber = FakeTranscriber()
        transcriber.finalTranscript = "oil change on the viper"
        let service = FakeVoiceService(result: .success(sampleProposal))
        let viewModel = makeViewModel(transcriber: transcriber, service: service)

        await viewModel.startListening()
        await viewModel.toggle(vehicle: nil)

        #expect(transcriber.stopped)
        #expect(service.lastTranscript == "oil change on the viper")
        #expect(viewModel.phase == .idle)
        #expect(viewModel.consumeProposal() == sampleProposal)
        #expect(viewModel.consumeProposal() == nil)
    }

    @Test func emptyTranscriptFailsBeforeAnyCall() async {
        let transcriber = FakeTranscriber()
        transcriber.finalTranscript = "   "
        let service = FakeVoiceService(result: .success(sampleProposal))
        let viewModel = makeViewModel(transcriber: transcriber, service: service)

        await viewModel.startListening()
        await viewModel.toggle(vehicle: nil)

        #expect(viewModel.phase == .failed(.emptyTranscript))
        #expect(service.lastTranscript == nil)
    }

    @Test func proRequiredErrorMapsToUpsellFailure() async {
        let transcriber = FakeTranscriber()
        transcriber.finalTranscript = "brake job"
        let service = FakeVoiceService(result: .failure(VoiceCallableError.proRequired))
        let viewModel = makeViewModel(transcriber: transcriber, service: service)

        await viewModel.startListening()
        await viewModel.toggle(vehicle: nil)

        #expect(viewModel.phase == .failed(.proRequired))
    }

    @Test func dailyExhaustedErrorCarriesResetDate() async {
        let resetAt = Date(timeIntervalSince1970: 10_000)
        let transcriber = FakeTranscriber()
        transcriber.finalTranscript = "tire rotation"
        let service = FakeVoiceService(result: .failure(VoiceCallableError.dailyExhausted(resetAt: resetAt)))
        let viewModel = makeViewModel(transcriber: transcriber, service: service)

        await viewModel.startListening()
        await viewModel.toggle(vehicle: nil)

        #expect(viewModel.phase == .failed(.dailyExhausted(resetAt: resetAt)))
    }
}
