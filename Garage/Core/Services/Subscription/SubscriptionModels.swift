import CryptoKit
import Foundation
import Observation

struct IdentityLease: Equatable, Sendable {
    let uid: String
    let generation: UInt64
}

struct EntitlementProof: Equatable, Sendable {
    let isActive: Bool
    let expirationDate: Date?
    let lease: IdentityLease

    func isValid(now: Date) -> Bool {
        isActive && expirationDate.map { $0 > now } != false
    }
}

struct EntitlementSnapshot: Equatable, Sendable {
    let isActive: Bool
    let expirationDate: Date?
    let productID: String?

    func disablingEntitlement() -> EntitlementSnapshot {
        EntitlementSnapshot(
            isActive: false,
            expirationDate: expirationDate,
            productID: productID
        )
    }
}

struct SubscriptionPeriodDTO: Equatable, Sendable {
    enum Unit: Equatable, Sendable {
        case day
        case week
        case month
        case year
        case unknown
    }

    let value: Int
    let unit: Unit

    var isSupportedRenewal: Bool { value > 0 && unit != .unknown }
}

struct PackageHandle: Hashable, Sendable {
    let cacheEpoch: UInt64
    let ordinal: UInt64
}

struct PackageDTO: Equatable, Sendable {
    let handle: PackageHandle
    let offeringID: String
    let packageID: String
    let productID: String
    let analyticsProduct: AnalyticsProductID
    let title: String
    let packageDescription: String
    let localizedPrice: String
    let period: SubscriptionPeriodDTO?
}

struct OfferingsSnapshot: Equatable, Sendable {
    let epoch: UInt64
    let offeringID: String
    let packages: [PackageDTO]
    let omittedUnknownProductIDs: [String]
}

struct PackageSelection: Equatable, Sendable {
    let lease: IdentityLease
    let handle: PackageHandle
    let offeringID: String
    let packageID: String
    let productID: String
    let analyticsProduct: AnalyticsProductID
}

struct SubscriptionAccountRevisionStep: Equatable, Sendable {
    let value: UInt64
    let overflowed: Bool
}

enum SubscriptionAccountRevisionReducer {
    static func advance(from current: UInt64) -> SubscriptionAccountRevisionStep {
        let (value, overflowed) = current.addingReportingOverflow(1)
        return SubscriptionAccountRevisionStep(
            value: overflowed ? .max : value,
            overflowed: overflowed
        )
    }
}

enum SubscriptionCheckedCounter {
    static func advance(_ value: inout UInt64, name: StaticString) -> UInt64 {
        let (next, overflowed) = value.addingReportingOverflow(1)
        precondition(!overflowed, "\(name) overflowed")
        value = next
        return next
    }
}

struct PendingSubscriptionReconciliation: Codable, Equatable, Sendable {
    let kind: SubscriptionReconciliationKind
    private let identityDigest: String?

    init(kind: SubscriptionReconciliationKind, uid: String?) {
        self.kind = kind
        identityDigest = uid.map(Self.digest)
    }

    /// A reconciliation with no identity digest can never be matched or cleared, so it must NEVER
    /// be allowed to block the purchase path — that would be a permanent, unrecoverable brick.
    /// Callers treat a non-identity-bound reconciliation as absent.
    var isIdentityBound: Bool { identityDigest != nil }

    func matches(uid: String?) -> Bool {
        guard let uid, let identityDigest else { return false }
        return identityDigest == Self.digest(uid)
    }

    private static func digest(_ uid: String) -> String {
        SHA256.hash(data: Data(uid.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

@MainActor
@Observable
final class SubscriptionReconciliationStore {
    static let storageKey = "garage.subscription.pending-reconciliation.v1"

    private let defaults: UserDefaults?
    private let key: String
    private(set) var pending: PendingSubscriptionReconciliation?

    init(defaults: UserDefaults? = nil, key: String = storageKey) {
        self.defaults = defaults
        self.key = key
        guard let data = defaults?.data(forKey: key) else { return }
        // An undecodable (corrupt / future-schema) blob — or a persisted non-identity-bound
        // reconciliation — is unclearable, so clear it rather than fabricating a nil-uid brick that
        // permanently blocks purchases.
        if let decoded = try? JSONDecoder().decode(PendingSubscriptionReconciliation.self, from: data),
           decoded.isIdentityBound {
            pending = decoded
        } else {
            defaults?.removeObject(forKey: key)
        }
    }

    /// A non-identity-bound reconciliation can never be cleared, so it must not block the purchase
    /// path — surface it as absent (the stored value is reaped on the next launch).
    var kind: SubscriptionReconciliationKind? {
        guard let pending, pending.isIdentityBound else { return nil }
        return pending.kind
    }

    func observePurchase(_ outcome: PurchaseOutcome, uid: String?) {
        guard outcome == .reconciliationRequired else { return }
        replace(with: PendingSubscriptionReconciliation(kind: .purchase, uid: uid))
    }

    func observeRestore(_ outcome: RestoreOutcome, uid: String?) {
        switch outcome {
        case .reconciliationRequired where pending == nil:
            replace(with: PendingSubscriptionReconciliation(kind: .restore, uid: uid))
        case .activeEntitlement where pending?.matches(uid: uid) == true:
            replace(with: nil)
        case .noActiveEntitlement
            where pending?.kind == .restore && pending?.matches(uid: uid) == true:
            replace(with: nil)
        default: break
        }
    }

    private func replace(with value: PendingSubscriptionReconciliation?) {
        pending = value
        guard let defaults else { return }
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
protocol EntitlementClock: Sendable {
    func now() -> Date
}

@MainActor
struct SystemEntitlementClock: EntitlementClock {
    func now() -> Date { Date() }
}

#if DEBUG
struct PurchaseServiceDiagnostics: Equatable, Sendable {
    let lastAcceptedStamp: UInt64?
    let lastAcceptedEvent: SubscriptionCommitEvent?
    let currentReadyLease: IdentityLease?
    let proofIsPresent: Bool
    let proofIsActive: Bool
    let proofExpiration: Date?
    let storedSelection: PackageSelection?
    let accountRevision: UInt64
}

struct SubscriptionViewModelDiagnostics: Equatable, Sendable {
    let sdkFailureDiagnostic: SDKFailureDiagnostic?
    let actionCounter: UInt64
    let activeActionID: UInt64?
}
#endif
