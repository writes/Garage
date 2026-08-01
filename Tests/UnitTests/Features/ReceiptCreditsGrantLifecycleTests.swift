import Foundation
import Testing
@testable import Garage

/// Regression pins for the 2026-08-01 tri-review blockers: offer suppression while a paid
/// purchase is unresolved, the post-TTL final reconcile, the identity lease across awaits, and
/// the nil-transaction-id recovery routing. Split from ReceiptCreditsControllerTests for the
/// file-length cap.
@MainActor
struct ReceiptCreditsGrantLifecycleTests {
    private final class AnalyticsSpy: AnalyticsTracking {
        var events: [AnalyticsEvent] = []
        func track(_ event: AnalyticsEvent) { events.append(event) }
        func setEnabled(_: Bool) {}
    }

    /// A store whose StoreKit round completes WITHOUT an SDK transaction id (observed RC edge).
    private final class NilTransactionStoreClient: ReceiptCreditsStoreClient {
        var appUserID = "uid-1"
        var isAnonymous = false
        func fetchCreditsProduct() async -> ReceiptCreditsProductFacts? {
            ReceiptCreditsProductFacts(localizedPrice: "$0.99")
        }
        func purchaseCredits() async throws -> ReceiptCreditsStorePurchase {
            .purchased(transactionID: nil)
        }
    }

    private struct Harness {
        let controller: ReceiptCreditsController
        let markers: ReceiptCreditsMarkerStore
        let service: FakeReceiptService
        let analytics: AnalyticsSpy
        let viewModel: ReceiptCaptureViewModel
    }

    private func makeHarness(
        store: any ReceiptCreditsStoreClient = InertReceiptCreditsStoreClient(),
        currentUID: @escaping () -> String? = { "uid-1" }
    ) -> Harness {
        let markers = ReceiptCreditsMarkerStore(defaults: nil)
        let service = FakeReceiptService(result: .success(.init(
            proposal: sampleReceiptProposal, token: nil, quota: nil
        )))
        let analytics = AnalyticsSpy()
        let viewModel = makeReceiptCaptureViewModel(service: service)
        let controller = ReceiptCreditsController(
            purchaser: ReceiptCreditsPurchaser(store: store, markers: markers, currentUID: currentUID),
            markers: markers,
            service: service,
            analytics: analytics,
            currentUID: currentUID,
            sleeper: { _ in }
        )
        return Harness(
            controller: controller, markers: markers, service: service,
            analytics: analytics, viewModel: viewModel
        )
    }

    private func unknownSnapshot() -> ReceiptQuotaSnapshot {
        var value = ReceiptQuotaSnapshot.fixture
        value.transactionState = .unknown
        return value
    }

    private func drySnapshot() -> ReceiptQuotaSnapshot {
        var value = ReceiptQuotaSnapshot(
            entitlement: .free, scanRemaining: 0, scanCeiling: 20,
            confirmedRemaining: 0, confirmedAllowance: 5, resetAt: nil
        )
        value.creditsRemaining = 0
        value.creditsScanRemaining = 0
        return value
    }

    @Test func unresolvedMarkerOnResumeSuppressesTheBuyOffer() async {
        let harness = makeHarness()
        harness.markers.add(transactionID: "txn-1", uid: "uid-1", now: .now)
        harness.service.quotaStatusResult = .success(unknownSnapshot())
        harness.service.reconcileResult = .success(unknownSnapshot())

        await harness.controller.resumeOutstandingMarkers(recoveringInto: harness.viewModel)

        // Buy renders only from `.idle`; re-offering while a paid grant is still pending
        // invites a second charge for the same need (tri-review Sol blocker).
        #expect(harness.controller.purchaseState == .delayed)
        #expect(harness.markers.unexpiredMarkers(uid: "uid-1", now: .now).active.count == 1)
    }

    @Test func transientErrorAtTTLKeepsTheMarkerAndSuppressesBuy() async {
        let harness = makeHarness()
        let old = Date.now.addingTimeInterval(-(ReceiptCreditsMarkerStore.markerTTL + 60))
        harness.markers.add(transactionID: "txn-old", uid: "uid-1", now: old)
        harness.service.quotaStatusResult = .failure(AppError.unknown("offline"))
        harness.service.reconcileResult = .failure(AppError.unknown("offline"))

        await harness.controller.resumeOutstandingMarkers(recoveringInto: harness.viewModel)

        // A thrown reconcile is INDETERMINATE, never a definitive miss: the repair key must
        // survive a network timeout at TTL (tri-review r2, both dissenters).
        #expect(harness.markers.unexpiredMarkers(uid: "uid-1", now: .now).expired.count == 1)
        #expect(!harness.analytics.events.contains(.receiptCreditsGrantMissing))
        #expect(!harness.controller.hasExpiredUnresolvedPurchase)
        #expect(harness.controller.purchaseState == .delayed)
    }

    @Test func expiredMarkerWhoseGrantLandedWhileClosedStillResolves() async {
        let harness = makeHarness()
        let old = Date.now.addingTimeInterval(-(ReceiptCreditsMarkerStore.markerTTL + 60))
        harness.markers.add(transactionID: "txn-old", uid: "uid-1", now: old)
        var granted = ReceiptQuotaSnapshot.fixture
        granted.creditsRemaining = 10
        granted.creditsScanRemaining = 40
        granted.transactionState = .granted
        harness.service.quotaStatusResult = .success(granted)
        harness.viewModel.quotaFailure = .proMonthExhausted(resetAt: nil)
        harness.viewModel.phase = .failed(.proMonthExhausted(resetAt: nil))

        await harness.controller.resumeOutstandingMarkers(recoveringInto: harness.viewModel)

        // TTL must not orphan a grant that landed while the app was closed (Sol blocker).
        #expect(harness.analytics.events.contains(.receiptCreditsGrantConfirmed))
        #expect(!harness.analytics.events.contains(.receiptCreditsGrantMissing))
        #expect(!harness.controller.hasExpiredUnresolvedPurchase)
        #expect(harness.viewModel.quotaFailure == nil)
    }

    @Test func accountSwitchDuringResumeNeitherAppliesNorResolves() async {
        var uid: String? = "uid-1"
        let harness = makeHarness(currentUID: { uid })
        harness.markers.add(transactionID: "txn-1", uid: "uid-1", now: .now)
        var granted = ReceiptQuotaSnapshot.fixture
        granted.transactionState = .granted
        harness.service.quotaStatusResult = .success(granted)
        harness.service.reconcileResult = .success(granted)
        // The switch lands INSIDE the awaited status call — after the lease was taken.
        harness.service.onQuotaStatus = { uid = "uid-2" }
        harness.viewModel.quotaFailure = .proMonthExhausted(resetAt: nil)

        await harness.controller.resumeOutstandingMarkers(recoveringInto: harness.viewModel)

        // The other account's snapshot must not clear this sheet's latch or resolve uid-1's
        // marker — it stays for the right account's next resume (tri-review Sol blocker).
        #expect(harness.markers.unexpiredMarkers(uid: "uid-1", now: .now).active.count == 1)
        #expect(!harness.analytics.events.contains(.receiptCreditsGrantConfirmed))
        #expect(harness.viewModel.quotaFailure != nil)
    }

    @Test func nilTransactionIDPurchaseRoutesTheRefreshThroughRecovery() async {
        let harness = makeHarness(store: NilTransactionStoreClient())
        harness.viewModel.quotaFailure = .proMonthExhausted(resetAt: nil)
        harness.viewModel.phase = .failed(.proMonthExhausted(resetAt: nil))
        var admissible = ReceiptQuotaSnapshot.fixture
        admissible.creditsRemaining = 10
        admissible.creditsScanRemaining = 40
        harness.service.quotaStatusResult = .success(admissible)

        await harness.controller.purchase(recoveringInto: harness.viewModel)

        // The landed grant clears the latch NOW, not on the next sheet open (Sol blocker).
        #expect(harness.viewModel.quotaFailure == nil)
        #expect(harness.controller.purchaseState == .granted)
        #expect(!harness.analytics.events.contains(.receiptCreditsGrantDelayed))
        // No transaction-terminal evidence — grant_confirmed must NOT fire on this path.
        #expect(!harness.analytics.events.contains(.receiptCreditsGrantConfirmed))
    }

    @Test func nilTransactionIDPurchaseStaysDelayedWhileTheGrantIsNotVisible() async {
        let harness = makeHarness(store: NilTransactionStoreClient())
        harness.viewModel.quotaFailure = .proMonthExhausted(resetAt: nil)
        harness.viewModel.phase = .failed(.proMonthExhausted(resetAt: nil))
        harness.service.quotaStatusResult = .success(drySnapshot())

        await harness.controller.purchase(recoveringInto: harness.viewModel)

        #expect(harness.viewModel.quotaFailure != nil, "no admissible route -> the latch stays")
        #expect(harness.controller.purchaseState == .delayed)
        #expect(harness.analytics.events.contains(.receiptCreditsGrantDelayed))
    }
}
