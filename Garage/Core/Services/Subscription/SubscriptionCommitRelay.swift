import Foundation
import OSLog
enum SubscriptionIntegrityViolation: Equatable, Sendable {
    case sameStampDifferentPayload(stamp: UInt64)
    case staleStamp(received: UInt64, lastAccepted: UInt64)
    case prebindDelivery(stamp: UInt64)
    case secondBind
    case commitLeaseMismatch
    case accountRevisionOverflow(last: UInt64)
}
enum StampDisposition: Equatable, Sendable {
    case apply
    case ignoreExactDuplicate
    case drop(SubscriptionIntegrityViolation)
}
enum SubscriptionStampReducer {
    static func disposition(
        incoming: StampedSubscriptionCommit,
        lastAccepted: StampedSubscriptionCommit?
    ) -> StampDisposition {
        guard let lastAccepted else { return .apply }
        if incoming.stamp > lastAccepted.stamp { return .apply }
        if incoming == lastAccepted { return .ignoreExactDuplicate }
        if incoming.stamp == lastAccepted.stamp {
            return .drop(.sameStampDifferentPayload(stamp: incoming.stamp))
        }
        return .drop(.staleStamp(
            received: incoming.stamp,
            lastAccepted: lastAccepted.stamp
        ))
    }
}

struct PurchaseStateEffects {
    let expiry: EntitlementExpiryDisposition?
    let analytics: AnalyticsEvent?
    let violations: [SubscriptionIntegrityViolation]

    static let none = PurchaseStateEffects(expiry: nil, analytics: nil, violations: [])
}

@MainActor
struct PurchaseServiceState {
    var lastAccepted: StampedSubscriptionCommit?
    var currentReadyLease: IdentityLease?
    var proof: EntitlementProof?
    var storedSelection: PackageSelection?
    var plans: OfferingsSnapshot?
    var accountRevision: UInt64 = 0
    /// FIX B bounded grace: while an expiry-wake server refresh is in flight, isPro reads true
    /// past the stale local expirationDate instead of flapping false — capped, so a hung/
    /// offline refresh still fails closed once this deadline passes.
    var expiryGraceUntil: Date?

    func isPro(now: () -> Date) -> Bool {
        guard let currentReadyLease, let proof,
              proof.lease == currentReadyLease, proof.isActive else { return false }
        guard let expirationDate = proof.expirationDate else { return true }
        let instant = now()
        return expirationDate > instant || (expiryGraceUntil.map { instant < $0 } ?? false)
    }

    mutating func makeSelection(for dto: PackageDTO, enabled: Bool) -> PackageSelection? {
        guard enabled, dto.period?.isSupportedRenewal == true,
              let plans, let lease = currentReadyLease,
              let package = plans.packages.first(where: { $0 == dto }) else {
            storedSelection = nil
            return nil
        }
        let selection = PackageSelection(
            lease: lease, handle: package.handle, offeringID: package.offeringID,
            packageID: package.packageID, productID: package.productID,
            analyticsProduct: package.analyticsProduct)
        storedSelection = selection
        return selection
    }

    mutating func apply(_ event: SubscriptionCommitEvent, now: () -> Date) -> PurchaseStateEffects {
        if case .revokedAll = event { return revoke(leaseMismatch: false) }
        if case .currentError(_, .identityMismatch) = event {
            return revoke(leaseMismatch: false)
        }
        if case let .identityApplied(lease, snapshot) = event {
            currentReadyLease = lease
            return proofEffects(replaceProof(snapshot: snapshot, lease: lease, now: now))
        }
        guard let lease = event.guardedLease, lease == currentReadyLease else {
            return revoke(leaseMismatch: true)
        }
        return applyGuarded(event, lease: lease, now: now)
    }

    mutating func reevaluate(now: Date?) -> EntitlementExpiryDisposition {
        assignProof(proof, now: now)
    }

    private mutating func applyGuarded(
        _ event: SubscriptionCommitEvent, lease: IdentityLease,
        now: () -> Date) -> PurchaseStateEffects {
        switch event {
        case .statusCommitted(_, let snapshot):
            return proofEffects(replaceProof(snapshot: snapshot, lease: lease, now: now))
        case .offeringsLoaded(_, let snapshot):
            plans = snapshot
            storedSelection = nil
        case .offeringsUnavailable:
            plans = nil
            storedSelection = nil
        case .currentError(_, .sdk): return applyVoteC(now: now)
        case .purchaseCompleted(_, let snapshot, let product):
            return applyActive(snapshot, lease: lease, analytics: .purchaseCompleted(productID: product), now: now)
        case .purchaseNoEntitlement(_, let snapshot):
            return applyInactive(snapshot, lease: lease, now: now)
        case .restoreActive(_, let snapshot):
            return applyActive(snapshot, lease: lease, analytics: .purchaseRestored, now: now)
        case .restoreNoActive(_, let snapshot):
            return applyInactive(snapshot, lease: lease, now: now)
        default: break
        }
        return .none
    }

    private mutating func applyVoteC(now: () -> Date) -> PurchaseStateEffects {
        plans = nil
        storedSelection = nil
        guard let lease = currentReadyLease, let proof, proof.lease == lease, proof.isActive else {
            return proofEffects(assignProof(nil, now: nil))
        }
        let instant = proof.expirationDate == nil ? nil : now()
        guard instant.map({ proof.isValid(now: $0) }) != false else {
            return proofEffects(assignProof(nil, now: nil))
        }
        return proofEffects(assignProof(proof, now: instant))
    }

    private mutating func applyActive(
        _ snapshot: EntitlementSnapshot, lease: IdentityLease,
        analytics: AnalyticsEvent, now: () -> Date) -> PurchaseStateEffects {
        let candidate = EntitlementProof(
            isActive: snapshot.isActive, expirationDate: snapshot.expirationDate,
            lease: lease)
        let instant = candidate.isActive && candidate.expirationDate != nil ? now() : nil
        let valid = candidate.isActive && instant.map { candidate.isValid(now: $0) } != false
        let expiry = assignProof(valid ? candidate : nil, now: instant)
        storedSelection = nil
        return PurchaseStateEffects(expiry: expiry, analytics: valid ? analytics : nil, violations: [])
    }

    private mutating func applyInactive(
        _ snapshot: EntitlementSnapshot, lease: IdentityLease,
        now: () -> Date) -> PurchaseStateEffects {
        storedSelection = nil
        let expiry = replaceProof(snapshot: snapshot.disablingEntitlement(), lease: lease, now: now)
        return proofEffects(expiry)
    }

    private mutating func replaceProof(
        snapshot: EntitlementSnapshot, lease: IdentityLease,
        now: () -> Date) -> EntitlementExpiryDisposition {
        let candidate = EntitlementProof(
            isActive: snapshot.isActive, expirationDate: snapshot.expirationDate,
            lease: lease)
        let instant = candidate.isActive && candidate.expirationDate != nil ? now() : nil
        return assignProof(candidate, now: instant)
    }

    private mutating func assignProof(
        _ newProof: EntitlementProof?, now: Date?) -> EntitlementExpiryDisposition {
        proof = newProof
        expiryGraceUntil = nil // any commit resolves the hold
        let result = EntitlementExpiryReducer.disposition(
            currentReadyLease: currentReadyLease, proof: proof, now: now)
        if result == .clearProof { proof = nil }
        return result
    }

    private mutating func revoke(leaseMismatch: Bool) -> PurchaseStateEffects {
        currentReadyLease = nil
        proof = nil
        expiryGraceUntil = nil
        plans = nil
        storedSelection = nil
        let prior = accountRevision
        let step = SubscriptionAccountRevisionReducer.advance(from: prior)
        accountRevision = step.value
        var violations: [SubscriptionIntegrityViolation] = leaseMismatch ? [.commitLeaseMismatch] : []
        if step.overflowed { violations.append(.accountRevisionOverflow(last: prior)) }
        return PurchaseStateEffects(expiry: .keepWithoutWake, analytics: nil, violations: violations)
    }

    private func proofEffects(_ expiry: EntitlementExpiryDisposition) -> PurchaseStateEffects {
        PurchaseStateEffects(expiry: expiry, analytics: nil, violations: [])
    }
}

@MainActor
protocol SubscriptionCommitSink: AnyObject {
    func commit(_ envelope: StampedSubscriptionCommit)
}

@MainActor
protocol SubscriptionIntegrityReporter: AnyObject {
    func report(_ violation: SubscriptionIntegrityViolation)
}

@MainActor
final class LoggingSubscriptionIntegrityReporter: SubscriptionIntegrityReporter {
    func report(_ violation: SubscriptionIntegrityViolation) {
        AppLogger.purchase.fault("Subscription integrity: \(String(describing: violation), privacy: .public)")
    }
}

@MainActor
final class SubscriptionCommitRelay {
    private weak var sink: (any SubscriptionCommitSink)?
    private let reporter: any SubscriptionIntegrityReporter
    private var hasBound = false

    init(reporter: any SubscriptionIntegrityReporter) {
        self.reporter = reporter
    }

    func bind(_ sink: any SubscriptionCommitSink) {
        guard !hasBound else {
            reporter.report(.secondBind)
            return
        }
        self.sink = sink
        hasBound = true
    }

    func deliver(_ envelope: StampedSubscriptionCommit) {
        guard hasBound else {
            reporter.report(.prebindDelivery(stamp: envelope.stamp))
            return
        }
        sink?.commit(envelope)
    }

    func report(_ violation: SubscriptionIntegrityViolation) {
        reporter.report(violation)
    }

#if DEBUG
    var isBound: Bool { hasBound }
    var sinkIsAlive: Bool { sink != nil }
#endif
}
