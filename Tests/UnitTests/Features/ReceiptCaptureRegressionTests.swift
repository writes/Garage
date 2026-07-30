import Foundation
import Testing
@testable import Garage

/// Regression cover for three defects found in review of the receipt capture flow:
/// re-burning the metered quota after a terminal failure, an abandoned PDF preflight
/// resurrecting the scan, and the PDF affordance dead-ending when a photo is staged.
@MainActor
struct ReceiptCaptureViewModelRegressionTests {
    @Test func abandon_blocksASuccessfulPDFPreflightFromResurrectingTheScan() async {
        let preflighter = SuspendedReceiptPreflighter()
        let securityScope = RecordingOilAnalysisSecurityScope()
        let viewModel = makeReceiptCaptureViewModel(preflighter: preflighter, securityScope: securityScope)
        viewModel.addPDF(url: URL(fileURLWithPath: "/tmp/receipt.pdf"))
        await waitForReceiptPDFCall(preflighter)
        viewModel.abandon()
        #expect(viewModel.phase == .idle)
        #expect(securityScope.events == [.acquired, .released])
        preflighter.completePDF(with: .success("cGRm"))
        for _ in 0 ..< 10 { await Task.yield() }
        #expect(viewModel.pdfPage == nil)
        #expect(viewModel.phase == .idle)
    }

    /// A model verdict keeps its quota unit, so retrying unchanged pages would purchase the same
    /// answer again. Removing a page creates a different document and makes one new call useful.
    @Test func confirmAndParse_notAReceiptBlocksUntilAPageIsRemoved() async {
        let service = FakeReceiptService(result: .failure(ReceiptCallableError.notAReceipt))
        let viewModel = makeReceiptCaptureViewModel(service: service)
        viewModel.addImage(Data([0x01]), source: .camera)
        viewModel.addImage(Data([0x02]), source: .library)
        await viewModel.confirmAndParse(vehicle: nil)
        #expect(viewModel.phase == .failed(.notAReceipt))
        #expect(!viewModel.canSubmit)
        await viewModel.confirmAndParse(vehicle: nil)
        #expect(service.callCount == 1)
        viewModel.removeImagePage(viewModel.imagePages[1].id)
        #expect(viewModel.phase == .ready)
        #expect(viewModel.canSubmit)
        service.result = .success(.init(proposal: sampleReceiptProposal, token: nil, quota: nil))
        await viewModel.confirmAndParse(vehicle: nil)
        #expect(service.callCount == 2)
        #expect(viewModel.phase == .ready)
        #expect(viewModel.consumeProposalPackage()?.proposal == sampleReceiptProposal)
    }

    @Test func confirmAndParse_proMonthExhaustedBlocksASecondMeteredCall() async {
        let resetAt = Date(timeIntervalSince1970: 10_000)
        let service = FakeReceiptService(result: .failure(ReceiptCallableError.proMonthExhausted(resetAt: resetAt)))
        let viewModel = makeReceiptCaptureViewModel(service: service)
        viewModel.addImage(Data([0x01]), source: .camera)
        await viewModel.confirmAndParse(vehicle: nil)
        await viewModel.confirmAndParse(vehicle: nil)
        #expect(viewModel.phase == .failed(.proMonthExhausted(resetAt: resetAt)))
        #expect(service.callCount == 1)
    }

    @Test func confirmAndParse_freeLifetimeExhaustedBlocksASecondMeteredCall() async {
        let service = FakeReceiptService(result: .failure(ReceiptCallableError.freeLifetimeExhausted))
        let viewModel = makeReceiptCaptureViewModel(service: service)
        viewModel.addImage(Data([0x01]), source: .camera)
        await viewModel.confirmAndParse(vehicle: nil)
        await viewModel.confirmAndParse(vehicle: nil)
        #expect(viewModel.phase == .failed(.freeLifetimeExhausted))
        #expect(service.callCount == 1)
    }

    @Test func quotaDenialStaysBlockedAfterAPageMutation() async {
        let resetAt = Date(timeIntervalSince1970: 10_000)
        let service = FakeReceiptService(result: .failure(ReceiptCallableError.proMonthExhausted(resetAt: resetAt)))
        let viewModel = makeReceiptCaptureViewModel(service: service)
        viewModel.addImage(Data([0x01]), source: .camera)
        await viewModel.confirmAndParse(vehicle: nil)
        viewModel.addImage(Data([0x02]), source: .library)
        #expect(viewModel.imagePages.count == 2)
        #expect(viewModel.phase == .failed(.proMonthExhausted(resetAt: resetAt)))
        #expect(!viewModel.canSubmit)
    }

    @Test func addPDFWithAnImageReportsWhyTheDocumentCannotBeUsed() {
        let viewModel = makeReceiptCaptureViewModel()
        viewModel.addImage(Data([0x01]), source: .camera)
        #expect(!viewModel.canAddPDF)
        viewModel.addPDF(url: URL(fileURLWithPath: "/tmp/receipt.pdf"))
        #expect(viewModel.pdfPage == nil)
        #expect(
            viewModel.phase == .failed(
                .preflight(.unknown("A PDF and photos cannot be combined in one scan."))
            )
        )
    }
}
