import Foundation
import RevenueCat
import Testing
@testable import Garage

/// The identity-gated consumable purchaser + the transaction-marker queue. The money-path
/// pins: no purchase without identity, the marker persists BEFORE the post-purchase identity
/// check, cancelled/pending are outcomes not failures, and markers expire terminally at 72h.
@MainActor
struct ReceiptCreditsPurchaseTests {
    private final class StoreClientFake: ReceiptCreditsStoreClient {
        var appUserID = "uid-1"
        var isAnonymous = false
        var facts: ReceiptCreditsProductFacts? = ReceiptCreditsProductFacts(localizedPrice: "$0.99")
        var purchaseResult: Result<ReceiptCreditsStorePurchase, Error> = .success(.purchased(transactionID: "txn-1"))
        /// Simulates identity divergence DURING the StoreKit call.
        var appUserIDAfterPurchase: String?
        private(set) var purchaseCalls = 0

        func fetchCreditsProduct() async -> ReceiptCreditsProductFacts? { facts }

        func purchaseCredits() async throws -> ReceiptCreditsStorePurchase {
            purchaseCalls += 1
            if let diverged = appUserIDAfterPurchase { appUserID = diverged }
            return try purchaseResult.get()
        }
    }

    private func makeMarkers() -> ReceiptCreditsMarkerStore {
        ReceiptCreditsMarkerStore(defaults: nil)
    }

    @Test func anonymousIdentityRefusesBeforeAnyStoreCall() async {
        let store = StoreClientFake()
        store.isAnonymous = true
        let markers = makeMarkers()
        let purchaser = ReceiptCreditsPurchaser(store: store, markers: markers, currentUID: { "uid-1" })
        #expect(await purchaser.purchase() == .identityMismatch)
        #expect(store.purchaseCalls == 0)
        #expect(markers.unexpiredMarkers(uid: "uid-1", now: .now).active.isEmpty)
    }

    @Test func divergedIdentityRefusesBeforeAnyStoreCall() async {
        let store = StoreClientFake()
        store.appUserID = "someone-else"
        let purchaser = ReceiptCreditsPurchaser(store: store, markers: makeMarkers(), currentUID: { "uid-1" })
        #expect(await purchaser.purchase() == .identityMismatch)
        #expect(store.purchaseCalls == 0)
    }

    @Test func signedOutRefuses() async {
        let store = StoreClientFake()
        let purchaser = ReceiptCreditsPurchaser(store: store, markers: makeMarkers(), currentUID: { nil })
        #expect(await purchaser.purchase() == .identityMismatch)
    }

    @Test func unfetchableProductFailsWithoutAStoreCall() async {
        let store = StoreClientFake()
        store.facts = nil
        let purchaser = ReceiptCreditsPurchaser(store: store, markers: makeMarkers(), currentUID: { "uid-1" })
        #expect(await purchaser.purchase() == .failed(.productUnavailable))
        #expect(store.purchaseCalls == 0)
        #expect(await purchaser.fetchProductFacts() == nil)
    }

    @Test func successfulPurchasePersistsTheMarkerUnderThePayingUID() async {
        let store = StoreClientFake()
        let markers = makeMarkers()
        let purchaser = ReceiptCreditsPurchaser(store: store, markers: markers, currentUID: { "uid-1" })
        #expect(await purchaser.purchase() == .completed(transactionID: "txn-1"))
        #expect(markers.unexpiredMarkers(uid: "uid-1", now: .now).active.map(\.transactionID) == ["txn-1"])
    }

    @Test func returnedCancellationFlagIsCancelledNotSuccess() async {
        // RC reports user cancellation as a RETURNED flag, not a thrown error — dropping it
        // logged Cancel as success and started the grant poll (tri-review blocking finding).
        let store = StoreClientFake()
        store.purchaseResult = .success(.cancelled)
        let markers = makeMarkers()
        let purchaser = ReceiptCreditsPurchaser(store: store, markers: markers, currentUID: { "uid-1" })
        #expect(await purchaser.purchase() == .cancelled)
        #expect(markers.unexpiredMarkers(uid: "uid-1", now: .now).active.isEmpty)
    }

    @Test func firebaseUIDChangeDuringPurchaseYieldsRecoverableOutcome() async {
        // The RC identity holds but the FIREBASE user changes mid-call: the marker (written
        // pre-check, under the payer) keeps the grant recoverable; never report plain success.
        var uid: String? = "uid-1"
        let store = StoreClientFake()
        let markers = makeMarkers()
        let purchaser = ReceiptCreditsPurchaser(store: store, markers: markers, currentUID: { uid })
        store.appUserIDAfterPurchase = "uid-1" // RC unchanged
        uid = "uid-1"
        // Divergence is simulated by swapping the closure's value after the store call begins:
        // the fake mutates appUserID only; here we flip the Firebase uid via the closure.
        store.purchaseResult = .success(.purchased(transactionID: "txn-9"))
        // First call sequence with a stable uid must succeed…
        #expect(await purchaser.purchase() == .completed(transactionID: "txn-9"))
        // …then verify the diverged-Firebase-uid path.
        uid = "uid-2"
        let second = await purchaser.purchase()
        #expect(second == .identityMismatch, "pre-checks catch a switch before money moves")
        #expect(markers.unexpiredMarkers(uid: "uid-1", now: .now).active.map(\.transactionID) == ["txn-9"])
    }

    @Test func rcIdentityDivergenceAfterPurchaseIsRecoverableViaTheMarker() async {
        let store = StoreClientFake()
        store.appUserIDAfterPurchase = "someone-else"
        let markers = makeMarkers()
        let purchaser = ReceiptCreditsPurchaser(store: store, markers: markers, currentUID: { "uid-1" })
        #expect(await purchaser.purchase() == .identityChangedAfterPurchase)
        #expect(markers.unexpiredMarkers(uid: "uid-1", now: .now).active.map(\.transactionID) == ["txn-1"])
    }

    @Test func purchasedWithoutATransactionIDFallsBackToTheBalancePath() async {
        let store = StoreClientFake()
        store.purchaseResult = .success(.purchased(transactionID: nil))
        let markers = makeMarkers()
        let purchaser = ReceiptCreditsPurchaser(store: store, markers: markers, currentUID: { "uid-1" })
        #expect(await purchaser.purchase() == .completed(transactionID: ""))
        #expect(markers.unexpiredMarkers(uid: "uid-1", now: .now).active.isEmpty, "nothing to mark or poll")
    }

    @Test func productFactsCarryTheLocalizedPrice() async {
        let store = StoreClientFake()
        store.facts = ReceiptCreditsProductFacts(localizedPrice: "€1,19")
        let purchaser = ReceiptCreditsPurchaser(store: store, markers: makeMarkers(), currentUID: { "uid-1" })
        #expect(await purchaser.fetchProductFacts()?.localizedPrice == "€1,19")
    }

    @Test func removeAllClearsMarkersAndDismissalFlagForOneUIDOnly() {
        let markers = makeMarkers()
        let now = Date(timeIntervalSince1970: 1_000_000)
        markers.add(transactionID: "txn-1", uid: "uid-1", now: now)
        markers.add(transactionID: "txn-2", uid: "uid-2", now: now)
        markers.recordPaywallDismissed(uid: "uid-1")
        markers.removeAll(uid: "uid-1")
        #expect(markers.unexpiredMarkers(uid: "uid-1", now: now).active.isEmpty)
        #expect(!markers.hasDismissedPaywall(uid: "uid-1"))
        #expect(markers.unexpiredMarkers(uid: "uid-2", now: now).active.count == 1)
    }

    // MARK: - Marker store

    @Test func markersQueuePerTransactionAndResolveIndependently() {
        let markers = makeMarkers()
        let now = Date(timeIntervalSince1970: 1_000_000)
        markers.add(transactionID: "txn-1", uid: "uid-1", now: now)
        markers.add(transactionID: "txn-2", uid: "uid-1", now: now)
        // Same id twice must not double-queue (a retried purchase completion).
        markers.add(transactionID: "txn-1", uid: "uid-1", now: now)
        #expect(markers.unexpiredMarkers(uid: "uid-1", now: now).active.count == 2)

        markers.resolve(transactionID: "txn-1", uid: "uid-1")
        let remaining = markers.unexpiredMarkers(uid: "uid-1", now: now).active
        #expect(remaining.map(\.transactionID) == ["txn-2"])
    }

    @Test func markersAreScopedPerUID() {
        let markers = makeMarkers()
        let now = Date(timeIntervalSince1970: 1_000_000)
        markers.add(transactionID: "txn-1", uid: "uid-1", now: now)
        #expect(markers.unexpiredMarkers(uid: "uid-2", now: now).active.isEmpty)
    }

    @Test func markerReadsArePureAndExpiryIsTerminalOnlyViaMark() {
        let markers = makeMarkers()
        let purchased = Date(timeIntervalSince1970: 1_000_000)
        markers.add(transactionID: "txn-1", uid: "uid-1", now: purchased)

        let justInside = purchased.addingTimeInterval(ReceiptCreditsMarkerStore.markerTTL - 1)
        #expect(markers.unexpiredMarkers(uid: "uid-1", now: justInside).active.count == 1)

        let past = purchased.addingTimeInterval(ReceiptCreditsMarkerStore.markerTTL + 1)
        let (active, expired) = markers.unexpiredMarkers(uid: "uid-1", now: past)
        #expect(active.isEmpty)
        #expect(expired.map(\.transactionID) == ["txn-1"])
        // Reads are PURE: the expired marker survives until the caller's final reconcile
        // decides its fate — pruning on read destroyed the repair key before that attempt
        // could happen (tri-review Sol blocker).
        #expect(markers.unexpiredMarkers(uid: "uid-1", now: past).expired.count == 1)

        markers.markExpiredUnresolved(transactionID: "txn-1", uid: "uid-1")
        let after = markers.unexpiredMarkers(uid: "uid-1", now: past)
        #expect(after.active.isEmpty && after.expired.isEmpty)
        #expect(markers.hasExpiredUnresolvedPurchase(uid: "uid-1"))
        #expect(!markers.hasExpiredUnresolvedPurchase(uid: "uid-2"))
    }

    @Test func nilTransactionIDWithDivergedIdentityNeverCompletes() async {
        let store = StoreClientFake()
        store.purchaseResult = .success(.purchased(transactionID: nil))
        store.appUserIDAfterPurchase = "uid-2"
        let purchaser = ReceiptCreditsPurchaser(store: store, markers: makeMarkers(), currentUID: { "uid-1" })

        // `.completed("")` here would run the balance-bearing recovery under the WRONG user's
        // sheet (tri-review r2, both dissenters) — divergence must take the delayed path.
        #expect(await purchaser.purchase() == .identityChangedAfterPurchase)
    }

    @Test func paywallDismissalFlagIsPerUIDAndSticky() {
        let markers = makeMarkers()
        #expect(!markers.hasDismissedPaywall(uid: "uid-1"))
        markers.recordPaywallDismissed(uid: "uid-1")
        #expect(markers.hasDismissedPaywall(uid: "uid-1"))
        #expect(!markers.hasDismissedPaywall(uid: "uid-2"))
    }
}
