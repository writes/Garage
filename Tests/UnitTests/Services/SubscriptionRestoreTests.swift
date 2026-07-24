import Foundation
import Testing
@testable import Garage

@MainActor
struct SubscriptionRestoreTests {
    @Test func activeRestoreCommitsAndTracksExactlyOnce() async {
        let client = SubscriptionMockClient()
        client.restoreHandler = { client.observed(.success(SubscriptionFixtures.active)) }
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let service = makeTestService(client: client, analytics: analytics)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        #expect(await service.restore() == .activeEntitlement)
        #expect(service.isPro)
        #expect(analytics.events == [.purchaseRestored])
    }

    @Test func inactiveRestoreDoesNotTrackOrGrant() async {
        let client = SubscriptionMockClient()
        client.restoreHandler = { client.observed(.success(SubscriptionFixtures.inactive)) }
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let service = makeTestService(client: client, analytics: analytics)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        #expect(await service.restore() == .noActiveEntitlement)
        #expect(!service.isPro)
        #expect(analytics.events.isEmpty)
    }

    @Test func expiredRawActiveRestoreDowngradesAndDoesNotTrack() async {
        let now = Date(timeIntervalSince1970: 100)
        let client = SubscriptionMockClient()
        client.restoreHandler = {
            client.observed(.success(.init(
                isActive: true,
                expirationDate: now,
                productID: Constants.monthlyPlanIdentifier
            )))
        }
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let service = makeTestService(
            client: client,
            clock: AdjustableEntitlementClock(now),
            analytics: analytics
        )
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        #expect(await service.restore() == .noActiveEntitlement)
        #expect(!service.isPro)
        #expect(analytics.events.isEmpty)
    }

    @Test func currentObservedUIDMismatchRevokesAndDoesNotTrack() async {
        let client = SubscriptionMockClient()
        client.restoreHandler = {
            client.observed(.success(SubscriptionFixtures.active), uid: "B")
        }
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let service = makeTestService(client: client, analytics: analytics)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        let revision = service.accountRevision
        #expect(await service.restore() == .reconciliationRequired)
        #expect(service.accountRevision == revision + 1)
        #expect(!service.isPro)
        #expect(analytics.events.isEmpty)
    }

    @Test func staleRestoreRequiresReconciliationWithoutDuplicateRevocation() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<EntitlementSnapshot>>()
        client.restoreHandler = { await held.load() }
        let sink = SubscriptionCommitSinkSpy()
        let relay = SubscriptionCommitRelay(reporter: SubscriptionReporterSpy())
        relay.bind(sink)
        let gateway = SubscriptionGateway(client: client, relay: relay)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        let restore = gateway.registerRestore()
        let id = await held.waitForStart()
        _ = gateway.setDesiredFirebaseUID("B")
        let revocations = sink.envelopes.filter { $0.event == .revokedAll }.count
        held.resolve(id, with: client.observed(.success(SubscriptionFixtures.active), uid: "A"))
        #expect(await restore.awaitValue() == .reconciliationRequired)
        #expect(sink.envelopes.filter { $0.event == .revokedAll }.count == revocations)
    }

    @Test func pendingPurchaseClearsOnlyAfterIdentityCorrectActiveRestore() {
        let store = SubscriptionReconciliationStore()
        store.observePurchase(.reconciliationRequired, uid: "account-A")

        store.observeRestore(.reconciliationRequired, uid: "account-B") // already pending: no-op
        #expect(store.kind == .purchase)
        store.observeRestore(.activeEntitlement, uid: "account-B") // wrong identity: still blocked
        #expect(store.kind == .purchase)
        store.observeRestore(.activeEntitlement, uid: "account-A") // correct identity: clears
        #expect(store.kind == nil)
    }

    // FIX C: a genuinely identity-correct "nothing to restore" result is a legitimate
    // resolution regardless of which kind of reconciliation was pending — it must not leave a
    // purchase-kind block permanently gating future purchases.
    @Test func matchingIdentityNoActiveEntitlementClearsPendingRegardlessOfStoredKind() {
        let store = SubscriptionReconciliationStore()
        store.observePurchase(.reconciliationRequired, uid: "account-A")
        store.observeRestore(.noActiveEntitlement, uid: "account-B") // wrong identity: still blocked
        #expect(store.kind == .purchase)
        store.observeRestore(.noActiveEntitlement, uid: "account-A") // correct identity: clears (NEW)
        #expect(store.kind == nil)

        let restoreStore = SubscriptionReconciliationStore()
        restoreStore.observeRestore(.reconciliationRequired, uid: "account-A")
        restoreStore.observeRestore(.noActiveEntitlement, uid: "account-B") // wrong identity
        #expect(restoreStore.kind == .restore)
        restoreStore.observeRestore(.noActiveEntitlement, uid: "account-A") // correct identity: clears
        #expect(restoreStore.kind == nil) // unchanged: this path already cleared pre-fix
    }

    @Test func realServiceWrongAccountRestoreCannotClearPendingPurchase() async {
        let client = SubscriptionMockClient()
        let store = SubscriptionReconciliationStore()
        store.observePurchase(.reconciliationRequired, uid: "A")
        let service = makeTestService(client: client, reconciliationStore: store)
        _ = await service.setDesiredFirebaseUID("B")?.awaitValue()
        client.restoreHandler = { client.observed(.success(SubscriptionFixtures.inactive)) }

        #expect(await service.restore() == .noActiveEntitlement)
        #expect(service.pendingReconciliation == .purchase)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        client.restoreHandler = { client.observed(.success(SubscriptionFixtures.active)) }
        #expect(await service.restore() == .activeEntitlement)
        #expect(service.pendingReconciliation == nil)
    }

    // FIX C, service level: a purchase-kind reconciliation used to permanently gate the
    // purchase path once the correct account genuinely had nothing to restore. It must clear.
    @Test func realServiceCorrectIdentityNoActiveEntitlementClearsPurchaseKindReconciliation() async {
        let client = SubscriptionMockClient()
        let store = SubscriptionReconciliationStore()
        store.observePurchase(.reconciliationRequired, uid: "A")
        let service = makeTestService(client: client, reconciliationStore: store)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        client.restoreHandler = { client.observed(.success(SubscriptionFixtures.inactive)) }

        #expect(service.pendingReconciliation == .purchase)
        #expect(await service.restore() == .noActiveEntitlement)
        #expect(service.pendingReconciliation == nil)
    }

    @Test func reconciliationPersistsWithoutStoringRawIdentity() throws {
        let suite = "Garage.Reconciliation.\(UUID().uuidString)"
        let key = "pending"
        let uid = "private-firebase-identity-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defer { defaults.removeObject(forKey: key) }

        let first = SubscriptionReconciliationStore(defaults: defaults, key: key)
        first.observePurchase(.reconciliationRequired, uid: uid)
        let encoded = try #require(defaults.data(forKey: key))
        let storedText = try #require(String(bytes: encoded, encoding: .utf8))
        #expect(!storedText.contains(uid))

        let relaunched = SubscriptionReconciliationStore(defaults: defaults, key: key)
        #expect(relaunched.kind == .purchase)
        relaunched.observeRestore(.activeEntitlement, uid: uid)
        #expect(relaunched.kind == nil)
    }
}
