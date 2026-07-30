import Foundation
import Testing
@testable import Garage

@MainActor
struct ReceiptCaptureQuotaStatusTests {
    @Test func refreshQuotaStatus_showsFreeConfirmedBalance() async {
        let service = FakeReceiptService(result: .success(.init(
            proposal: sampleReceiptProposal, token: nil, quota: nil
        )))
        service.quotaStatusResult = .success(snapshot(
            entitlement: .free, scanRemaining: 12, scanCeiling: 20,
            confirmedRemaining: 3, confirmedAllowance: 5
        ))
        let viewModel = makeReceiptCaptureViewModel(service: service)

        await viewModel.refreshQuotaStatus()

        #expect(viewModel.quotaFooterState == .freeSavesLeft(3))
        #expect(service.quotaStatusCallCount == 1)
    }

    @Test func refreshQuotaStatus_showsProMonthlyConfirmedBalance() async {
        let service = FakeReceiptService(result: .success(.init(
            proposal: sampleReceiptProposal, token: nil, quota: nil
        )))
        service.quotaStatusResult = .success(snapshot(
            entitlement: .pro, scanRemaining: 79, scanCeiling: 80,
            confirmedRemaining: 19, confirmedAllowance: 20
        ))
        let viewModel = makeReceiptCaptureViewModel(service: service)

        await viewModel.refreshQuotaStatus()

        #expect(viewModel.quotaFooterState == .proSavesLeft(19))
    }

    @Test func refreshQuotaStatus_failureHidesBalanceWithoutBlockingCapture() async {
        let service = FakeReceiptService(result: .success(.init(
            proposal: sampleReceiptProposal, token: nil, quota: nil
        )))
        service.quotaStatusResult = .failure(AppError.unknown("status unavailable"))
        let viewModel = makeReceiptCaptureViewModel(service: service)
        viewModel.addImage(Data([0x01]), source: .camera)

        await viewModel.refreshQuotaStatus()

        #expect(viewModel.quotaFooterState == nil)
        #expect(viewModel.canSubmit)
    }

    @Test func refreshQuotaStatus_scanExhaustedOverridesPositiveConfirmedBalance() async {
        let service = FakeReceiptService(result: .success(.init(
            proposal: sampleReceiptProposal, token: nil, quota: nil
        )))
        service.quotaStatusResult = .success(snapshot(
            entitlement: .pro, scanRemaining: 0, scanCeiling: 80,
            confirmedRemaining: 4, confirmedAllowance: 20
        ))
        let viewModel = makeReceiptCaptureViewModel(service: service)

        await viewModel.refreshQuotaStatus()

        #expect(viewModel.quotaFooterState == .proScansExhausted)
    }

    @Test func successfulProposalCarriesTokenAndQuotaToTheOneShotPackage() async {
        let quota = snapshot(
            entitlement: .free, scanRemaining: 19, scanCeiling: 20,
            confirmedRemaining: 4, confirmedAllowance: 5
        )
        let service = FakeReceiptService(result: .success(.init(
            proposal: sampleReceiptProposal, token: "token", quota: quota
        )))
        let viewModel = makeReceiptCaptureViewModel(service: service)
        viewModel.addImage(Data([0x01]), source: .camera)

        await viewModel.confirmAndParse(vehicle: nil)

        #expect(viewModel.consumeProposalPackage()?.token == "token")
        #expect(viewModel.quotaFooterState == .freeSavesLeft(4))
    }

    @Test func proMonthDenialMapsToQuotaAnalytics() async {
        let resetAt = Date(timeIntervalSince1970: 100)
        let service = FakeReceiptService(result: .failure(.proMonthExhausted(resetAt: resetAt)))
        let analytics = AnalyticsSpy()
        let viewModel = makeReceiptCaptureViewModel(service: service, analytics: analytics)
        viewModel.addImage(Data([0x01]), source: .camera)

        await viewModel.confirmAndParse(vehicle: nil)

        #expect(viewModel.phase == .failed(.proMonthExhausted(resetAt: resetAt)))
        #expect(analytics.events.last == .receiptQuotaDenied(reason: .proMonthExhausted))
    }

    private func snapshot(
        entitlement: ReceiptQuotaSnapshot.Entitlement, scanRemaining: Int, scanCeiling: Int,
        confirmedRemaining: Int, confirmedAllowance: Int
    ) -> ReceiptQuotaSnapshot {
        ReceiptQuotaSnapshot(
            entitlement: entitlement, scanRemaining: scanRemaining, scanCeiling: scanCeiling,
            confirmedRemaining: confirmedRemaining, confirmedAllowance: confirmedAllowance,
            resetAt: entitlement == .pro ? "2026-08-01T00:00:00.000Z" : nil
        )
    }
}
