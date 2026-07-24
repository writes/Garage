import Foundation

enum SubscriptionError: Error, Equatable, Sendable {
    case identityMismatch
    case sdk(domain: String, code: Int, message: String)
}

struct RevenueCatObserved<Value: Sendable>: Sendable {
    let result: Result<Value, SubscriptionError>
    let observedAppUserID: String
}

enum ClientOfferingsPayload: Equatable, Sendable {
    case loaded(OfferingsSnapshot)
    case unavailable(epoch: UInt64)
    case cacheInvalidated
}

enum ClientPurchasePayload: Equatable, Sendable {
    case completed(snapshot: EntitlementSnapshot, product: AnalyticsProductID)
    case cancelled
    case pending
    case selectionInvalidated
}

enum NotNeededReason: Equatable, Sendable {
    case signedOut
    case alreadyReady(IdentityLease)
}

enum IdentityOutcome: Equatable, Sendable {
    case applied(IdentityLease)
    case skippedStale
    case notNeeded(NotNeededReason)
    case failed(SubscriptionError)
}

enum StatusOutcome: Equatable, Sendable {
    case committed(EntitlementSnapshot)
    case staleDiscarded
    case notReady
    case failed(SubscriptionError)
}

enum OfferingsOutcome: Equatable, Sendable {
    case loaded(OfferingsSnapshot)
    case unavailable
    case cacheInvalidated
    case staleDiscarded
    case notReady
    case failed(SubscriptionError)
}

enum PurchaseOutcome: Equatable, Sendable {
    case activePro
    case noEntitlement
    case cancelled
    case pending
    case busy
    case notReady
    case selectionInvalidated
    case reconciliationRequired
    case failed(SubscriptionError)
}

enum RestoreOutcome: Equatable, Sendable {
    case activeEntitlement
    case noActiveEntitlement
    case busy
    case notReady
    case reconciliationRequired
    case failed(SubscriptionError)
}

enum SubscriptionReconciliationKind: String, Codable, Equatable, Sendable { case purchase, restore }

enum SubscriptionPresentationState: Equatable, Sendable {
    case idle, loadingPlans, purchasing, restoring, purchased, cancelled, pending
    case noEntitlement, selectionInvalidated, unavailable
    case reconciliationRequired(SubscriptionReconciliationKind)
    case failure(AppError)
}

enum SubscriptionNotice: Equatable, Sendable {
    case plansUnavailable, notReady, busy, selectionInvalidated, active
    case purchaseNoEntitlement, restoreNoActive, cancelled, pending

    var text: String {
        switch self {
        case .plansUnavailable:
            return "Plans are unavailable right now. Check your connection, then tap Refresh Plans."
        case .notReady:
            return "Subscriptions are unavailable right now. Check your connection and try again."
        case .busy: return "Another subscription action is in progress."
        case .selectionInvalidated: return "Plans were updated. Choose a plan again."
        case .active: return "Garage Pro is active."
        case .purchaseNoEntitlement:
            return "Your purchase finished, but no Pro entitlement is active. " +
                "Use Restore Purchases, or contact support if you were charged."
        case .restoreNoActive:
            return "No active subscription was found for this account. Nothing was charged."
        case .cancelled: return "Purchase cancelled. Nothing was charged."
        case .pending:
            return "Waiting for approval — nothing has been charged yet. " +
                "Pro unlocks automatically once the purchase is approved."
        }
    }
}

enum SubscriptionPresentationOutput: Equatable, Sendable {
    case none
    case notice(SubscriptionNotice)
    case reconciliation(SubscriptionReconciliationKind)
    case failure(AppError)
}

struct SDKFailureDiagnostic: Equatable, Sendable {
    let domain: String
    let code: Int
    let message: String
}

enum SubscriptionActionKind: Equatable, Sendable { case refreshPlans, purchase, restore }

struct SubscriptionActionToken: Equatable {
    let id: UInt64
    let kind: SubscriptionActionKind
}

enum SubscriptionCommitEvent: Equatable, Sendable {
    case revokedAll
    case identityApplied(lease: IdentityLease, snapshot: EntitlementSnapshot)
    case statusCommitted(lease: IdentityLease, snapshot: EntitlementSnapshot)
    case offeringsLoaded(lease: IdentityLease, snapshot: OfferingsSnapshot)
    case offeringsUnavailable(lease: IdentityLease, retiredEpoch: UInt64)
    case currentError(lease: IdentityLease, error: SubscriptionError)
    case purchaseCompleted(
        lease: IdentityLease,
        snapshot: EntitlementSnapshot,
        productID: AnalyticsProductID
    )
    case purchaseNoEntitlement(lease: IdentityLease, snapshot: EntitlementSnapshot)
    case restoreActive(lease: IdentityLease, snapshot: EntitlementSnapshot)
    case restoreNoActive(lease: IdentityLease, snapshot: EntitlementSnapshot)

    var guardedLease: IdentityLease? {
        switch self {
        case .statusCommitted(let lease, _), .offeringsLoaded(let lease, _),
             .offeringsUnavailable(let lease, _), .currentError(let lease, _),
             .purchaseCompleted(let lease, _, _), .purchaseNoEntitlement(let lease, _),
             .restoreActive(let lease, _), .restoreNoActive(let lease, _): return lease
        case .revokedAll, .identityApplied: return nil
        }
    }
}

struct StampedSubscriptionCommit: Equatable, Sendable {
    let stamp: UInt64
    let event: SubscriptionCommitEvent
}

@MainActor
protocol SubscriptionFacading: AnyObject {
    var isPro: Bool { get }
    var plans: OfferingsSnapshot? { get }
    var accountRevision: UInt64 { get }
    var pendingReconciliation: SubscriptionReconciliationKind? { get }
    func makeSelection(for dto: PackageDTO) -> PackageSelection?
    func refreshStatus() async -> StatusOutcome
    func loadOfferings() async -> OfferingsOutcome
    func purchase(_ selection: PackageSelection) async -> PurchaseOutcome
    func restore() async -> RestoreOutcome
}
