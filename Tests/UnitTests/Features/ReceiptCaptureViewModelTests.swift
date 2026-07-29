import Foundation
import Testing
@testable import Garage

@MainActor
struct ReceiptCaptureViewModelTests {
    @Test func addImage_movesIdleToReadyAndReportsCaptureStarted() {
        let analytics = AnalyticsSpy()
        let viewModel = makeReceiptCaptureViewModel(analytics: analytics)

        viewModel.addImage(Data([0x01]), source: .camera)

        #expect(viewModel.phase == .ready)
        #expect(viewModel.imagePages.count == 1)
        #expect(analytics.events == [.receiptCaptureStarted(source: .camera)])
    }

    @Test func addImage_secondPageDoesNotReportASecondCaptureStarted() {
        let analytics = AnalyticsSpy()
        let viewModel = makeReceiptCaptureViewModel(analytics: analytics)

        viewModel.addImage(Data([0x01]), source: .camera)
        viewModel.addImage(Data([0x02]), source: .library)

        #expect(viewModel.imagePages.count == 2)
        #expect(analytics.events == [.receiptCaptureStarted(source: .camera)])
    }

    @Test func addImage_refusesAThirdPage() {
        let viewModel = makeReceiptCaptureViewModel()
        viewModel.addImage(Data([0x01]), source: .camera)
        viewModel.addImage(Data([0x02]), source: .camera)
        #expect(!viewModel.canAddImage)

        viewModel.addImage(Data([0x03]), source: .camera)
        #expect(viewModel.imagePages.count == 2)
    }

    @Test func addImage_preflightFailureReportsAndFails() {
        let preflighter = FakeReceiptPreflighter()
        preflighter.imageResult = .failure(ReceiptPreflightError.invalidImage)
        let analytics = AnalyticsSpy()
        let viewModel = makeReceiptCaptureViewModel(preflighter: preflighter, analytics: analytics)

        viewModel.addImage(Data([0x01]), source: .camera)

        #expect(viewModel.phase == .failed(.preflight(ReceiptPreflightError.invalidImage.appError)))
        #expect(analytics.events == [
            .receiptCaptureStarted(source: .camera), .receiptProposalFailed(reason: .preflight)
        ])
    }

    @Test func removeImagePage_backToIdleWhenLastPageRemoved() {
        let viewModel = makeReceiptCaptureViewModel()
        viewModel.addImage(Data([0x01]), source: .camera)
        let id = viewModel.imagePages[0].id

        viewModel.removeImagePage(id)

        #expect(viewModel.imagePages.isEmpty)
        #expect(viewModel.phase == .idle)
    }

    @Test func confirmAndParse_happyPathProducesAProposalAndReportsSuccess() async {
        let analytics = AnalyticsSpy()
        let service = FakeReceiptService(result: .success(sampleReceiptProposal))
        let viewModel = makeReceiptCaptureViewModel(service: service, analytics: analytics)
        viewModel.addImage(Data([0x01]), source: .camera)

        await viewModel.confirmAndParse(vehicle: nil)

        #expect(service.lastImages == ["cGFyc2U="])
        #expect(viewModel.phase == .ready)
        #expect(analytics.events.last == .receiptProposalSucceeded(entryType: .oilChange))
        let package = viewModel.consumeProposalPackage()
        #expect(package?.proposal == sampleReceiptProposal)
        #expect(package?.attachments == [.init(kind: .image, data: Data([0xFF, 0xD8, 0xFF]), displayName: "Receipt")])
        #expect(viewModel.consumeProposalPackage() == nil)
    }

    @Test func confirmAndParse_notAReceiptReportsTypedFailure() async {
        let analytics = AnalyticsSpy()
        let service = FakeReceiptService(result: .failure(ReceiptCallableError.notAReceipt))
        let viewModel = makeReceiptCaptureViewModel(service: service, analytics: analytics)
        viewModel.addImage(Data([0x01]), source: .camera)

        await viewModel.confirmAndParse(vehicle: nil)

        #expect(viewModel.phase == .failed(.notAReceipt))
        #expect(analytics.events.last == .receiptProposalFailed(reason: .notAReceipt))
    }

    @Test func confirmAndParse_quotaDenialsReportTheQuotaEventNotTheFailureEvent() async {
        let analytics = AnalyticsSpy()
        let service = FakeReceiptService(result: .failure(ReceiptCallableError.freeLifetimeExhausted))
        let viewModel = makeReceiptCaptureViewModel(service: service, analytics: analytics)
        viewModel.addImage(Data([0x01]), source: .camera)

        await viewModel.confirmAndParse(vehicle: nil)

        #expect(viewModel.phase == .failed(.freeLifetimeExhausted))
        #expect(analytics.events.last == .receiptQuotaDenied(reason: .freeLifetimeExhausted))
    }

    /// G8: the confirm button stays enabled through the whole `.parsing` round trip — without the
    /// `isSubmitting` guard a double-tap would call the metered service twice for one scan.
    @Test func confirmAndParse_reentrancyGuardBlocksADoubleTap() async {
        let service = SuspendedReceiptService()
        let viewModel = makeReceiptCaptureViewModel(service: service)
        viewModel.addImage(Data([0x01]), source: .camera)

        async let first: Void = viewModel.confirmAndParse(vehicle: nil)
        await Task.yield()
        async let second: Void = viewModel.confirmAndParse(vehicle: nil)
        await Task.yield()
        #expect(service.callCount == 1)

        service.complete(with: .success(sampleReceiptProposal))
        _ = await (first, second)
        #expect(service.callCount == 1)
        #expect(viewModel.phase == .ready)
    }

    @Test func addPDF_movesThroughPreflightingToReady() async {
        let preflighter = SuspendedReceiptPreflighter()
        let securityScope = RecordingOilAnalysisSecurityScope()
        let viewModel = makeReceiptCaptureViewModel(preflighter: preflighter, securityScope: securityScope)

        viewModel.addPDF(url: URL(fileURLWithPath: "/tmp/receipt.pdf"))
        await waitForReceiptPDFCall(preflighter)

        #expect(viewModel.phase == .preflighting)
        preflighter.completePDF(with: .success("cGRm"))
        await waitForReceiptPhase(viewModel, notEqualTo: .preflighting)

        #expect(viewModel.phase == .ready)
        #expect(viewModel.pdfPage?.base64 == "cGRm")
        #expect(securityScope.events == [.acquired, .released])
    }

    // MARK: - Review findings: `.failed` must never destroy a page that already succeeded

    /// Page 1 succeeds, page 2's local preflight fails: page 1 must survive the failure (not be
    /// forced back through re-photographing, and not risk a second unrefunded metered scan) and
    /// remain submittable after the user retries.
    @Test func addImage_secondPageFailureKeepsFirstPageIntactAndStillSubmittable() async {
        let preflighter = FakeReceiptPreflighter()
        let service = FakeReceiptService(result: .success(sampleReceiptProposal))
        let viewModel = makeReceiptCaptureViewModel(preflighter: preflighter, service: service)

        viewModel.addImage(Data([0x01]), source: .camera)
        #expect(viewModel.imagePages.count == 1)

        preflighter.imageResult = .failure(ReceiptPreflightError.invalidImage)
        viewModel.addImage(Data([0x02]), source: .camera)

        #expect(viewModel.imagePages.count == 1)
        guard case .failed(.preflight) = viewModel.phase else {
            Issue.record("Expected a preflight failure, got \(viewModel.phase)")
            return
        }

        viewModel.retryAfterFailure()
        #expect(viewModel.phase == .ready)
        await viewModel.confirmAndParse(vehicle: nil)
        #expect(service.callCount == 1)
        #expect(viewModel.phase == .ready)
    }

    /// Sheet dismissal mid-parse must cancel the metered call so its (possibly late-arriving)
    /// result can never land on a viewModel the user already left.
    @Test func abandon_duringParseCancelsAndNoProposalLandsAfterward() async {
        let service = SuspendedReceiptService()
        let viewModel = makeReceiptCaptureViewModel(service: service)
        viewModel.addImage(Data([0x01]), source: .camera)

        async let parse: Void = viewModel.confirmAndParse(vehicle: nil)
        await waitForReceiptServiceCall(service)

        viewModel.abandon()
        #expect(viewModel.phase == .idle)
        #expect(viewModel.imagePages.isEmpty)

        service.complete(with: .success(sampleReceiptProposal)) // a late, now-stale result
        _ = await parse

        #expect(viewModel.proposal == nil)
        #expect(viewModel.phase == .idle)
    }

    /// Every `ReceiptCaptureFailure` case must map to exactly one analytics event family — a new
    /// case that forgets its mapping would otherwise compile only because the mapping lives in a
    /// switch the compiler exhausts.
    @Test func everyFailureCaseMapsToExactlyOneReasonFamily() {
        let failures: [ReceiptCaptureFailure] = [
            .preflight(.unknown("x")), .notAReceipt, .generic("x"),
            .freeLifetimeExhausted, .dailyExhausted(resetAt: .distantFuture)
        ]
        for failure in failures {
            let hasProposalReason = failure.proposalFailureReason != nil
            let hasQuotaReason = failure.quotaDeniedReason != nil
            #expect(hasProposalReason != hasQuotaReason)
        }
    }
}
