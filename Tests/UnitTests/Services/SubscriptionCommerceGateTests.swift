import Testing
@testable import Garage

@MainActor
struct SubscriptionCommerceGateTests {
    @Test func busyPurchaseMintsNoSecondFlightAndCallsSDKOnce() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<ClientPurchasePayload>>()
        client.offeringsHandler = { client.observed(.success(.loaded(SubscriptionFixtures.plans))) }
        client.purchaseHandler = { _, _, _, _, _ in await held.load() }
        let gateway = makeGateway(client)
        await readyWithOfferings(gateway)
        let first = gateway.registerPurchase(SubscriptionFixtures.selection)
        let second = gateway.registerPurchase(SubscriptionFixtures.selection)
        #expect(await second.awaitValue() == .busy)
        let id = await held.waitForStart()
        held.resolve(id, with: client.observed(.success(.completed(
            snapshot: SubscriptionFixtures.active,
            product: .monthly
        ))))
        #expect(await first.awaitValue() == .activePro)
        #expect(client.purchaseCalls == 1)
        #expect(gateway.diagnostics.commerceFlightID == nil)
    }

    @Test func purchaseFlightMakesRestoreBusyAndViceVersa() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<ClientPurchasePayload>>()
        client.offeringsHandler = { client.observed(.success(.loaded(SubscriptionFixtures.plans))) }
        client.purchaseHandler = { _, _, _, _, _ in await held.load() }
        let gateway = makeGateway(client)
        await readyWithOfferings(gateway)
        let purchase = gateway.registerPurchase(SubscriptionFixtures.selection)
        #expect(await gateway.registerRestore().awaitValue() == .busy)
        let id = await held.waitForStart()
        held.resolve(id, with: client.observed(.success(.cancelled)))
        #expect(await purchase.awaitValue() == .cancelled)
    }

    @Test func restoreFlightMakesPurchaseBusyAndSkipsPurchaseSDK() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<EntitlementSnapshot>>()
        client.offeringsHandler = {
            client.observed(.success(.loaded(SubscriptionFixtures.plans)))
        }
        client.restoreHandler = { await held.load() }
        let gateway = makeGateway(client)
        await readyWithOfferings(gateway)
        let restore = gateway.registerRestore()
        let purchase = gateway.registerPurchase(SubscriptionFixtures.selection)
        #expect(await purchase.awaitValue() == .busy)
        #expect(client.purchaseCalls == 0)
        let id = await held.waitForStart()
        held.resolve(id, with: client.observed(.success(SubscriptionFixtures.inactive)))
        #expect(await restore.awaitValue() == .noActiveEntitlement)
        #expect(client.restoreCalls == 1)
        #expect(gateway.diagnostics.commerceFlightID == nil)
    }

    @Test func staleSelectionEpochIsRejectedBeforeSDK() async {
        let client = SubscriptionMockClient()
        client.offeringsHandler = { client.observed(.success(.loaded(SubscriptionFixtures.plans))) }
        let gateway = makeGateway(client)
        await readyWithOfferings(gateway)
        let invalid = PackageSelection(
            lease: SubscriptionFixtures.leaseA,
            handle: PackageHandle(cacheEpoch: 2, ordinal: 1),
            offeringID: "default", packageID: "$rc_monthly",
            productID: Constants.monthlyPlanIdentifier, analyticsProduct: .monthly
        )
        #expect(await gateway.registerPurchase(invalid).awaitValue() == .selectionInvalidated)
        #expect(client.purchaseCalls == 0)
        #expect(gateway.diagnostics.commerceFlightID == nil)
    }

    @Test func mismatchedSelectionLeaseIsRejectedBeforeSDK() async {
        let client = SubscriptionMockClient()
        client.offeringsHandler = {
            client.observed(.success(.loaded(SubscriptionFixtures.plans)))
        }
        let gateway = makeGateway(client)
        await readyWithOfferings(gateway)
        let invalid = PackageSelection(
            lease: SubscriptionFixtures.leaseB,
            handle: SubscriptionFixtures.selection.handle,
            offeringID: SubscriptionFixtures.selection.offeringID,
            packageID: SubscriptionFixtures.selection.packageID,
            productID: SubscriptionFixtures.selection.productID,
            analyticsProduct: .monthly
        )
        #expect(await gateway.registerPurchase(invalid).awaitValue() == .selectionInvalidated)
        #expect(client.purchaseCalls == 0)
        #expect(gateway.diagnostics.commerceFlightID == nil)
    }

    private func readyWithOfferings(_ gateway: SubscriptionGateway) async {
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        _ = await gateway.registerOfferings().awaitValue()
    }

    private func makeGateway(_ client: SubscriptionMockClient) -> SubscriptionGateway {
        let relay = SubscriptionCommitRelay(reporter: SubscriptionReporterSpy())
        relay.bind(SubscriptionCommitSinkSpy())
        return SubscriptionGateway(client: client, relay: relay)
    }
}
