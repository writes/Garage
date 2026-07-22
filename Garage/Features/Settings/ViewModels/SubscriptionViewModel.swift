import Observation

@MainActor
@Observable
final class SubscriptionViewModel {
    private let service: any SubscriptionFacading
    private var activeAction: SubscriptionActionToken?
    private var actionCounter: UInt64 = 0
    private var presentedNotice: SubscriptionNotice?
    private var observedAccountRevision: UInt64?
    private var lastSDKFailureDiagnostic: SDKFailureDiagnostic?
    private(set) var state: SubscriptionPresentationState = .idle
    init(service: any SubscriptionFacading) { self.service = service }
    var plans: OfferingsSnapshot? { service.plans }
    var isPro: Bool { service.isPro }
    var accountRevision: UInt64 { service.accountRevision }
    var isBusy: Bool { activeAction != nil }
    var hasPendingReconciliation: Bool { service.pendingReconciliation != nil }

    var presentationOutput: SubscriptionPresentationOutput {
        if let pending = service.pendingReconciliation { return .reconciliation(pending) }
        if case .failure(let error) = state { return .failure(error) }
        if case .reconciliationRequired(let kind) = state { return .reconciliation(kind) }
        if let notice = presentedNotice, notice != .active { return .notice(notice) }
        if presentedNotice == .active, isPro { return .notice(.active) }
        if state == .idle || state == .purchased, isPro { return .notice(.active) }
        if state == .idle, plans == nil { return .notice(.plansUnavailable) }
        return .none
    }

    func accountRevisionChanged(to revision: UInt64) { synchronizeRevision(revision) }

    func refreshTapped() async {
        synchronizeRevision(accountRevision)
        guard beginAction(.refreshPlans, initialState: .loadingPlans) != nil else { return }
        guard let token = activeAction else { return }
        let status = await service.refreshStatus()
        synchronizeRevision(accountRevision)
        guard activeAction == token else { return }
        switch status {
        case .committed, .staleDiscarded:
            state = .loadingPlans
            presentedNotice = nil
        default:
            apply(status, token: token)
            return
        }
        let offerings = await service.loadOfferings()
        synchronizeRevision(accountRevision)
        guard activeAction == token else { return }
        apply(offerings, token: token)
    }

    func choosePackageTapped(_ dto: PackageDTO) async {
        synchronizeRevision(accountRevision)
        guard !rejectBusy() else { return }
        if let pending = service.pendingReconciliation {
            state = .reconciliationRequired(pending)
            presentedNotice = nil
            return
        }
        guard preflightCapacity() else { return }
        guard let selection = service.makeSelection(for: dto) else {
            state = .selectionInvalidated
            presentedNotice = .selectionInvalidated
            return
        }
        guard let token = startAction(.purchase, state: .purchasing) else { return }
        let outcome = await service.purchase(selection)
        synchronizeRevision(accountRevision)
        guard activeAction == token else { return }
        apply(outcome, token: token)
    }

    func restoreTapped() async {
        synchronizeRevision(accountRevision)
        guard beginAction(.restore, initialState: .restoring) != nil else { return }
        guard let token = activeAction else { return }
        let outcome = await service.restore()
        synchronizeRevision(accountRevision)
        guard activeAction == token else { return }
        apply(outcome, token: token)
    }
}

private extension SubscriptionViewModel {
    var hasActionCapacity: Bool { actionCounter != .max }

    func synchronizeRevision(_ revision: UInt64) {
        guard let observedAccountRevision else {
            self.observedAccountRevision = revision
            return
        }
        guard observedAccountRevision != revision else { return }
        self.observedAccountRevision = revision
        activeAction = nil
        state = .idle
        presentedNotice = nil
        lastSDKFailureDiagnostic = nil
    }

    private func beginAction(
        _ kind: SubscriptionActionKind,
        initialState: SubscriptionPresentationState
    ) -> SubscriptionActionToken? {
        guard !rejectBusy(), preflightCapacity() else { return nil }
        return startAction(kind, state: initialState)
    }

    func rejectBusy() -> Bool {
        guard isBusy else { return false }
        presentedNotice = .busy
        return true
    }

    func preflightCapacity() -> Bool {
        guard hasActionCapacity else { rejectActionCapacityOverflow(); return false }
        return true
    }

    private func startAction(
        _ kind: SubscriptionActionKind,
        state: SubscriptionPresentationState
    ) -> SubscriptionActionToken? {
        presentedNotice = nil
        lastSDKFailureDiagnostic = nil
        guard let token = mintActionToken(kind) else { return nil }
        activeAction = token
        self.state = state
        return token
    }

    private func mintActionToken(_ kind: SubscriptionActionKind) -> SubscriptionActionToken? {
        let (next, overflowed) = actionCounter.addingReportingOverflow(1)
        guard !overflowed else { rejectActionCapacityOverflow(); return nil }
        actionCounter = next
        return SubscriptionActionToken(id: next, kind: kind)
    }

    func rejectActionCapacityOverflow() {
        state = .unavailable
        presentedNotice = .notReady
        lastSDKFailureDiagnostic = nil
    }

    private func finish(
        _ token: SubscriptionActionToken,
        state: SubscriptionPresentationState,
        notice: SubscriptionNotice?
    ) {
        guard activeAction == token else { return }
        activeAction = nil
        self.state = state
        presentedNotice = notice
    }

    private func apply(_ outcome: StatusOutcome, token: SubscriptionActionToken) {
        switch outcome {
        case .notReady: finish(token, state: .unavailable, notice: .notReady)
        case .failed(let error): finishFailure(error, operation: .status, token: token)
        case .committed, .staleDiscarded: break
        }
    }

    private func apply(_ outcome: OfferingsOutcome, token: SubscriptionActionToken) {
        switch outcome {
        case .loaded, .staleDiscarded: finish(token, state: .idle, notice: nil)
        case .unavailable: finish(token, state: .unavailable, notice: .plansUnavailable)
        case .cacheInvalidated:
            finish(token, state: .selectionInvalidated, notice: .selectionInvalidated)
        case .notReady: finish(token, state: .unavailable, notice: .notReady)
        case .failed(let error): finishFailure(error, operation: .offerings, token: token)
        }
    }

    private func apply(_ outcome: PurchaseOutcome, token: SubscriptionActionToken) {
        switch outcome {
        case .activePro: finish(token, state: .purchased, notice: .active)
        case .noEntitlement: finish(token, state: .noEntitlement, notice: .purchaseNoEntitlement)
        case .cancelled: finish(token, state: .cancelled, notice: .cancelled)
        case .busy: finish(token, state: .idle, notice: .busy)
        case .notReady: finish(token, state: .unavailable, notice: .notReady)
        case .selectionInvalidated:
            finish(token, state: .selectionInvalidated, notice: .selectionInvalidated)
        case .reconciliationRequired:
            finish(token, state: .reconciliationRequired(.purchase), notice: nil)
        case .failed(let error): finishFailure(error, operation: .purchase, token: token)
        }
    }

    private func apply(_ outcome: RestoreOutcome, token: SubscriptionActionToken) {
        switch outcome {
        case .activeEntitlement:
            finish(token, state: .purchased, notice: .active)
        case .noActiveEntitlement:
            finish(token, state: .noEntitlement, notice: .restoreNoActive)
        case .busy: finish(token, state: .idle, notice: .busy)
        case .notReady: finish(token, state: .unavailable, notice: .notReady)
        case .reconciliationRequired:
            finish(token, state: .reconciliationRequired(.restore), notice: nil)
        case .failed(let error): finishFailure(error, operation: .restore, token: token)
        }
    }

    enum FailureOperation { case status, offerings, purchase, restore }

    private func finishFailure(
        _ error: SubscriptionError,
        operation: FailureOperation,
        token: SubscriptionActionToken
    ) {
        if case let .sdk(domain, code, message) = error {
            lastSDKFailureDiagnostic = SDKFailureDiagnostic(domain: domain, code: code, message: message)
        }
        finish(token, state: .failure(map(error, operation: operation)), notice: nil)
    }

    func map(_ error: SubscriptionError, operation: FailureOperation) -> AppError {
        if case .identityMismatch = error {
            return .unknown("Subscription account changed. Sign in again.")
        }
        switch operation {
        case .status: return .unknown("Your subscription status couldn't be refreshed. Try again.")
        case .offerings:
            return .unknown("Plans couldn't be loaded. Check your connection, then tap Refresh Plans.")
        case .purchase:
            return .unknown(
                "The purchase couldn't be completed. No entitlement was granted. " +
                    "If you believe you were charged, use Restore Purchases."
            )
        case .restore: return .unknown("Restore couldn't be completed. Try again.")
        }
    }
}

#if DEBUG
extension SubscriptionViewModel {
    var diagnostics: SubscriptionViewModelDiagnostics {
        SubscriptionViewModelDiagnostics(
            sdkFailureDiagnostic: lastSDKFailureDiagnostic,
            actionCounter: actionCounter,
            activeActionID: activeAction?.id
        )
    }

    func setActionCounterForTesting(_ value: UInt64) { actionCounter = value }
}
#endif
