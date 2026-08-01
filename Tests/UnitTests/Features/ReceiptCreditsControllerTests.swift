import Foundation
import Testing
@testable import Garage

/// The offer-visibility matrix (Q3-C), the poll→reconcile→terminal lifecycle, and the one
/// credits→capture coupling (latch recovery). The store client is unreachable here
/// (StoreProduct is not constructible in unit tests), so purchase flows are driven from the
/// controller's poll path via markers; the purchaser itself is pinned in
/// ReceiptCreditsPurchaseTests.
@MainActor
struct ReceiptCreditsControllerTests {
    private final class AnalyticsSpy: AnalyticsTracking {
        var events: [AnalyticsEvent] = []
        func track(_ event: AnalyticsEvent) { events.append(event) }
        func setEnabled(_: Bool) {}
    }

    private func snapshot(
        purchasingEnabled: Bool? = true,
        deficit: Int? = 0,
        transactionState: ReceiptQuotaSnapshot.TransactionState? = nil
    ) -> ReceiptQuotaSnapshot {
        var value = ReceiptQuotaSnapshot.fixture
        value.creditsPurchasingEnabled = purchasingEnabled
        value.creditsDeficit = deficit
        value.creditsRemaining = 10
        value.creditsScanRemaining = 40
        value.transactionState = transactionState
        return value
    }

    private struct Harness {
        let controller: ReceiptCreditsController
        let markers: ReceiptCreditsMarkerStore
        let service: FakeReceiptService
        let analytics: AnalyticsSpy
        let viewModel: ReceiptCaptureViewModel
    }

    private func makeHarness(uid: String? = "uid-1") -> Harness {
        let markers = ReceiptCreditsMarkerStore(defaults: nil)
        let service = FakeReceiptService(result: .success(.init(
            proposal: sampleReceiptProposal, token: nil, quota: nil
        )))
        let analytics = AnalyticsSpy()
        let viewModel = makeReceiptCaptureViewModel(service: service)
        let controller = ReceiptCreditsController(
            purchaser: ReceiptCreditsPurchaser(
                store: InertReceiptCreditsStoreClient(), markers: markers, currentUID: { uid }
            ),
            markers: markers,
            service: service,
            analytics: analytics,
            currentUID: { uid },
            sleeper: { _ in }
        )
        return Harness(
            controller: controller, markers: markers, service: service,
            analytics: analytics, viewModel: viewModel
        )
    }

    // MARK: - Marker resume → terminal transitions

    @Test func grantedMarkerResolvesRecoversTheLatchAndReports() async {
        let harness = makeHarness()
        harness.markers.add(transactionID: "txn-1", uid: "uid-1", now: .now)
        harness.service.quotaStatusResult = .success(snapshot(transactionState: .granted))

        // Latch a quota denial on the view model first: recovery must clear it.
        harness.viewModel.quotaFailure = .proMonthExhausted(resetAt: nil)
        harness.viewModel.phase = .failed(.proMonthExhausted(resetAt: nil))

        await harness.controller.resumeOutstandingMarkers(recoveringInto: harness.viewModel)

        #expect(harness.controller.purchaseState == .granted)
        #expect(harness.markers.unexpiredMarkers(uid: "uid-1", now: .now).active.isEmpty)
        #expect(harness.analytics.events.contains(.receiptCreditsGrantConfirmed))
        #expect(harness.viewModel.quotaFailure == nil)
        #expect(harness.viewModel.phase == .idle)
        #expect(harness.service.quotaStatusTransactionIDs == ["txn-1"])
    }

    @Test func refundedMarkerResolvesTerminallyWithoutRecovery() async {
        let harness = makeHarness()
        harness.markers.add(transactionID: "txn-1", uid: "uid-1", now: .now)
        harness.service.quotaStatusResult = .success(snapshot(transactionState: .refunded))
        harness.viewModel.quotaFailure = .proMonthExhausted(resetAt: nil)

        await harness.controller.resumeOutstandingMarkers(recoveringInto: harness.viewModel)

        #expect(harness.controller.purchaseState == .refunded)
        #expect(harness.markers.unexpiredMarkers(uid: "uid-1", now: .now).active.isEmpty)
        #expect(harness.analytics.events.contains(.receiptCreditsRefundObserved))
        #expect(harness.viewModel.quotaFailure != nil)
    }

    @Test func unknownStateOnResumePollsAndReconcilesWithoutSpammingMissing() async {
        let harness = makeHarness()
        harness.markers.add(transactionID: "txn-1", uid: "uid-1", now: .now)
        harness.service.quotaStatusResult = .success(snapshot(transactionState: .unknown))
        harness.service.reconcileResult = .success(snapshot(transactionState: .unknown))

        await harness.controller.resumeOutstandingMarkers(recoveringInto: harness.viewModel)

        #expect(harness.service.quotaStatusTransactionIDs == ["txn-1"])
        #expect(harness.service.reconcileTransactionIDs == ["txn-1"])
        // A still-in-flight transaction is NOT a terminal miss: `grant_missing` on every
        // sheet-appear would spam the lost-webhook ops metric (Gemini client-check #2).
        #expect(!harness.analytics.events.contains(.receiptCreditsGrantMissing))
        // The marker survives for the next appear (still inside its TTL).
        #expect(harness.markers.unexpiredMarkers(uid: "uid-1", now: .now).active.count == 1)
    }

    @Test func grantAbsorbedByDeficitDoesNotClearTheLatch() async {
        let harness = makeHarness()
        harness.markers.add(transactionID: "txn-1", uid: "uid-1", now: .now)
        // Granted, but every route is dry: the pack paid a refund deficit down.
        var dry = ReceiptQuotaSnapshot(
            entitlement: .free, scanRemaining: 0, scanCeiling: 20,
            confirmedRemaining: 0, confirmedAllowance: 5, resetAt: nil
        )
        dry.creditsRemaining = 0
        dry.creditsScanRemaining = 0
        dry.creditsPurchasingEnabled = true
        dry.transactionState = .granted
        harness.service.quotaStatusResult = .success(dry)
        harness.viewModel.quotaFailure = .freeLifetimeExhausted
        harness.viewModel.phase = .failed(.freeLifetimeExhausted)

        await harness.controller.resumeOutstandingMarkers(recoveringInto: harness.viewModel)

        // Buy must STAY available when the pack was absorbed (spec §19) — celebrating with
        // `.granted` would hide the affordance while the account is still inadmissible.
        #expect(harness.controller.purchaseState == .idle)
        #expect(harness.viewModel.quotaFailure != nil, "no admissible route -> the latch stays")
        #expect(harness.viewModel.quotaSnapshot == dry, "fresh numbers still apply")
    }

    @Test func refundedTerminalStillAppliesTheFreshSnapshot() async {
        let harness = makeHarness()
        harness.markers.add(transactionID: "txn-1", uid: "uid-1", now: .now)
        let refunded = snapshot(transactionState: .refunded)
        harness.service.quotaStatusResult = .success(refunded)

        await harness.controller.resumeOutstandingMarkers(recoveringInto: harness.viewModel)

        #expect(harness.viewModel.quotaSnapshot == refunded)
    }

    @Test func reconcileGrantRoutesThroughTheSameTerminalTransition() async {
        let harness = makeHarness()
        harness.markers.add(transactionID: "txn-1", uid: "uid-1", now: .now)
        harness.service.quotaStatusResult = .success(snapshot(transactionState: .unknown))
        harness.service.reconcileResult = .success(snapshot(transactionState: .granted))

        await harness.controller.resumeOutstandingMarkers(recoveringInto: harness.viewModel)

        #expect(harness.controller.purchaseState == .granted)
        #expect(harness.analytics.events.contains(.receiptCreditsGrantConfirmed))
    }

    @Test func expiredMarkerGetsOneFinalReconcileBeforeTerminalMiss() async {
        let harness = makeHarness()
        let old = Date.now.addingTimeInterval(-(ReceiptCreditsMarkerStore.markerTTL + 60))
        harness.markers.add(transactionID: "txn-old", uid: "uid-1", now: old)
        harness.service.quotaStatusResult = .success(snapshot(transactionState: .unknown))
        harness.service.reconcileResult = .success(snapshot(transactionState: .unknown))

        await harness.controller.resumeOutstandingMarkers(recoveringInto: harness.viewModel)

        // The final status/reconcile DID run before the marker was destroyed, and the miss
        // left a durable per-uid support flag (tri-review Sol blocker).
        #expect(harness.service.quotaStatusTransactionIDs == ["txn-old"])
        #expect(harness.service.reconcileTransactionIDs == ["txn-old"])
        #expect(harness.analytics.events == [.receiptCreditsGrantMissing])
        let after = harness.markers.unexpiredMarkers(uid: "uid-1", now: .now)
        #expect(after.active.isEmpty && after.expired.isEmpty)
        #expect(harness.markers.hasExpiredUnresolvedPurchase(uid: "uid-1"))
        #expect(harness.controller.hasExpiredUnresolvedPurchase)
    }

    @Test func twoOutstandingMarkersResolveIndependently() async {
        let harness = makeHarness()
        harness.markers.add(transactionID: "txn-1", uid: "uid-1", now: .now)
        harness.markers.add(transactionID: "txn-2", uid: "uid-1", now: .now)
        harness.service.quotaStatusResult = .success(snapshot(transactionState: .granted))

        await harness.controller.resumeOutstandingMarkers(recoveringInto: harness.viewModel)

        #expect(harness.service.quotaStatusTransactionIDs.sorted { ($0 ?? "") < ($1 ?? "") } == ["txn-1", "txn-2"])
        #expect(harness.markers.unexpiredMarkers(uid: "uid-1", now: .now).active.isEmpty)
    }

    // MARK: - Latch recovery specifics

    @Test func recoveryKeepsRetainedPagesAndRespectsANotAReceiptVerdict() {
        let service = FakeReceiptService(result: .success(.init(
            proposal: sampleReceiptProposal, token: nil, quota: nil
        )))
        let viewModel = makeReceiptCaptureViewModel(service: service)
        viewModel.addImage(Data([0x01]), source: .camera)

        viewModel.quotaFailure = .freeLifetimeExhausted
        viewModel.phase = .failed(.freeLifetimeExhausted)
        viewModel.applyCreditsRecovery(snapshot: .fixture)
        #expect(viewModel.quotaFailure == nil)
        #expect(viewModel.phase == .ready, "retained pages restore straight to ready")

        viewModel.quotaFailure = .freeLifetimeExhausted
        viewModel.notAReceiptBlocked = true
        viewModel.phase = .failed(.freeLifetimeExhausted)
        viewModel.applyCreditsRecovery(snapshot: .fixture)
        #expect(viewModel.phase == .failed(.notAReceipt), "credits cannot make the same document a receipt")
    }
}
