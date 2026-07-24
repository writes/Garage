import Foundation
import Testing
@testable import Garage

// FIX A (audited money-path fix): Ask-to-Buy/SCA deferred purchases must route to a calm
// "pending" outcome end to end — never the "you may have been charged" failure/reconciliation
// copy — and must resolve the operation ticket + clear busy state like any other terminal
// purchase outcome.
@MainActor
struct SubscriptionPurchasePendingTests {
    @Test func classifierRoutesPendingPayloadToPendingOutcome() async {
        let client = configuredClient()
        client.purchaseHandler = { _, _, _, _, _ in client.observed(.success(.pending)) }
        let gateway = makeGateway(client)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        _ = await gateway.registerOfferings().awaitValue()
        #expect(await gateway.registerPurchase(SubscriptionFixtures.selection).awaitValue() == .pending)
    }

    @Test func pendingPurchaseResolvesTicketClearsSelectionAndCreatesNoReconciliation() async {
        let client = configuredClient()
        client.purchaseHandler = { _, _, _, _, _ in client.observed(.success(.pending)) }
        let service = makeTestService(client: client)
        guard let selection = await prepareSelection(service) else {
            Issue.record("Expected a stored selection")
            return
        }
        #expect(await service.purchase(selection) == .pending)
        #expect(!service.isPro)
        #expect(service.pendingReconciliation == nil)
        // A stale selection is now rejected — proves storedSelection was cleared on resolution.
        #expect(await service.purchase(selection) == .selectionInvalidated)
    }

    @Test func mismatchedIdentityPendingRevokesWithoutReconciliation() async {
        let client = configuredClient()
        client.purchaseHandler = { _, _, _, _, _ in client.observed(.success(.pending), uid: "B") }
        let service = makeTestService(client: client)
        guard let selection = await prepareSelection(service) else {
            Issue.record("Expected a stored selection")
            return
        }
        let revision = service.accountRevision
        #expect(await service.purchase(selection) == .pending)
        #expect(service.accountRevision == revision + 1)
        #expect(service.pendingReconciliation == nil)
    }

    @Test func viewModelPresentsCalmNoticeNotFailureAndClearsBusy() async {
        let facade = ScriptedSubscriptionFacade()
        facade.selection = SubscriptionFixtures.selection
        facade.purchases = [.pending]
        let model = SubscriptionViewModel(service: facade)

        await model.choosePackageTapped(SubscriptionFixtures.package)

        #expect(model.state == .pending)
        #expect(model.presentationOutput == .notice(.pending))
        #expect(!model.isBusy)
        #expect(model.diagnostics.activeActionID == nil)
        #expect(
            SubscriptionNotice.pending.text.contains("Waiting for approval")
        )
        #expect(!SubscriptionNotice.pending.text.contains("Restore Purchases"))
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

    private func makeGateway(_ client: SubscriptionMockClient) -> SubscriptionGateway {
        let relay = SubscriptionCommitRelay(reporter: SubscriptionReporterSpy())
        relay.bind(SubscriptionCommitSinkSpy())
        return SubscriptionGateway(client: client, relay: relay)
    }
}
