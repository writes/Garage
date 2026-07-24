import Foundation

enum ObservedOperationDisposition<Value: Sendable>: Sendable {
    case stale
    case identityMismatch
    case failed(SubscriptionError)
    case succeeded(Value)
}

enum PurchaseOperationDisposition: Sendable {
    case selectionInvalidated(revoke: Bool)
    case cancelled(revoke: Bool)
    case pending(revoke: Bool)
    case reconciliationRequired(revoke: Bool)
    case failed(SubscriptionError)
    case completed(EntitlementSnapshot, AnalyticsProductID)
}

enum SubscriptionGatewayEffect: Sendable {
    case none
    case revoke
    case invalidateCache
    case offeringsEpoch(UInt64?)
}

struct SubscriptionGatewayResolution<Outcome: Sendable>: Sendable {
    let outcome: Outcome
    let event: SubscriptionCommitEvent?
    let effect: SubscriptionGatewayEffect
}

enum SubscriptionOutcomeClassifier {
    static func error(_ error: Error) -> SubscriptionError {
        let nsError = error as NSError
        return .sdk(
            domain: nsError.domain,
            code: nsError.code,
            message: nsError.localizedDescription
        )
    }

    static func isCurrent(_ lease: IdentityLease, desiredUID: String?, generation: UInt64) -> Bool {
        lease.uid == desiredUID && lease.generation == generation
    }

    static func observed<Value: Sendable>(
        _ value: RevenueCatObserved<Value>,
        expectedUID: String,
        isCurrent: Bool
    ) -> ObservedOperationDisposition<Value> {
        guard isCurrent else { return .stale }
        guard value.observedAppUserID == expectedUID else { return .identityMismatch }
        switch value.result {
        case .failure(.identityMismatch): return .identityMismatch
        case .failure(let error): return .failed(error)
        case .success(let payload): return .succeeded(payload)
        }
    }

    static func purchase(
        _ value: RevenueCatObserved<ClientPurchasePayload>,
        expectedUID: String,
        isCurrent: Bool
    ) -> PurchaseOperationDisposition {
        let mismatched = value.observedAppUserID != expectedUID
        switch value.result {
        case .success(.selectionInvalidated):
            return .selectionInvalidated(revoke: isCurrent && mismatched)
        case .success(.cancelled):
            return .cancelled(revoke: isCurrent && mismatched)
        case .success(.pending):
            // A deferred (Ask-to-Buy/SCA) purchase hasn't charged or completed anything yet —
            // treat it like cancellation for identity/staleness purposes, not like a completed
            // purchase that would need reconciliation (FIX A).
            return .pending(revoke: isCurrent && mismatched)
        default: break
        }
        guard isCurrent else { return .reconciliationRequired(revoke: false) }
        guard !mismatched else { return .reconciliationRequired(revoke: true) }
        switch value.result {
        case .failure(.identityMismatch): return .reconciliationRequired(revoke: true)
        case .failure(let error): return .failed(error)
        case .success(.completed(let snapshot, let product)):
            return .completed(snapshot, product)
        case .success: return .selectionInvalidated(revoke: false)
        }
    }

    static func status(
        _ value: RevenueCatObserved<EntitlementSnapshot>,
        lease: IdentityLease,
        isCurrent: Bool
    ) -> SubscriptionGatewayResolution<StatusOutcome> {
        switch observed(value, expectedUID: lease.uid, isCurrent: isCurrent) {
        case .stale: return resolution(.staleDiscarded)
        case .identityMismatch: return resolution(.failed(.identityMismatch), effect: .revoke)
        case .failed(let error):
            return resolution(
                .failed(error),
                event: .currentError(lease: lease, error: error),
                effect: .invalidateCache
            )
        case .succeeded(let snapshot):
            return resolution(
                .committed(snapshot),
                event: .statusCommitted(lease: lease, snapshot: snapshot)
            )
        }
    }

    static func offerings(
        _ value: RevenueCatObserved<ClientOfferingsPayload>,
        lease: IdentityLease,
        isCurrent: Bool
    ) -> SubscriptionGatewayResolution<OfferingsOutcome> {
        switch observed(value, expectedUID: lease.uid, isCurrent: isCurrent) {
        case .stale: return resolution(.staleDiscarded)
        case .identityMismatch: return resolution(.failed(.identityMismatch), effect: .revoke)
        case .failed(let error):
            return resolution(
                .failed(error),
                event: .currentError(lease: lease, error: error),
                effect: .invalidateCache
            )
        case .succeeded(.cacheInvalidated): return resolution(.cacheInvalidated)
        case .succeeded(.unavailable(let epoch)):
            return resolution(
                .unavailable,
                event: .offeringsUnavailable(lease: lease, retiredEpoch: epoch),
                effect: .offeringsEpoch(nil)
            )
        case .succeeded(.loaded(let snapshot)):
            return resolution(
                .loaded(snapshot),
                event: .offeringsLoaded(lease: lease, snapshot: snapshot),
                effect: .offeringsEpoch(snapshot.epoch)
            )
        }
    }

    static func purchaseResolution(
        _ value: RevenueCatObserved<ClientPurchasePayload>,
        selection: PackageSelection,
        isCurrent: Bool
    ) -> SubscriptionGatewayResolution<PurchaseOutcome> {
        switch purchase(value, expectedUID: selection.lease.uid, isCurrent: isCurrent) {
        case .selectionInvalidated(let revoke):
            return resolution(.selectionInvalidated, effect: revoke ? .revoke : .none)
        case .cancelled(let revoke):
            return resolution(.cancelled, effect: revoke ? .revoke : .none)
        case .pending(let revoke):
            return resolution(.pending, effect: revoke ? .revoke : .none)
        case .reconciliationRequired(let revoke):
            return resolution(.reconciliationRequired, effect: revoke ? .revoke : .none)
        case .failed(let error):
            return resolution(
                .failed(error),
                event: .currentError(lease: selection.lease, error: error),
                effect: .invalidateCache
            )
        case .completed(let snapshot, let product):
            let event: SubscriptionCommitEvent = snapshot.isActive
                ? .purchaseCompleted(lease: selection.lease, snapshot: snapshot, productID: product)
                : .purchaseNoEntitlement(lease: selection.lease, snapshot: snapshot)
            return resolution(snapshot.isActive ? .activePro : .noEntitlement, event: event)
        }
    }

    static func restore(
        _ value: RevenueCatObserved<EntitlementSnapshot>,
        lease: IdentityLease,
        isCurrent: Bool
    ) -> SubscriptionGatewayResolution<RestoreOutcome> {
        switch observed(value, expectedUID: lease.uid, isCurrent: isCurrent) {
        case .stale: return resolution(.reconciliationRequired)
        case .identityMismatch: return resolution(.reconciliationRequired, effect: .revoke)
        case .failed(let error):
            return resolution(
                .failed(error),
                event: .currentError(lease: lease, error: error),
                effect: .invalidateCache
            )
        case .succeeded(let snapshot):
            let event: SubscriptionCommitEvent = snapshot.isActive
                ? .restoreActive(lease: lease, snapshot: snapshot)
                : .restoreNoActive(lease: lease, snapshot: snapshot)
            return resolution(snapshot.isActive ? .activeEntitlement : .noActiveEntitlement, event: event)
        }
    }

    private static func resolution<Outcome: Sendable>(
        _ outcome: Outcome,
        event: SubscriptionCommitEvent? = nil,
        effect: SubscriptionGatewayEffect = .none
    ) -> SubscriptionGatewayResolution<Outcome> {
        SubscriptionGatewayResolution(outcome: outcome, event: event, effect: effect)
    }
}
