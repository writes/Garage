struct SubscriptionIdentityAttempt {
    let lease: IdentityLease
    let attemptID: UInt64
    let ticket: OperationTicket<IdentityOutcome>
}

struct SubscriptionCommerceFlight { let flightID: UInt64 }

enum SubscriptionQueuedOperation {
    case identity(SubscriptionIdentityAttempt)
    case signOut(generation: UInt64)
    case status(IdentityLease?, OperationTicket<StatusOutcome>)
    case offerings(IdentityLease?, OperationTicket<OfferingsOutcome>)
    case purchase(PackageSelection, IdentityLease?, UInt64, OperationTicket<PurchaseOutcome>)
    case restore(IdentityLease?, UInt64, OperationTicket<RestoreOutcome>)
}

struct SubscriptionTicketRegistration<Value: Sendable> {
    let ticket: OperationTicket<Value>
    let appended: Bool
}

struct SubscriptionIdentityTransition {
    let changed: Bool
    let ticket: OperationTicket<IdentityOutcome>?
    let appended: Bool
}

@MainActor
final class SubscriptionGatewayState {
    var desiredFirebaseUID: String?
    var appliedRevenueCatUID: String?
    var generation: UInt64 = 0
    var readyLease: IdentityLease?
    var attemptCounter: UInt64 = 0
    var currentAttempt: SubscriptionIdentityAttempt?
    var operations = SubscriptionOperationQueue<SubscriptionQueuedOperation>()
    var drainTask: Task<Void, Never>?
    var commerceFlight: SubscriptionCommerceFlight?
    var flightCounter: UInt64 = 0
    var currentOfferingsEpoch: UInt64?
    var stampCounter: UInt64 = 0

    func setDesiredUID(_ uid: String?) -> SubscriptionIdentityTransition {
        guard uid != desiredFirebaseUID else {
            return SubscriptionIdentityTransition(
                changed: false,
                ticket: currentAttempt?.ticket,
                appended: false
            )
        }
        _ = SubscriptionCheckedCounter.advance(&generation, name: "identity generation")
        desiredFirebaseUID = uid
        revokeReadiness()
        guard let uid else {
            // The SDK sign-out is QUEUED so it serializes behind any in-flight logIn — a
            // detached logOut racing a queued logIn was the identity-revert bug class the
            // 7273915 tri-review flagged. The generation stamp lets a superseding sign-in
            // cancel it at execution time.
            operations.append(.signOut(generation: generation))
            return SubscriptionIdentityTransition(changed: true, ticket: nil, appended: true)
        }
        let ticket = appendIdentityAttempt(uid: uid).ticket
        return SubscriptionIdentityTransition(changed: true, ticket: ticket, appended: true)
    }

    func registerIdentityRetry() -> SubscriptionTicketRegistration<IdentityOutcome> {
        guard let uid = desiredFirebaseUID else {
            return registration(.notNeeded(.signedOut))
        }
        if let readyLease { return registration(.notNeeded(.alreadyReady(readyLease))) }
        if let currentAttempt {
            return SubscriptionTicketRegistration(ticket: currentAttempt.ticket, appended: false)
        }
        return SubscriptionTicketRegistration(
            ticket: appendIdentityAttempt(uid: uid).ticket,
            appended: true
        )
    }

    func registerStatus() -> SubscriptionTicketRegistration<StatusOutcome> {
        let ticket = OperationTicket<StatusOutcome>()
        operations.append(.status(demandReadiness(), ticket))
        return SubscriptionTicketRegistration(ticket: ticket, appended: true)
    }

    func registerOfferings() -> SubscriptionTicketRegistration<OfferingsOutcome> {
        let ticket = OperationTicket<OfferingsOutcome>()
        operations.append(.offerings(demandReadiness(), ticket))
        return SubscriptionTicketRegistration(ticket: ticket, appended: true)
    }

    func registerPurchase(
        _ selection: PackageSelection
    ) -> SubscriptionTicketRegistration<PurchaseOutcome> {
        guard commerceFlight == nil else { return registration(.busy) }
        let flightID = mintFlight()
        let ticket = OperationTicket<PurchaseOutcome>()
        operations.append(.purchase(selection, demandReadiness(), flightID, ticket))
        return SubscriptionTicketRegistration(ticket: ticket, appended: true)
    }

    func registerRestore() -> SubscriptionTicketRegistration<RestoreOutcome> {
        guard commerceFlight == nil else { return registration(.busy) }
        let flightID = mintFlight()
        let ticket = OperationTicket<RestoreOutcome>()
        operations.append(.restore(demandReadiness(), flightID, ticket))
        return SubscriptionTicketRegistration(ticket: ticket, appended: true)
    }

    func isCurrent(_ lease: IdentityLease) -> Bool {
        lease.uid == desiredFirebaseUID && lease.generation == generation
    }

    func isCurrent(_ attempt: SubscriptionIdentityAttempt) -> Bool {
        guard let currentAttempt else { return false }
        return currentAttempt.attemptID == attempt.attemptID && currentAttempt.lease == attempt.lease
    }

    func revokeReadiness() {
        readyLease = nil
        currentAttempt = nil
        currentOfferingsEpoch = nil
    }

    func clearFlight(_ id: UInt64) {
        guard commerceFlight?.flightID == id else { return }
        commerceFlight = nil
    }

    func nextStamp() -> UInt64 {
        SubscriptionCheckedCounter.advance(&stampCounter, name: "commit stamp")
    }

    private func appendIdentityAttempt(uid: String) -> SubscriptionIdentityAttempt {
        let attempt = SubscriptionIdentityAttempt(
            lease: IdentityLease(uid: uid, generation: generation),
            attemptID: SubscriptionCheckedCounter.advance(&attemptCounter, name: "identity attempt"),
            ticket: OperationTicket()
        )
        currentAttempt = attempt
        operations.append(.identity(attempt))
        return attempt
    }

    private func demandReadiness() -> IdentityLease? {
        if let readyLease, isCurrent(readyLease) { return readyLease }
        if let currentAttempt { return currentAttempt.lease }
        guard let uid = desiredFirebaseUID else { return nil }
        return appendIdentityAttempt(uid: uid).lease
    }

    private func mintFlight() -> UInt64 {
        let id = SubscriptionCheckedCounter.advance(&flightCounter, name: "commerce flight")
        commerceFlight = SubscriptionCommerceFlight(flightID: id)
        return id
    }

    private func registration<Value: Sendable>(
        _ value: Value
    ) -> SubscriptionTicketRegistration<Value> {
        SubscriptionTicketRegistration(ticket: OperationTicket(resolved: value), appended: false)
    }
}

@MainActor
final class SubscriptionOperationQueue<Element> {
    struct Entry {
        let id: UInt64
        let element: Element
    }

    private var operationCounter: UInt64 = 0
    private var entries: [Entry] = []
    private(set) var synchronousRegistrationCount: UInt64 = 0

    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    @discardableResult
    func append(_ element: Element) -> UInt64 {
        let id = SubscriptionCheckedCounter.advance(&operationCounter, name: "operation counter")
        _ = SubscriptionCheckedCounter.advance(
            &synchronousRegistrationCount,
            name: "registration counter"
        )
        entries.append(Entry(id: id, element: element))
        return id
    }

    func popFirst() -> Entry? {
        guard !entries.isEmpty else { return nil }
        return entries.removeFirst()
    }
}

#if DEBUG
struct SubscriptionGatewayDiagnostics: Equatable, Sendable {
    let generation: UInt64
    let desiredFirebaseUID: String?
    let appliedRevenueCatUID: String?
    let readyLease: IdentityLease?
    let currentAttemptID: UInt64?
    let currentOfferingsEpoch: UInt64?
    let commerceFlightID: UInt64?
    let queuedOperationCount: Int
    let synchronousRegistrationCount: UInt64
    let drainTaskRetained: Bool
    let stampCounter: UInt64
}

extension SubscriptionGateway {
    var diagnostics: SubscriptionGatewayDiagnostics {
        SubscriptionGatewayDiagnostics(
            generation: state.generation,
            desiredFirebaseUID: state.desiredFirebaseUID,
            appliedRevenueCatUID: state.appliedRevenueCatUID,
            readyLease: state.readyLease,
            currentAttemptID: state.currentAttempt?.attemptID,
            currentOfferingsEpoch: state.currentOfferingsEpoch,
            commerceFlightID: state.commerceFlight?.flightID,
            queuedOperationCount: state.operations.count,
            synchronousRegistrationCount: state.operations.synchronousRegistrationCount,
            drainTaskRetained: state.drainTask != nil,
            stampCounter: state.stampCounter
        )
    }
}
#endif
