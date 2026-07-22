import Testing
@testable import Garage

@MainActor
struct SubscriptionIdentityAttemptTests {
    @Test func duplicateApplyingUIDJoinsExactTicket() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<EntitlementSnapshot>>()
        client.loginHandler = { _ in await held.load() }
        let gateway = makeGateway(client)
        let first = gateway.setDesiredFirebaseUID("A")
        let second = gateway.setDesiredFirebaseUID("A")
        #expect(first === second)
        let id = await held.waitForStart()
        held.resolve(id, with: client.observed(.success(SubscriptionFixtures.active), uid: "A"))
        #expect(await first?.awaitValue() == .applied(SubscriptionFixtures.leaseA))
        #expect(client.loginUIDs == ["A"])
    }

    @Test func supersededACompletesBeforeQueuedBAndCannotBecomeReady() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<EntitlementSnapshot>>()
        client.loginHandler = { _ in await held.load() }
        let gateway = makeGateway(client)
        let first = gateway.setDesiredFirebaseUID("A")
        let firstID = await held.waitForStart()
        let second = gateway.setDesiredFirebaseUID("B")
        held.resolve(firstID, with: client.observed(.success(SubscriptionFixtures.active), uid: "A"))
        #expect(await first?.awaitValue() == .skippedStale)
        let secondID = await held.waitForStart()
        held.resolve(secondID, with: client.observed(.success(SubscriptionFixtures.active), uid: "B"))
        #expect(await second?.awaitValue() == .applied(SubscriptionFixtures.leaseB))
        #expect(client.loginUIDs == ["A", "B"])
        #expect(gateway.diagnostics.readyLease == SubscriptionFixtures.leaseB)
    }

    @Test func inFlightABACannotAdmitTheFirstAOrCallTheQueuedB() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<EntitlementSnapshot>>()
        client.loginHandler = { _ in await held.load() }
        let gateway = makeGateway(client)
        let firstA = gateway.setDesiredFirebaseUID("A")
        let firstID = await held.waitForStart()
        let queuedB = gateway.setDesiredFirebaseUID("B")
        let currentA = gateway.setDesiredFirebaseUID("A")
        held.resolve(firstID, with: client.observed(.success(SubscriptionFixtures.active), uid: "A"))
        #expect(await firstA?.awaitValue() == .skippedStale)
        let currentID = await held.waitForStart()
        held.resolve(currentID, with: client.observed(.success(SubscriptionFixtures.active), uid: "A"))
        #expect(await queuedB?.awaitValue() == .skippedStale)
        #expect(await currentA?.awaitValue() == .applied(IdentityLease(uid: "A", generation: 3)))
        #expect(client.loginUIDs == ["A", "A"])
        #expect(gateway.diagnostics.readyLease == IdentityLease(uid: "A", generation: 3))
    }

    @Test func queuedStaleIdentityPreflightMakesZeroSDKCalls() async {
        let client = SubscriptionMockClient()
        client.loginHandler = { uid in
            client.observed(.success(SubscriptionFixtures.inactive), uid: uid)
        }
        let gateway = makeGateway(client)
        let stale = gateway.setDesiredFirebaseUID("A")
        let current = gateway.setDesiredFirebaseUID("B")
        #expect(await stale?.awaitValue() == .skippedStale)
        #expect(await current?.awaitValue() == .applied(SubscriptionFixtures.leaseB))
        #expect(client.loginUIDs == ["B"])
    }

    @Test func observedUIDMismatchFailsClosedAndRevokes() async {
        let client = SubscriptionMockClient()
        client.loginHandler = { _ in client.observed(.success(SubscriptionFixtures.active), uid: "B") }
        let sink = SubscriptionCommitSinkSpy()
        let gateway = makeGateway(client, sink: sink)
        let outcome = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        #expect(outcome == .failed(.identityMismatch))
        #expect(gateway.diagnostics.readyLease == nil)
        #expect(sink.envelopes.map(\.event) == [.revokedAll, .revokedAll])
    }

    @Test func matchingObservedUIDPreservesExactSDKFailureWithoutExtraRevocation() async {
        let client = SubscriptionMockClient()
        let error = SubscriptionError.sdk(domain: "identity", code: 41, message: "offline")
        client.loginHandler = { uid in client.observed(.failure(error), uid: uid) }
        let sink = SubscriptionCommitSinkSpy()
        let gateway = makeGateway(client, sink: sink)
        #expect(await gateway.setDesiredFirebaseUID("A")?.awaitValue() == .failed(error))
        #expect(client.loginUIDs == ["A"])
        #expect(gateway.diagnostics.readyLease == nil)
        #expect(sink.envelopes.map(\.event) == [.revokedAll])
    }

    @Test func signOutNeverCallsRevenueCatLogout() async {
        let client = SubscriptionMockClient()
        let gateway = makeGateway(client)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        let result = gateway.setDesiredFirebaseUID(nil)
        #expect(result == nil)
        #expect(client.loginUIDs == ["A"])
        #expect(gateway.diagnostics.desiredFirebaseUID == nil)
        #expect(gateway.diagnostics.readyLease == nil)
    }

    private func makeGateway(
        _ client: SubscriptionMockClient,
        sink: SubscriptionCommitSinkSpy = SubscriptionCommitSinkSpy()
    ) -> SubscriptionGateway {
        let relay = SubscriptionCommitRelay(reporter: SubscriptionReporterSpy())
        relay.bind(sink)
        return SubscriptionGateway(client: client, relay: relay)
    }
}
