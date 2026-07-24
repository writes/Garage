import Foundation
import Observation
import Testing
@testable import Garage

@MainActor
struct PurchaseServiceIdentityLeaseTests {
    @Test func proofMustMatchCurrentReadyLease() {
        let service = makeTestService(client: SubscriptionMockClient())
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.active)
        ))
        #expect(service.isPro)
        service.commit(.init(
            stamp: 2,
            event: .statusCommitted(lease: SubscriptionFixtures.leaseB, snapshot: SubscriptionFixtures.active)
        ))
        #expect(!service.isPro)
    }

    @Test func expirationEqualityIsNotAuthorized() {
        let now = Date(timeIntervalSince1970: 2_000)
        let clock = AdjustableEntitlementClock(now)
        let service = makeTestService(client: SubscriptionMockClient(), clock: clock)
        let snapshot = EntitlementSnapshot(
            isActive: true,
            expirationDate: now,
            productID: Constants.monthlyPlanIdentifier
        )
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: snapshot)
        ))
        #expect(!service.isPro)
    }

    @Test func finiteProofExpiresAgainstTheSingleInjectedClock() async {
        let now = Date(timeIntervalSince1970: 3_000)
        let clock = AdjustableEntitlementClock(now)
        let scheduler = ManualExpiryScheduler()
        let service = makeTestService(
            client: SubscriptionMockClient(),
            clock: clock,
            scheduler: scheduler
        )
        let snapshot = EntitlementSnapshot(
            isActive: true,
            expirationDate: now.addingTimeInterval(60),
            productID: Constants.monthlyPlanIdentifier
        )
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: snapshot)
        ))
        #expect(clock.reads == 1)
        #expect(service.isPro)
        #expect(clock.reads == 2)
        #expect(scheduler.replacements == [60])
        clock.value = now.addingTimeInterval(60)
        scheduler.fire()
        // FIX B routes the clear through an async server-refresh attempt first (gateway
        // identity was never established here, so it resolves .notReady and falls back).
        let cleared = await eventually { !service.diagnostics.proofIsPresent }
        #expect(cleared)
        #expect(!service.isPro)
        #expect(service.accountRevision == 0)
        #expect(service.diagnostics.currentReadyLease == SubscriptionFixtures.leaseA)
    }

    @Test func activeProofWithoutExpirationNeverReadsAuthorizationClock() {
        let clock = AdjustableEntitlementClock()
        let service = makeTestService(client: SubscriptionMockClient(), clock: clock)
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(
                lease: SubscriptionFixtures.leaseA,
                snapshot: SubscriptionFixtures.active
            )
        ))
        #expect(clock.reads == 0)
        #expect(service.isPro)
        #expect(clock.reads == 0)
    }

    @Test func inertSchedulerIsRetainedButNeverStarted() {
        let service = PurchaseService(testIsPro: true)
        #expect(service.isPro)
        #expect(service.diagnostics.currentReadyLease != nil)
        #expect(service.accountRevision == 0)
    }

    @Test func desiredAndAppliedIdentityRemainSeparateUntilLoginCompletes() async {
        let client = SubscriptionMockClient()
        let service = makeTestService(client: client)
        let ticket = service.setDesiredFirebaseUID("A")
        #expect(!service.isPro)
        let outcome = await ticket?.awaitValue()
        #expect(outcome == .applied(SubscriptionFixtures.leaseA))
        #expect(service.diagnostics.currentReadyLease == SubscriptionFixtures.leaseA)
    }

    @Test func proofMutationInvalidatesDirectFacadeModelAndAppStateReads() async {
        let service = makeTestService(client: SubscriptionMockClient())
        let facade: any SubscriptionFacading = service
        let model = SubscriptionViewModel(service: facade)
        let analytics = AnalyticsSpy()
        let appState = AppState(
            authService: AuthService(testUID: nil, analytics: analytics),
            vehicleService: VehicleService(testVehicles: [], purchaseService: service),
            purchaseService: service,
            analytics: analytics
        )
        let counters = (0..<4).map { _ in SubscriptionCounter() }
        track({ service.isPro }, counter: counters[0])
        track({ facade.isPro }, counter: counters[1])
        track({ model.isPro }, counter: counters[2])
        track({ appState.isPro }, counter: counters[3])

        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.active)
        ))
        let allInvalidated = await eventuallyInvalidated(counters)
        #expect(allInvalidated)
        #expect(counters.allSatisfy { $0.value == 1 })
    }

    private func track(
        _ read: @escaping @MainActor () -> Bool,
        counter: SubscriptionCounter
    ) {
        withObservationTracking { _ = read() } onChange: {
            Task { @MainActor in counter.increment() }
        }
    }

    private func eventuallyInvalidated(_ counters: [SubscriptionCounter]) async -> Bool {
        for _ in 0..<20 {
            if counters.allSatisfy({ $0.value == 1 }) { return true }
            await Task.yield()
        }
        return counters.allSatisfy { $0.value == 1 }
    }

    private func eventually(_ predicate: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<50 {
            if predicate() { return true }
            try? await Task<Never, Never>.sleep(nanoseconds: 10_000_000)
        }
        return predicate()
    }
}
