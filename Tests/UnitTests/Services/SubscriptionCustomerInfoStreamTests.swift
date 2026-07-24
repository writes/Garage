import Foundation
import Testing
@testable import Garage

// FIX D (audited money-path fix): no push channel previously existed for entitlement changes,
// so a later-approved Ask-to-Buy purchase or a server-side entitlement change only surfaced on
// relaunch or paywall reopen. SubscriptionGateway now consumes a stream of customer-info
// updates and re-runs the existing status-registration path on each one, converging entitlement
// state without user action.
@MainActor
struct SubscriptionCustomerInfoStreamTests {
    @Test func yieldedActiveCustomerInfoFlipsProOnWithoutManualRefresh() async {
        let client = SubscriptionMockClient()
        client.loginHandler = { uid in client.observed(.success(SubscriptionFixtures.inactive), uid: uid) }
        let service = makeTestService(client: client)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        #expect(!service.isPro)

        client.statusHandler = { client.observed(.success(SubscriptionFixtures.active)) }
        client.yieldCustomerInfoUpdate(SubscriptionFixtures.active)

        let becamePro = await eventually { service.isPro }
        #expect(becamePro)
        #expect(client.statusCalls == 1)
    }

    @Test func duplicateYieldsAreIdempotent() async {
        let client = SubscriptionMockClient()
        client.loginHandler = { uid in client.observed(.success(SubscriptionFixtures.inactive), uid: uid) }
        let reporter = SubscriptionReporterSpy()
        let service = makeTestService(client: client, reporter: reporter)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()

        client.statusHandler = { client.observed(.success(SubscriptionFixtures.active)) }
        for _ in 0..<3 { client.yieldCustomerInfoUpdate(SubscriptionFixtures.active) }

        let drained = await eventually { client.statusCalls >= 3 }
        #expect(drained)
        #expect(service.isPro) // repeated application converges to the same correct state
        #expect(reporter.violations.isEmpty) // no double-resolve / integrity fault from repeats
    }

    @Test func reIdentifyDoesNotStartASecondObservationLoop() async {
        let client = SubscriptionMockClient()
        client.loginHandler = { uid in client.observed(.success(SubscriptionFixtures.inactive), uid: uid) }
        let service = makeTestService(client: client)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        _ = service.setDesiredFirebaseUID(nil)
        _ = await service.setDesiredFirebaseUID("B")?.awaitValue()
        #expect(client.customerInfoStreamRequests == 1)
    }

    @Test func observationTaskDoesNotRetainOrOutliveTheGateway() async {
        let client = SubscriptionMockClient()
        weak var weakGateway: SubscriptionGateway?
        do {
            let relay = SubscriptionCommitRelay(reporter: SubscriptionReporterSpy())
            relay.bind(SubscriptionCommitSinkSpy())
            let gateway = SubscriptionGateway(client: client, relay: relay)
            weakGateway = gateway
            _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        }
        #expect(weakGateway == nil)
    }

    private func eventually(_ predicate: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<50 {
            if predicate() { return true }
            try? await Task<Never, Never>.sleep(nanoseconds: 10_000_000)
        }
        return predicate()
    }
}
