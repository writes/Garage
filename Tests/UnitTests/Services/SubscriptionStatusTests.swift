import Foundation
import Testing
@testable import Garage

@MainActor
struct SubscriptionStatusTests {
    @Test func currentSuccessCommitsLeaseBearingSnapshot() async {
        let client = SubscriptionMockClient()
        client.statusHandler = { client.observed(.success(SubscriptionFixtures.active)) }
        let sink = SubscriptionCommitSinkSpy()
        let gateway = makeGateway(client, sink: sink)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        let outcome = await gateway.registerStatus().awaitValue()
        #expect(outcome == .committed(SubscriptionFixtures.active))
        #expect(
            sink.envelopes.last?.event
                == .statusCommitted(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.active)
        )
    }

    @Test func currentSDKErrorInvalidatesCacheAndEmitsCurrentError() async {
        let client = SubscriptionMockClient()
        let error = SubscriptionError.sdk(domain: "network", code: -1, message: "offline")
        client.statusHandler = { client.observed(.failure(error)) }
        let sink = SubscriptionCommitSinkSpy()
        let gateway = makeGateway(client, sink: sink)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        let invalidations = client.invalidationCount
        #expect(await gateway.registerStatus().awaitValue() == .failed(error))
        #expect(client.invalidationCount == invalidations + 1)
        #expect(sink.envelopes.last?.event == .currentError(lease: SubscriptionFixtures.leaseA, error: error))
    }

    @Test func observedMismatchRevokesAndReturnsIdentityFailure() async {
        let client = SubscriptionMockClient()
        client.statusHandler = {
            client.observed(.success(SubscriptionFixtures.active), uid: "B")
        }
        let sink = SubscriptionCommitSinkSpy()
        let gateway = makeGateway(client, sink: sink)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        #expect(await gateway.registerStatus().awaitValue() == .failed(.identityMismatch))
        #expect(sink.envelopes.last?.event == .revokedAll)
        #expect(!sink.envelopes.contains {
            $0.event == .currentError(lease: SubscriptionFixtures.leaseA, error: .identityMismatch)
        })
        #expect(gateway.diagnostics.readyLease == nil)
    }

    @Test func staleHeldStatusCannotCommitAfterAccountSwitch() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<EntitlementSnapshot>>()
        client.statusHandler = { await held.load() }
        let sink = SubscriptionCommitSinkSpy()
        let gateway = makeGateway(client, sink: sink)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        let status = gateway.registerStatus()
        let id = await held.waitForStart()
        _ = gateway.setDesiredFirebaseUID("B")
        held.resolve(id, with: client.observed(.success(SubscriptionFixtures.active), uid: "A"))
        #expect(await status.awaitValue() == .staleDiscarded)
        #expect(!sink.envelopes.contains {
            $0.event == .statusCommitted(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.active)
        })
    }

    @Test func staleSDKErrorCannotInvalidateOrEmitCurrentErrorAfterSwitch() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<EntitlementSnapshot>>()
        let error = SubscriptionError.sdk(domain: "network", code: -1, message: "offline")
        client.statusHandler = { await held.load() }
        let sink = SubscriptionCommitSinkSpy()
        let gateway = makeGateway(client, sink: sink)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        let status = gateway.registerStatus()
        let id = await held.waitForStart()
        _ = gateway.setDesiredFirebaseUID("B")
        let invalidations = client.invalidationCount
        held.resolve(id, with: client.observed(.failure(error), uid: "A"))
        #expect(await status.awaitValue() == .staleDiscarded)
        #expect(client.invalidationCount == invalidations)
        #expect(!sink.envelopes.contains {
            $0.event == .currentError(lease: SubscriptionFixtures.leaseA, error: error)
        })
    }

    @Test func guardedCommitLeaseMismatchRevokesWithoutAnalytics() {
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let service = makeTestService(client: SubscriptionMockClient(), analytics: analytics)
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.active)
        ))
        let revision = service.accountRevision
        service.commit(.init(
            stamp: 2,
            event: .statusCommitted(lease: SubscriptionFixtures.leaseB, snapshot: SubscriptionFixtures.active)
        ))
        #expect(service.accountRevision == revision + 1)
        #expect(!service.isPro)
        #expect(analytics.events.isEmpty)
    }

    @Test func voteCPreservesOnlyUnexpiredExactLeaseProofAndClearsPlans() {
        let now = Date(timeIntervalSince1970: 1_000)
        let clock = AdjustableEntitlementClock(now)
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let service = makeTestService(client: SubscriptionMockClient(), clock: clock, analytics: analytics)
        let future = EntitlementSnapshot(
            isActive: true,
            expirationDate: now.addingTimeInterval(30),
            productID: Constants.monthlyPlanIdentifier
        )
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: future)
        ))
        service.commit(.init(
            stamp: 2,
            event: .offeringsLoaded(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.plans)
        ))
        service.commit(.init(
            stamp: 3,
            event: .currentError(
                lease: SubscriptionFixtures.leaseA,
                error: .sdk(domain: "x", code: 1, message: "y")
            )
        ))
        #expect(service.isPro)
        #expect(service.plans == nil)
        clock.value = now.addingTimeInterval(31)
        service.commit(.init(
            stamp: 4,
            event: .currentError(
                lease: SubscriptionFixtures.leaseA,
                error: .sdk(domain: "x", code: 2, message: "z")
            )
        ))
        #expect(!service.isPro)
        #expect(analytics.events.isEmpty)
    }

    private func makeGateway(
        _ client: SubscriptionMockClient,
        sink: SubscriptionCommitSinkSpy
    ) -> SubscriptionGateway {
        let relay = SubscriptionCommitRelay(reporter: SubscriptionReporterSpy())
        relay.bind(sink)
        return SubscriptionGateway(client: client, relay: relay)
    }
}
