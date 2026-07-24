import Foundation
import Testing
import UIKit
@testable import Garage

@MainActor
struct EntitlementExpirySchedulerTests {
    @Test func reducerCoversMissingMismatchInactiveFutureAndExpiredProofs() {
        let now = Date(timeIntervalSince1970: 100)
        let lease = SubscriptionFixtures.leaseA
        #expect(
            EntitlementExpiryReducer.disposition(currentReadyLease: lease, proof: nil, now: now)
                == .keepWithoutWake
        )
        let inactive = EntitlementProof(isActive: false, expirationDate: now, lease: lease)
        #expect(
            EntitlementExpiryReducer.disposition(currentReadyLease: lease, proof: inactive, now: nil)
                == .keepWithoutWake
        )
        let future = EntitlementProof(isActive: true, expirationDate: now.addingTimeInterval(10), lease: lease)
        #expect(
            EntitlementExpiryReducer.disposition(currentReadyLease: lease, proof: future, now: now)
                == .rearm(after: 10)
        )
        #expect(
            EntitlementExpiryReducer.disposition(currentReadyLease: lease, proof: future, now: nil)
                == .clearProof
        )
        #expect(
            EntitlementExpiryReducer.disposition(currentReadyLease: nil, proof: future, now: now)
                == .clearProof
        )
        let expired = EntitlementProof(isActive: true, expirationDate: now, lease: lease)
        #expect(
            EntitlementExpiryReducer.disposition(currentReadyLease: lease, proof: expired, now: now)
                == .clearProof
        )
    }

    @Test func nonFiniteOrNonPositiveWakeSignalsSynchronously() {
        let scheduler = EntitlementExpiryScheduler()
        var calls = 0
        scheduler.start { calls += 1 }
        scheduler.replaceWake(after: 0)
        scheduler.replaceWake(after: .nan)
        scheduler.replaceWake(after: .infinity)
        #expect(calls == 3)
    }

    @Test func onlyNewestFiniteWakeFires() async {
        let scheduler = EntitlementExpiryScheduler(center: NotificationCenter())
        var calls = 0
        scheduler.start { calls += 1 }
        scheduler.replaceWake(after: 0.03)
        scheduler.replaceWake(after: 0.15)

        try? await Task<Never, Never>.sleep(nanoseconds: 70_000_000)
        #expect(calls == 0)
        let woke = await eventually { calls == 1 }
        #expect(woke)
        try? await Task<Never, Never>.sleep(nanoseconds: 50_000_000)
        #expect(calls == 1)
    }

    @Test func lifecycleNotificationsRouteAndCancelPendingWake() async {
        let center = NotificationCenter()
        let scheduler = EntitlementExpiryScheduler(center: center)
        var calls = 0
        scheduler.start { calls += 1 }
        scheduler.replaceWake(after: 0.12)

        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        let observedForeground = await eventually { calls == 1 }
        center.post(name: UIApplication.significantTimeChangeNotification, object: nil)
        let observedTimeChange = await eventually { calls == 2 }
        try? await Task<Never, Never>.sleep(nanoseconds: 150_000_000)

        #expect(observedForeground)
        #expect(observedTimeChange)
        #expect(calls == 2)
    }

    @Test func activeWakeAndRegistrationsReleaseWithScheduler() async {
        let center = NotificationCenter()
        var calls = 0
        weak var reference: EntitlementExpiryScheduler?
        do {
            let scheduler = EntitlementExpiryScheduler(center: center)
            reference = scheduler
            scheduler.start { calls += 1 }
            scheduler.replaceWake(after: 0.05)
        }

        #expect(reference == nil)
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        center.post(name: UIApplication.significantTimeChangeNotification, object: nil)
        try? await Task<Never, Never>.sleep(nanoseconds: 80_000_000)
        #expect(calls == 0)
    }

    @Test func schedulerSourceLocksLifecycleAndGenerationContract() {
        let source = SubscriptionSourceProbe.read(
            "Garage/Core/Services/Subscription/EntitlementExpiryScheduler.swift"
        )
        #expect(source.contains("guard self.reevaluator == nil"))
        #expect(source.contains("assertionFailure(\"EntitlementExpiryScheduler started more than once\")"))
        #expect(source.contains("generation == self.wakeGeneration"))
        #expect(source.contains("center.removeObserver(token)"))
        #expect(source.contains("deinit {\n        wakeTask?.cancel()"))
        #expect(SubscriptionSourceProbe.count("[weak self]", in: source) >= 3)
        #expect(SubscriptionSourceProbe.count("willEnterForegroundNotification", in: source) == 1)
        #expect(SubscriptionSourceProbe.count("significantTimeChangeNotification", in: source) == 1)
    }

    @Test func proofSourceLocksCancelFirstAndLeaseValidityContract() {
        let service = SubscriptionSourceProbe.read(
            "Garage/Core/Services/Subscription/PurchaseService.swift"
        )
        let state = SubscriptionSourceProbe.read(
            "Garage/Core/Services/Subscription/SubscriptionCommitRelay.swift"
        )
        #expect(service.contains("func performProofMutation"))
        #expect(SubscriptionSourceProbe.count("expiryScheduler.cancelWake()", in: service) == 1)
        #expect(SubscriptionSourceProbe.containsInOrder(
            ["func performProofMutation", "expiryScheduler.cancelWake()", "return mutation()"],
            in: service
        ))
        #expect(SubscriptionSourceProbe.containsInOrder(
            ["state.lastAccepted = envelope", "let effects = applyStateEvent", "relay.report", "perform(effects)"],
            in: service
        ))
        #expect(service.contains("performProofMutation { state.reevaluate(now: now) }"))
        #expect(state.contains("proof.lease == currentReadyLease"))
        #expect(state.contains("proof.isActive else"))
        // FIX B: isPro consults the bounded grace hold instead of reading the stale
        // expirationDate unconditionally — pins that the grace check is still wired in.
        #expect(state.contains("guard let expirationDate = proof.expirationDate else { return true }"))
        #expect(state.contains("expiryGraceUntil.map { instant < $0 } ?? false"))
    }

    @Test func expiryClearsOnlyProofAndLeavesAccountContextIntact() async {
        let now = Date(timeIntervalSince1970: 500)
        let clock = AdjustableEntitlementClock(now)
        let scheduler = ManualExpiryScheduler()
        let service = makeTestService(
            client: SubscriptionMockClient(),
            clock: clock,
            scheduler: scheduler
        )
        let snapshot = EntitlementSnapshot(
            isActive: true,
            expirationDate: now.addingTimeInterval(1),
            productID: Constants.monthlyPlanIdentifier
        )
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: snapshot)
        ))
        clock.value = now.addingTimeInterval(2)
        scheduler.fire()
        // FIX B routes the clear through an async server-refresh attempt first (gateway
        // identity was never established here, so it resolves .notReady and falls back).
        let cleared = await eventually { !service.diagnostics.proofIsPresent }
        #expect(cleared)
        #expect(!service.isPro)
        #expect(service.accountRevision == 0)
        #expect(service.diagnostics.currentReadyLease == SubscriptionFixtures.leaseA)
        #expect(service.diagnostics.lastAcceptedStamp == 1)
    }

    private func eventually(_ predicate: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<50 {
            if predicate() { return true }
            try? await Task<Never, Never>.sleep(nanoseconds: 10_000_000)
        }
        return predicate()
    }
}
