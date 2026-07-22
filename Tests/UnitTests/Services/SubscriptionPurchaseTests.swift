import Foundation
import Testing
@testable import Garage

@MainActor
struct SubscriptionPurchaseTests {
    @Test func activePurchaseCommitsProofAndExactlyOnceAnalytics() async {
        let client = configuredClient()
        client.purchaseHandler = { _, _, _, _, _ in
            client.observed(.success(.completed(snapshot: SubscriptionFixtures.active, product: .monthly)))
        }
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let service = makeTestService(client: client, analytics: analytics)
        let selection = await prepareSelection(service)
        guard let selection else { return }
        #expect(await service.purchase(selection) == .activePro)
        #expect(service.isPro)
        #expect(analytics.events == [.purchaseCompleted(productID: .monthly)])
    }

    @Test func inactivePurchaseCommitsNoEntitlementAndNoAnalytics() async {
        let client = configuredClient()
        client.purchaseHandler = { _, _, _, _, _ in
            client.observed(.success(.completed(snapshot: SubscriptionFixtures.inactive, product: .monthly)))
        }
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let service = makeTestService(client: client, analytics: analytics)
        guard let selection = await prepareSelection(service) else { return }
        #expect(await service.purchase(selection) == .noEntitlement)
        #expect(!service.isPro)
        #expect(analytics.events.isEmpty)
    }

    @Test func staleCompletionRequiresReconciliationAndCannotGrant() async {
        let client = configuredClient()
        let held = HeldValue<RevenueCatObserved<ClientPurchasePayload>>()
        client.purchaseHandler = { _, _, _, _, _ in await held.load() }
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let service = makeTestService(client: client, analytics: analytics)
        guard let selection = await prepareSelection(service) else { return }
        let task = Task { await service.purchase(selection) }
        let id = await held.waitForStart()
        _ = service.setDesiredFirebaseUID("B")
        held.resolve(id, with: client.observed(.success(.completed(
            snapshot: SubscriptionFixtures.active,
            product: .monthly
        )), uid: "A"))
        #expect(await task.value == .reconciliationRequired)
        #expect(service.pendingReconciliation == .purchase)
        #expect(!service.isPro)
        #expect(analytics.events.isEmpty)
    }

    @Test func pendingReconciliationBlocksSelectionAndProviderPurchase() async {
        let client = configuredClient()
        let store = SubscriptionReconciliationStore()
        store.observePurchase(.reconciliationRequired, uid: "A")
        let service = makeTestService(client: client, reconciliationStore: store)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        _ = await service.loadOfferings()

        #expect(service.makeSelection(for: SubscriptionFixtures.package) == nil)
        #expect(await service.purchase(SubscriptionFixtures.selection) == .reconciliationRequired)
        #expect(client.purchaseCalls == 0)
        #expect(service.pendingReconciliation == .purchase)
    }

    @Test func expiredActiveCompletionDowngradesWithoutSuccessAnalytics() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let client = configuredClient()
        let expired = EntitlementSnapshot(
            isActive: true,
            expirationDate: now,
            productID: Constants.monthlyPlanIdentifier
        )
        client.purchaseHandler = { _, _, _, _, _ in
            client.observed(.success(.completed(snapshot: expired, product: .monthly)))
        }
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let service = makeTestService(
            client: client,
            clock: AdjustableEntitlementClock(now),
            analytics: analytics
        )
        guard let selection = await prepareSelection(service) else { return }
        #expect(await service.purchase(selection) == .noEntitlement)
        #expect(!service.isPro)
        #expect(analytics.events.isEmpty)
    }

    @Test func callerCannotPurchaseASelectionThatIsNotStored() async {
        let client = configuredClient()
        let service = makeTestService(client: client)
        _ = await prepareSelection(service)
        let altered = PackageSelection(
            lease: SubscriptionFixtures.leaseA,
            handle: SubscriptionFixtures.selection.handle,
            offeringID: "altered", packageID: SubscriptionFixtures.selection.packageID,
            productID: SubscriptionFixtures.selection.productID, analyticsProduct: .monthly
        )
        #expect(await service.purchase(altered) == .selectionInvalidated)
        #expect(client.purchaseCalls == 0)
    }

    private func configuredClient() -> SubscriptionMockClient {
        let client = SubscriptionMockClient()
        client.offeringsHandler = { client.observed(.success(.loaded(SubscriptionFixtures.plans))) }
        return client
    }

    private func prepareSelection(_ service: PurchaseService) async -> PackageSelection? {
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        _ = await service.loadOfferings()
        return service.makeSelection(for: SubscriptionFixtures.package)
    }
}
