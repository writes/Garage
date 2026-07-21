import Testing
@testable import Garage

@MainActor
struct SubscriptionIdentityRetryTests {
    @Test func signedOutAndReadyRetryArePreResolvedNotNeeded() async {
        let gateway = makeGateway(SubscriptionMockClient())
        #expect(await gateway.requestIdentityRetry().awaitValue() == .notNeeded(.signedOut))
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        #expect(
            await gateway.requestIdentityRetry().awaitValue()
                == .notNeeded(.alreadyReady(SubscriptionFixtures.leaseA))
        )
    }

    @Test func failedIdentityDemandQueuesExactlyOneRetryAheadOfStatus() async {
        let client = SubscriptionMockClient()
        var attempts = 0
        client.loginHandler = { uid in
            attempts += 1
            if attempts == 1 {
                return client.observed(.failure(.sdk(domain: "test", code: 1, message: "offline")), uid: uid)
            }
            return client.observed(.success(SubscriptionFixtures.inactive), uid: uid)
        }
        let gateway = makeGateway(client)
        #expect(
            await gateway.setDesiredFirebaseUID("A")?.awaitValue()
                == .failed(.sdk(domain: "test", code: 1, message: "offline"))
        )
        let status = await gateway.registerStatus().awaitValue()
        #expect(status == .committed(SubscriptionFixtures.inactive))
        #expect(client.callLog == ["login:A", "login:A", "status"])
    }

    @Test func explicitSameUIDRetryAfterFailureKeepsGenerationAndUsesNewTicket() async {
        let client = SubscriptionMockClient()
        let error = SubscriptionError.sdk(domain: "test", code: 2, message: "offline")
        var attempts = 0
        client.loginHandler = { uid in
            attempts += 1
            if attempts == 1 { return client.observed(.failure(error), uid: uid) }
            return client.observed(.success(SubscriptionFixtures.inactive), uid: uid)
        }
        let gateway = makeGateway(client)
        let initial = gateway.setDesiredFirebaseUID("A")
        #expect(await initial?.awaitValue() == .failed(error))
        let retry = gateway.requestIdentityRetry()
        #expect(initial !== retry)
        #expect(await retry.awaitValue() == .applied(SubscriptionFixtures.leaseA))
        #expect(gateway.diagnostics.generation == 1)
        #expect(client.loginUIDs == ["A", "A"])
    }

    @Test func retryWhileApplyingJoinsCurrentAttempt() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<EntitlementSnapshot>>()
        client.loginHandler = { _ in await held.load() }
        let gateway = makeGateway(client)
        let initial = gateway.setDesiredFirebaseUID("A")
        let firstRetry = gateway.requestIdentityRetry()
        let secondRetry = gateway.requestIdentityRetry()
        let status = gateway.registerStatus()
        #expect(initial === firstRetry)
        #expect(firstRetry === secondRetry)
        let id = await held.waitForStart()
        held.resolve(id, with: client.observed(.success(SubscriptionFixtures.inactive), uid: "A"))
        _ = await initial?.awaitValue()
        #expect(await status.awaitValue() == .committed(SubscriptionFixtures.inactive))
        #expect(client.loginUIDs.count == 1)
        #expect(client.statusCalls == 1)
    }

    @Test func duplicateReadyAuthCallbackDoesNotTriggerRetry() async {
        let client = SubscriptionMockClient()
        let gateway = makeGateway(client)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        #expect(gateway.setDesiredFirebaseUID("A") == nil)
        #expect(client.loginUIDs == ["A"])
    }

    @Test func duplicateNilAndFailedSameUIDCallbacksStayInert() async {
        let client = SubscriptionMockClient()
        let error = SubscriptionError.sdk(domain: "test", code: 3, message: "offline")
        client.loginHandler = { uid in client.observed(.failure(error), uid: uid) }
        let gateway = makeGateway(client)
        #expect(gateway.setDesiredFirebaseUID(nil) == nil)
        #expect(gateway.setDesiredFirebaseUID(nil) == nil)
        #expect(await gateway.setDesiredFirebaseUID("A")?.awaitValue() == .failed(error))
        #expect(gateway.setDesiredFirebaseUID("A") == nil)
        #expect(client.loginUIDs == ["A"])
        #expect(client.invalidationCount == 1)
        #expect(gateway.setDesiredFirebaseUID(nil) == nil)
        #expect(gateway.setDesiredFirebaseUID(nil) == nil)
        #expect(client.invalidationCount == 2)
    }

    private func makeGateway(_ client: SubscriptionMockClient) -> SubscriptionGateway {
        let relay = SubscriptionCommitRelay(reporter: SubscriptionReporterSpy())
        relay.bind(SubscriptionCommitSinkSpy())
        return SubscriptionGateway(client: client, relay: relay)
    }
}
