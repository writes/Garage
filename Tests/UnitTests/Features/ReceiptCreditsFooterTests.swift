import Foundation
import Testing
@testable import Garage

/// Per-route footer arithmetic (spec §21) + the additive wire decode. A save is usable only
/// where BOTH its scan and confirm capacity exist: `min(base pair) + min(credits pair)`.
@MainActor
struct ReceiptCreditsFooterTests {
    private func makeViewModel(snapshot: ReceiptQuotaSnapshot) -> ReceiptCaptureViewModel {
        let viewModel = makeReceiptCaptureViewModel()
        viewModel.quotaSnapshot = snapshot
        return viewModel
    }

    private func snapshot(
        entitlement: ReceiptQuotaSnapshot.Entitlement = .free,
        scanRemaining: Int, confirmedRemaining: Int,
        creditsRemaining: Int? = nil, creditsScanRemaining: Int? = nil
    ) -> ReceiptQuotaSnapshot {
        var value = ReceiptQuotaSnapshot(
            entitlement: entitlement, scanRemaining: scanRemaining, scanCeiling: 20,
            confirmedRemaining: confirmedRemaining, confirmedAllowance: 5, resetAt: nil
        )
        value.creditsRemaining = creditsRemaining
        value.creditsScanRemaining = creditsScanRemaining
        return value
    }

    @Test func baseOnlySnapshotKeepsTheHistoricalNumbers() {
        let viewModel = makeViewModel(snapshot: snapshot(scanRemaining: 20, confirmedRemaining: 5))
        #expect(viewModel.quotaFooterState == .freeSavesLeft(5))
    }

    @Test func creditsAddOnlyTheirUsablePair() {
        // 10 credits but only 3 credit scans -> 3 usable from the credit route.
        let viewModel = makeViewModel(snapshot: snapshot(
            scanRemaining: 20, confirmedRemaining: 5, creditsRemaining: 10, creditsScanRemaining: 3
        ))
        #expect(viewModel.quotaFooterState == .freeSavesLeft(8))
    }

    @Test func baseRouteIsBoundedByItsScanPool() {
        // 5 base confirms but 0 base scans: the base route contributes nothing; credits carry.
        let viewModel = makeViewModel(snapshot: snapshot(
            scanRemaining: 0, confirmedRemaining: 5, creditsRemaining: 4, creditsScanRemaining: 40
        ))
        #expect(viewModel.quotaFooterState == .freeSavesLeft(4))
    }

    @Test func bothRoutesDryWithZeroScansShowsScanExhaustion() {
        let free = makeViewModel(snapshot: snapshot(
            scanRemaining: 0, confirmedRemaining: 5, creditsRemaining: 0, creditsScanRemaining: 0
        ))
        #expect(free.quotaFooterState == .freeScansExhausted)

        let pro = makeViewModel(snapshot: snapshot(
            entitlement: .pro, scanRemaining: 0, confirmedRemaining: 3
        ))
        #expect(pro.quotaFooterState == .proScansExhausted)
    }

    @Test func creditScansAloneKeepTheZeroSavesCopyNotScanExhaustion() {
        // Base scans dry, credit SCANS remain, but zero credit balance: scans are not truly
        // exhausted, so the honest copy is "0 saves left" (Gemini client-check #6).
        let viewModel = makeViewModel(snapshot: snapshot(
            scanRemaining: 0, confirmedRemaining: 5, creditsRemaining: 0, creditsScanRemaining: 12
        ))
        #expect(viewModel.quotaFooterState == .freeSavesLeft(0))
    }

    @Test func zeroUsableWithScansLeftStillShowsZeroSaves() {
        // Confirm allowance dry, scans available, no credits: "0 saves left" is the honest copy
        // (the scan pool alone cannot produce a save).
        let viewModel = makeViewModel(snapshot: snapshot(scanRemaining: 12, confirmedRemaining: 0))
        #expect(viewModel.quotaFooterState == .freeSavesLeft(0))
    }

    @Test func additiveWireFieldsDecodeAndOldServersYieldNil() throws {
        let old = try JSONDecoder().decode(ReceiptQuotaSnapshot.self, from: Data(
            """
            {"entitlement":"free","scanRemaining":20,"scanCeiling":20,
             "confirmedRemaining":5,"confirmedAllowance":5,"resetAt":null}
            """.utf8
        ))
        #expect(old.creditsRemaining == nil)
        #expect(old.creditsPurchasingEnabled == nil)
        #expect(old.transactionState == nil)

        let new = try JSONDecoder().decode(ReceiptQuotaSnapshot.self, from: Data(
            """
            {"entitlement":"pro","scanRemaining":1,"scanCeiling":80,
             "confirmedRemaining":2,"confirmedAllowance":20,"resetAt":"2026-08-01T00:00:00.000Z",
             "creditsRemaining":9,"creditsScanRemaining":39,"creditsGranted":10,
             "creditsDeficit":0,"creditsPurchasingEnabled":true,"sweepIncomplete":false,
             "transactionState":"granted"}
            """.utf8
        ))
        #expect(new.creditsRemaining == 9)
        #expect(new.creditsPurchasingEnabled == true)
        #expect(new.transactionState == .granted)
    }
}
