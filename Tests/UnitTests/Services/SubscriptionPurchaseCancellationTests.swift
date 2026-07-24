import Foundation
import RevenueCat
import Testing
@testable import Garage

@MainActor
struct SubscriptionPurchaseCancellationTests {
    @Test func returnedCancellationIsNormalizedByAdapter() async {
        let adapter = makeAdapter { _, _, _, _, _ in
            RawPurchaseResult(userCancelled: true, snapshot: SubscriptionFixtures.active)
        }
        let result = await purchaseFirstPackage(adapter)
        #expect(result?.result == .success(.cancelled))
    }

    @Test func thrownRevenueCatCancellationIsNormalizedByAdapter() async {
        let adapter = makeAdapter { _, _, _, _, _ in throw ErrorCode.purchaseCancelledError }
        let result = await purchaseFirstPackage(adapter)
        #expect(result?.result == .success(.cancelled))
    }

    @Test func bridgedNSErrorCancellationIsNormalizedByAdapter() async {
        let adapter = makeAdapter { _, _, _, _, _ in
            throw ErrorCode.purchaseCancelledError as NSError
        }
        let result = await purchaseFirstPackage(adapter)
        #expect(result?.result == .success(.cancelled))
    }

    // FIX A: Ask-to-Buy/SCA deferral throws paymentPendingError promptly (never hangs) —
    // mirrors the cancellation detection above exactly, both raw-thrown and NSError-bridged.
    @Test func thrownRevenueCatPaymentPendingIsNormalizedByAdapter() async {
        let adapter = makeAdapter { _, _, _, _, _ in throw ErrorCode.paymentPendingError }
        let result = await purchaseFirstPackage(adapter)
        #expect(result?.result == .success(.pending))
    }

    @Test func bridgedNSErrorPaymentPendingIsNormalizedByAdapter() async {
        let adapter = makeAdapter { _, _, _, _, _ in
            throw ErrorCode.paymentPendingError as NSError
        }
        let result = await purchaseFirstPackage(adapter)
        #expect(result?.result == .success(.pending))
    }

    @Test func staleCancelledGatewayFlightRemainsCancelled() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<ClientPurchasePayload>>()
        client.offeringsHandler = { client.observed(.success(.loaded(SubscriptionFixtures.plans))) }
        client.purchaseHandler = { _, _, _, _, _ in await held.load() }
        let gateway = makeGateway(client)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        _ = await gateway.registerOfferings().awaitValue()
        let ticket = gateway.registerPurchase(SubscriptionFixtures.selection)
        let id = await held.waitForStart()
        _ = gateway.setDesiredFirebaseUID("B")
        held.resolve(id, with: client.observed(.success(.cancelled), uid: "A"))
        #expect(await ticket.awaitValue() == .cancelled)
    }

    @Test func currentUIDMismatchCancellationRevokesWithoutAnalytics() async {
        let client = SubscriptionMockClient()
        client.statusHandler = { client.observed(.success(SubscriptionFixtures.active)) }
        client.offeringsHandler = {
            client.observed(.success(.loaded(SubscriptionFixtures.plans)))
        }
        client.purchaseHandler = { _, _, _, _, _ in
            client.observed(.success(.cancelled), uid: "B")
        }
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let service = makeTestService(client: client, analytics: analytics)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        _ = await service.refreshStatus()
        _ = await service.loadOfferings()
        guard let selection = service.makeSelection(for: SubscriptionFixtures.package) else {
            Issue.record("Expected current account selection")
            return
        }
        let revision = service.accountRevision
        #expect(await service.purchase(selection) == .cancelled)
        #expect(service.accountRevision == revision + 1)
        #expect(!service.isPro)
        #expect(analytics.events.isEmpty)
    }

    private func makeAdapter(
        purchase: @escaping DebugPurchaseExecutor
    ) -> LiveRevenueCatClient {
        LiveRevenueCatClient(
            observedUserID: { "A" },
            offeringsExecutor: {
                RawOfferingFacts(
                    offeringID: "default",
                    packages: [RawPackageFacts(
                        packageID: "monthly", productID: Constants.monthlyPlanIdentifier,
                        title: "Monthly", packageDescription: "Known", localizedPrice: "$4.99",
                        period: .init(value: 1, unit: .month)
                    )]
                )
            },
            purchaseExecutor: purchase
        )
    }

    private func purchaseFirstPackage(
        _ adapter: LiveRevenueCatClient
    ) async -> RevenueCatObserved<ClientPurchasePayload>? {
        let offering = await adapter.offerings()
        guard case .success(.loaded(let snapshot)) = offering.result,
              let package = snapshot.packages.first else { return nil }
        return await adapter.purchase(
            handle: package.handle, offeringID: package.offeringID,
            packageID: package.packageID, productID: package.productID,
            analyticsProduct: package.analyticsProduct
        )
    }

    private func makeGateway(_ client: SubscriptionMockClient) -> SubscriptionGateway {
        let relay = SubscriptionCommitRelay(reporter: SubscriptionReporterSpy())
        relay.bind(SubscriptionCommitSinkSpy())
        return SubscriptionGateway(client: client, relay: relay)
    }
}
