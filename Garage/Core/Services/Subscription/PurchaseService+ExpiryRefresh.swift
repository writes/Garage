import Foundation

// MARK: - FIX B (audited money-path fix): expiry-wake server refresh
//
// EntitlementExpiryScheduler previously fired straight into PurchaseService's local-clock
// reevaluation: if the disposition was `.clearProof`, Pro was cleared with NO server re-check —
// a subscription renewed server-side (including sandbox renewal flapping) would drop Pro until
// some unrelated status refresh happened to run. Before clearing on the local clock alone,
// attempt exactly ONE server status refresh:
//   - success (`.committed`): SubscriptionGateway.executeStatus already delivered the resulting
//     commit event (apply() runs before the ticket resolves), so entitlement state has already
//     converged by the time this awaits — nothing further to do.
//   - anything else (`.notReady` / `.staleDiscarded` / `.failed`, or no gateway at all): the
//     refresh didn't confirm anything, so fall back to the original local-clock disposition,
//     unchanged — fail-closed stays intact.
// A bounded grace hold (PurchaseServiceState.expiryGraceUntil) keeps `isPro` reading true for
// up to 30s while the refresh is in flight — without it, `isPro` recomputes the stale
// expirationDate live and would flap false the instant the wake fires, independent of this
// refresh entirely. A hung/offline refresh still fails closed once the cap elapses.
// Single-flight: a new wake cancels any still-running refresh Task from a prior wake before
// starting its own; the cancelled task's own fallback becomes a no-op.
extension PurchaseService {
    func reevaluateEntitlementExpiry() {
        let now = state.proof?.isActive == true && state.proof?.expirationDate != nil
            ? clock.now()
            : nil
        guard let gateway,
              EntitlementExpiryReducer.disposition(
                  currentReadyLease: state.currentReadyLease, proof: state.proof, now: now
              ) == .clearProof
        else {
            applyLocalExpiryFallback(now: now)
            return
        }
        state.expiryGraceUntil = clock.now().addingTimeInterval(30)
        expiryRefreshTask?.cancel()
        expiryRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard case .committed = await gateway.registerStatus().awaitValue() else {
                guard !Task.isCancelled else { return }
                self.applyLocalExpiryFallback(now: now)
                return
            }
        }
    }
}
