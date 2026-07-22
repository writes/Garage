import Testing
@testable import Garage

@MainActor
struct SubscriptionQueueOrderingTests {
    @Test func identityStatusAndOfferingsExecuteInRegistrationOrder() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<EntitlementSnapshot>>()
        client.loginHandler = { _ in await held.load() }
        let gateway = makeGateway(client)
        let identity = gateway.setDesiredFirebaseUID("A")
        let status = gateway.registerStatus()
        let offerings = gateway.registerOfferings()
        #expect(gateway.diagnostics.synchronousRegistrationCount == 3)
        let loginID = await held.waitForStart()
        #expect(client.callLog == ["login:A"])
        held.resolve(loginID, with: client.observed(.success(SubscriptionFixtures.inactive), uid: "A"))
        _ = await identity?.awaitValue()
        _ = await status.awaitValue()
        _ = await offerings.awaitValue()
        #expect(client.callLog == ["login:A", "status", "offerings"])
        #expect(gateway.diagnostics.queuedOperationCount == 0)
        #expect(!gateway.diagnostics.drainTaskRetained)
    }

    @Test func ticketResolvesAllWaitersWithOneTerminalValue() async {
        let ticket = OperationTicket<Int>()
        let first = Task { await ticket.awaitValue() }
        let second = Task { await ticket.awaitValue() }
        await Task.yield()
        ticket.resolve(42)
        #expect(await first.value == 42)
        #expect(await second.value == 42)
    }

    @Test func waiterCancellationDoesNotCancelRegisteredWork() async {
        let ticket = OperationTicket<String>()
        let waiter = Task { await ticket.awaitValue() }
        waiter.cancel()
        ticket.resolve("committed")
        #expect(await waiter.value == "committed")
    }

    private func makeGateway(_ client: SubscriptionMockClient) -> SubscriptionGateway {
        let relay = SubscriptionCommitRelay(reporter: SubscriptionReporterSpy())
        relay.bind(SubscriptionCommitSinkSpy())
        return SubscriptionGateway(client: client, relay: relay)
    }
}
