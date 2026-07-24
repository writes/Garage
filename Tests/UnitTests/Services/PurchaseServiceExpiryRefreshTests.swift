import Foundation
import Testing
@testable import Garage

// FIX B (audited money-path fix): the expiry wake used to clear Pro on the local clock alone,
// with no server re-check — a subscription renewed server-side (or a flapping sandbox renewal)
// would drop Pro until some unrelated refresh happened to run. These tests pin: a server-
// confirmed renewal keeps Pro without a visible flap, an offline/failed refresh still falls
// back to the original local-clock clearProof behavior, and at most one refresh is attempted
// per wake fire (no retry storm).
@MainActor
struct PurchaseServiceExpiryRefreshTests {
    @Test func serverRenewalKeepsProWithoutLocalFlap() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let clock = AdjustableEntitlementClock(now)
        let scheduler = ManualExpiryScheduler()
        let client = SubscriptionMockClient()
        let nearExpiry = now.addingTimeInterval(5)
        client.loginHandler = { uid in
            client.observed(.success(.init(
                isActive: true, expirationDate: nearExpiry, productID: Constants.monthlyPlanIdentifier
            )), uid: uid)
        }
        let service = makeTestService(client: client, clock: clock, scheduler: scheduler)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        #expect(service.isPro)

        // The server already renewed by the time the local wake fires; the local clock alone
        // would have declared expiry.
        let renewed = now.addingTimeInterval(3_600)
        client.statusHandler = {
            client.observed(.success(.init(
                isActive: true, expirationDate: renewed, productID: Constants.monthlyPlanIdentifier
            )))
        }
        clock.value = nearExpiry.addingTimeInterval(1)
        scheduler.fire()
        // The bounded grace hold (PurchaseServiceState.expiryGraceUntil) must already be
        // covering the stale local expirationDate the instant the wake returns, before the
        // async refresh has even started running.
        #expect(service.isPro)

        var observedFlap = false
        var renewedConfirmed = false
        for _ in 0..<50 {
            guard service.isPro else { observedFlap = true; break }
            if service.diagnostics.proofExpiration == renewed {
                renewedConfirmed = true
                break
            }
            try? await Task<Never, Never>.sleep(nanoseconds: 10_000_000)
        }
        #expect(!observedFlap) // isPro must hold true on every single poll, not just at the end
        #expect(renewedConfirmed)
        #expect(client.statusCalls == 1)
    }

    @Test func offlineRefreshFailureFallsBackToLocalClear() async {
        let now = Date(timeIntervalSince1970: 20_000)
        let clock = AdjustableEntitlementClock(now)
        let scheduler = ManualExpiryScheduler()
        let client = SubscriptionMockClient()
        let nearExpiry = now.addingTimeInterval(5)
        client.loginHandler = { uid in
            client.observed(.success(.init(
                isActive: true, expirationDate: nearExpiry, productID: Constants.monthlyPlanIdentifier
            )), uid: uid)
        }
        let service = makeTestService(client: client, clock: clock, scheduler: scheduler)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        #expect(service.isPro)

        client.statusHandler = {
            client.observed(.failure(.sdk(domain: "network", code: -1, message: "offline")))
        }
        clock.value = nearExpiry.addingTimeInterval(1)
        scheduler.fire()

        let cleared = await eventually { !service.isPro }
        #expect(cleared)
        #expect(client.statusCalls == 1)
        #expect(!service.diagnostics.proofIsPresent) // physically cleared, not just isPro-false
        // Fail-closed, unchanged: only the proof clears — identity/lease context survives.
        #expect(service.diagnostics.currentReadyLease == SubscriptionFixtures.leaseA)
    }

    @Test func nonClearingWakeNeverAttemptsServerRefresh() async {
        let now = Date(timeIntervalSince1970: 30_000)
        let clock = AdjustableEntitlementClock(now)
        let scheduler = ManualExpiryScheduler()
        let client = SubscriptionMockClient()
        let farExpiry = now.addingTimeInterval(600)
        client.loginHandler = { uid in
            client.observed(.success(.init(
                isActive: true, expirationDate: farExpiry, productID: Constants.monthlyPlanIdentifier
            )), uid: uid)
        }
        let service = makeTestService(client: client, clock: clock, scheduler: scheduler)
        _ = await service.setDesiredFirebaseUID("A")?.awaitValue()
        #expect(service.isPro)

        scheduler.fire() // still far from expiry -> rearm, never a clearProof candidate
        await Task.yield()
        #expect(client.statusCalls == 0)
        #expect(service.isPro)
        #expect(scheduler.replacements.last == 600)
    }

    private func eventually(_ predicate: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<50 {
            if predicate() { return true }
            try? await Task<Never, Never>.sleep(nanoseconds: 10_000_000)
        }
        return predicate()
    }
}
