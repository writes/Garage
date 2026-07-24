import Foundation

@MainActor
final class SubscriptionGateway {
    let client: any RevenueCatClienting
    let relay: SubscriptionCommitRelay
    let state = SubscriptionGatewayState()
    private var customerInfoTask: Task<Void, Never>?

    init(client: any RevenueCatClienting, relay: SubscriptionCommitRelay) {
        self.client = client
        self.relay = relay
        startObservingCustomerInfo()
    }

    deinit {
        customerInfoTask?.cancel()
    }

    @discardableResult
    func setDesiredFirebaseUID(_ uid: String?) -> OperationTicket<IdentityOutcome>? {
        let transition = state.setDesiredUID(uid)
        guard transition.changed else { return transition.ticket }
        client.invalidatePackageCache()
        emit(.revokedAll)
        if transition.appended { scheduleDrain() }
        return transition.ticket
    }

    func requestIdentityRetry() -> OperationTicket<IdentityOutcome> {
        finishRegistration(state.registerIdentityRetry())
    }

    func registerStatus() -> OperationTicket<StatusOutcome> {
        finishRegistration(state.registerStatus())
    }

    func registerOfferings() -> OperationTicket<OfferingsOutcome> {
        finishRegistration(state.registerOfferings())
    }

    func registerPurchase(_ selection: PackageSelection) -> OperationTicket<PurchaseOutcome> {
        finishRegistration(state.registerPurchase(selection))
    }

    func registerRestore() -> OperationTicket<RestoreOutcome> {
        finishRegistration(state.registerRestore())
    }

    func finishRegistration<Value: Sendable>(
        _ registration: SubscriptionTicketRegistration<Value>
    ) -> OperationTicket<Value> {
        if registration.appended { scheduleDrain() }
        return registration.ticket
    }

    func scheduleDrain() {
        guard state.drainTask == nil else { return }
        state.drainTask = Task { @MainActor [weak self] in await self?.drain() }
    }

    func drain() async {
        while let entry = state.operations.popFirst() { await execute(entry.element) }
        state.drainTask = nil
    }

    func execute(_ operation: SubscriptionQueuedOperation) async {
        switch operation {
        case .identity(let attempt): await executeIdentity(attempt)
        case .signOut(let generation): await executeSignOut(generation)
        case let .status(lease, ticket): await executeStatus(lease, ticket)
        case let .offerings(lease, ticket): await executeOfferings(lease, ticket)
        case let .purchase(selection, lease, flight, ticket):
            await executePurchase(selection, lease, flight, ticket)
        case let .restore(lease, flight, ticket): await executeRestore(lease, flight, ticket)
        }
    }

    func executeSignOut(_ generation: UInt64) async {
        // A sign-in that landed after this sign-out supersedes it — logging out then would
        // clobber the newer user's SDK identity. Local access was already fenced by the
        // revoke in setDesiredFirebaseUID; the SDK call is best-effort identity hygiene.
        guard state.generation == generation, state.desiredFirebaseUID == nil else { return }
        let observed = await client.logOut()
        state.appliedRevenueCatUID = observed.observedAppUserID
    }

    func executeIdentity(_ attempt: SubscriptionIdentityAttempt) async {
        guard state.isCurrent(attempt) else { attempt.ticket.resolve(.skippedStale); return }
        let observed = await client.logIn(uid: attempt.lease.uid)
        state.appliedRevenueCatUID = observed.observedAppUserID
        switch SubscriptionOutcomeClassifier.observed(
            observed,
            expectedUID: attempt.lease.uid,
            isCurrent: state.isCurrent(attempt)
        ) {
        case .stale: attempt.ticket.resolve(.skippedStale)
        case .identityMismatch:
            revokeForMismatch()
            attempt.ticket.resolve(.failed(.identityMismatch))
        case .failed(let error):
            state.currentAttempt = nil
            attempt.ticket.resolve(.failed(error))
        case .succeeded(let snapshot):
            state.currentAttempt = nil
            state.readyLease = attempt.lease
            emit(.identityApplied(lease: attempt.lease, snapshot: snapshot))
            attempt.ticket.resolve(.applied(attempt.lease))
        }
    }

    func executeStatus(_ lease: IdentityLease?, _ ticket: OperationTicket<StatusOutcome>) async {
        guard let lease else { ticket.resolve(.notReady); return }
        guard lease == state.readyLease, state.isCurrent(lease) else {
            ticket.resolve(.staleDiscarded)
            return
        }
        let observed = await client.customerInfo()
        state.appliedRevenueCatUID = observed.observedAppUserID
        let resolution = SubscriptionOutcomeClassifier.status(
            observed,
            lease: lease,
            isCurrent: lease == state.readyLease && state.isCurrent(lease)
        )
        apply(resolution)
        ticket.resolve(resolution.outcome)
    }

    func executeOfferings(_ lease: IdentityLease?, _ ticket: OperationTicket<OfferingsOutcome>) async {
        guard let lease else { ticket.resolve(.notReady); return }
        guard lease == state.readyLease, state.isCurrent(lease) else {
            ticket.resolve(.staleDiscarded)
            return
        }
        let observed = await client.offerings()
        state.appliedRevenueCatUID = observed.observedAppUserID
        let resolution = SubscriptionOutcomeClassifier.offerings(
            observed,
            lease: lease,
            isCurrent: lease == state.readyLease && state.isCurrent(lease)
        )
        apply(resolution)
        ticket.resolve(resolution.outcome)
    }

    func executePurchase(
        _ selection: PackageSelection,
        _ expectedLease: IdentityLease?,
        _ flightID: UInt64,
        _ ticket: OperationTicket<PurchaseOutcome>
    ) async {
        defer { state.clearFlight(flightID) }
        guard selection.lease == state.readyLease,
              selection.handle.cacheEpoch == state.currentOfferingsEpoch else {
            ticket.resolve(.selectionInvalidated); return
        }
        guard let expectedLease,
              expectedLease == state.readyLease,
              state.isCurrent(expectedLease) else {
            ticket.resolve(.notReady); return
        }
        let observed = await client.purchase(
            handle: selection.handle, offeringID: selection.offeringID,
            packageID: selection.packageID, productID: selection.productID,
            analyticsProduct: selection.analyticsProduct
        )
        state.appliedRevenueCatUID = observed.observedAppUserID
        classifyPurchase(observed, selection: selection, ticket: ticket)
    }

    func classifyPurchase(
        _ observed: RevenueCatObserved<ClientPurchasePayload>,
        selection: PackageSelection,
        ticket: OperationTicket<PurchaseOutcome>
    ) {
        let resolution = SubscriptionOutcomeClassifier.purchaseResolution(
            observed,
            selection: selection,
            isCurrent: selection.lease == state.readyLease && state.isCurrent(selection.lease)
        )
        apply(resolution)
        ticket.resolve(resolution.outcome)
    }

    func executeRestore(
        _ expectedLease: IdentityLease?,
        _ flightID: UInt64,
        _ ticket: OperationTicket<RestoreOutcome>
    ) async {
        defer { state.clearFlight(flightID) }
        guard let lease = expectedLease,
              lease == state.readyLease,
              state.isCurrent(lease) else {
            ticket.resolve(.notReady); return
        }
        let observed = await client.restore()
        state.appliedRevenueCatUID = observed.observedAppUserID
        let resolution = SubscriptionOutcomeClassifier.restore(
            observed,
            lease: lease,
            isCurrent: lease == state.readyLease && state.isCurrent(lease)
        )
        apply(resolution)
        ticket.resolve(resolution.outcome)
    }

    func apply<Outcome>(_ resolution: SubscriptionGatewayResolution<Outcome>) {
        switch resolution.effect {
        case .none: break
        case .revoke: revokeForMismatch()
        case .invalidateCache:
            client.invalidatePackageCache()
            state.currentOfferingsEpoch = nil
        case .offeringsEpoch(let epoch): state.currentOfferingsEpoch = epoch
        }
        if let event = resolution.event { emit(event) }
    }

    func revokeForMismatch() {
        client.invalidatePackageCache()
        state.revokeReadiness()
        emit(.revokedAll)
    }

    func emit(_ event: SubscriptionCommitEvent) {
        let stamp = state.nextStamp()
        relay.deliver(StampedSubscriptionCommit(stamp: stamp, event: event))
    }
}

extension SubscriptionGateway {
    // FIX D (audited money-path fix): a single long-lived task for the gateway's whole
    // lifetime, not restarted per sign-in/out. registerStatus() already re-validates identity/
    // lease/staleness on every call, so there's no correctness reason to tear down and restart
    // on re-identify — a single task also trivially rules out duplicate-consumption races. Each
    // update is just a wake-up signal; the resulting registerStatus() call is what actually
    // converges entitlement state (idempotent — see FIX B's interaction note).
    private func startObservingCustomerInfo() {
        guard customerInfoTask == nil else { return }
        let stream = client.observeCustomerInfoUpdates()
        customerInfoTask = Task { @MainActor [weak self] in
            for await _ in stream {
                guard let self else { return }
                _ = self.registerStatus()
            }
        }
    }
}
