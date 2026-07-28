import Foundation
import Observation
@MainActor @Observable
final class OilAnalysisImportCoordinator: EntryFormMutationGating {
    private let preflighter: any OilAnalysisPDFPreflighting; private let caller: any OilAnalysisCalling
    private let now: () -> Date; private let analytics: any AnalyticsTracking
    private let securityScope: any OilAnalysisPDFSecurityScopeAccessing
    private weak var draftSink: (any OilAnalysisPrefillApplying)?
    private let cancellationWatchdogDelay: Duration
    private var state: OilAnalysisImportState = .idle
    private var isBackgrounded = false; @ObservationIgnored private var currentResultEpoch: UInt64 = 0
    private(set) var outcome: OilAnalysisImportOutcome = .idle; private(set) var mutationEpoch: UInt64 = 0
    var pendingConsent: OilAnalysisPDFConsentRequest? {
        guard case .pending(let request) = state else { return nil }; return request.consent
    }
    var isImporting: Bool {
        if case .importing = state { return true }; if case .cancelling = state { return true }
        return false
    }
    var isCancelling: Bool { if case .cancelling = state { return true }; return false }
    var canCancelActiveImport: Bool { if case .importing = state { return true }; return false }
    var needsCancellationRecovery: Bool { if case .quarantined = state { return true }; return false }
    var isMutationLocked: Bool { isImporting }
    var canBeginPicker: Bool { !isBackgrounded && state.allowsPicker }
    init(
        preflighter: any OilAnalysisPDFPreflighting = OilAnalysisPDFPreflighter(),
        caller: any OilAnalysisCalling = ClaudeService.shared,
        now: @escaping () -> Date = { .now },
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        securityScope: any OilAnalysisPDFSecurityScopeAccessing = URLSecurityScopeAccess(),
        draftSink: (any OilAnalysisPrefillApplying)? = nil,
        cancellationWatchdogDelay: Duration = .seconds(30)
    ) {
        self.preflighter = preflighter; self.caller = caller; self.now = now
        self.analytics = analytics; self.securityScope = securityScope; self.draftSink = draftSink
        self.cancellationWatchdogDelay = cancellationWatchdogDelay
    }
    isolated deinit {
        tearDown()
    }
    func beginPicker(saveInProgress: Bool = false) -> UUID? {
        guard !saveInProgress, canBeginPicker else { return nil }
        let sessionID = UUID(); transition(to: .picking(sessionID))
        return sessionID
    }
    func completePicker(sessionID: UUID, result: Result<URL, Error>, saveInProgress: Bool = false) {
        guard case .picking(let currentID) = state, currentID == sessionID else { return }
        guard !saveInProgress else { transition(to: .idle); return }
        switch result {
        case .success(let url):
            let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let lease = OilAnalysisPDFSecurityScopeLease(url: url, access: securityScope) else {
                transition(to: .idle)
                outcome = .inlineError(.unknown("Couldn't access that PDF. Please choose it again."))
                return
            }
            let request = OilAnalysisPendingImport(
                requestID: UUID(), url: url, displayFilename: name.isEmpty ? "Selected PDF" : name, lease: lease
            )
            outcome = .idle
            transition(to: .pending(request))
        case .failure(let error):
            transition(to: .idle); let error = error as NSError
            if error.domain != NSCocoaErrorDomain || error.code != NSUserCancelledError {
                outcome = .inlineError(.unknown("Couldn't select that PDF. Please try again."))
            }
        }
    }
    func sceneDidChange(isBackgrounded: Bool) {
        self.isBackgrounded = isBackgrounded
        guard isBackgrounded else { return }
        switch state {
        case .picking: transition(to: .idle)
        case .pending(let request): request.lease.release(); transition(to: .idle)
        case .idle, .importing, .cancelling, .quarantined: break
        }
    }
    func cancelPendingConsent(requestID: UUID) {
        guard case .pending(let request) = state, request.requestID == requestID else { return }
        request.lease.release(); transition(to: .idle)
    }
    /// Defers one main-actor turn so a Send/Cancel action can claim the exact captured request first.
    func schedulePassiveDismissal(requestID: UUID) {
        Task { @MainActor [weak self] in await Task.yield(); self?.cancelPendingConsent(requestID: requestID) }
    }
    @discardableResult
    func confirmConsent(requestID: UUID, clientIsPro: Bool, saveInProgress: Bool = false) -> Bool {
        guard !saveInProgress, case .pending(let request) = state, request.requestID == requestID else { return false }
        let active = OilAnalysisActiveImport(
            ownerID: UUID(), requestID: request.requestID, resultEpoch: nextResultEpoch(),
            url: request.url, clientIsPro: clientIsPro, lease: request.lease
        )
        transition(to: .importing(active)); draftSink?.beginAuthorizedImport(ownerID: active.ownerID)
        launchImport(active)
        return true
    }
    func cancelActiveImport() {
        guard case .importing(let active) = state else { return }; cancelImport(ownerID: active.ownerID)
    }
    func cancelImport(ownerID: UUID) {
        guard case .importing(let active) = state, active.ownerID == ownerID else { return }
        invalidate(active); transition(to: .cancelling(active)); installWatchdog(for: active)
    }
    func recoverFromQuarantinedCancellation() {
        guard case .quarantined(let active) = state else { return }
        invalidate(active); active.watchdogTask?.cancel(); outcome = .idle; state = .idle
    }
    func tearDown() {
        switch state {
        case .idle, .picking: transition(to: .idle)
        case .pending(let request): request.lease.release(); transition(to: .idle)
        case .importing(let active): cancelImport(ownerID: active.ownerID)
        case .cancelling(let active), .quarantined(let active):
            draftSink?.abortAuthorizedImport(ownerID: active.ownerID)
            active.lease.release()
            active.importTask?.cancel()
        }
    }
    func acceptsUserMutation(epoch: UInt64) -> Bool { epoch == mutationEpoch && !isMutationLocked }
    func beginSave() -> UInt64? { canCommitSave(epoch: mutationEpoch) ? mutationEpoch : nil }
    func canCommitSave(epoch: UInt64) -> Bool { epoch == mutationEpoch && state.allowsSave }
}
private extension OilAnalysisImportCoordinator {
    /// Gated like every sibling side effect: a failure racing a user cancel is an abandonment.
    func trackFailureIfCurrent(_ reason: OilAnalysisFailureReason, ownerID: UUID, resultEpoch: UInt64) {
        guard isCurrentImport(ownerID: ownerID, resultEpoch: resultEpoch) else { return }
        analytics.track(.oilAnalysisFailed(reason: reason))
    }

    private func launchImport(_ active: OilAnalysisActiveImport) {
        let ownerID = active.ownerID; let resultEpoch = active.resultEpoch; let url = active.url
        let clientIsPro = active.clientIsPro; let lease = active.lease; let preflighter = preflighter
        let caller = caller; let analytics = analytics; let now = now; let draftSink = draftSink
        let startGate = OilAnalysisImportStartGate()
        active.importTask = Task { @MainActor [weak self, lease, preflighter, caller, analytics, now, draftSink] in
            await startGate.wait()
            defer { lease.release(); draftSink?.abortAuthorizedImport(ownerID: ownerID)
                self?.importTaskDidExit(ownerID: ownerID, resultEpoch: resultEpoch) }
            do {
                try Task.checkCancellation()
                guard self?.isCurrentImport(ownerID: ownerID, resultEpoch: resultEpoch) == true else { return }
                let base64 = try await preflighter.preflight(url: url)
                try Task.checkCancellation()
                guard self?.isCurrentImport(ownerID: ownerID, resultEpoch: resultEpoch) == true else { return }
                analytics.track(.oilAnalysisRequested)
                try Task.checkCancellation()
                guard self?.isCurrentImport(ownerID: ownerID, resultEpoch: resultEpoch) == true else { return }
                let entry = try await caller.parseOilAnalysis(pdfBase64: base64, now: now())
                try Task.checkCancellation()
                self?.publishSuccess(.init(entry: entry), ownerID: ownerID, resultEpoch: resultEpoch)
            } catch is CancellationError {
                // No analytics on purpose (runs on teardown/deinit too); abandonment is derived.
            } catch let error as OilAnalysisPDFPreflightError {
                self?.trackFailureIfCurrent(.preflight, ownerID: ownerID, resultEpoch: resultEpoch)
                self?.publish(.inlineError(error.appError), ownerID: ownerID, resultEpoch: resultEpoch)
            } catch let error as OilAnalysisCallableError {
                self?.publishCallableError(error, clientIsPro: clientIsPro, ownerID: ownerID, resultEpoch: resultEpoch)
            } catch {
                self?.trackFailureIfCurrent(.service, ownerID: ownerID, resultEpoch: resultEpoch)
                let message = AppError.unknown("Couldn't import the oil-analysis PDF. Please try again.")
                self?.publish(.inlineError(message), ownerID: ownerID, resultEpoch: resultEpoch)
            }
        }
        Task { await startGate.open() }
    }
    private func publishSuccess(_ prefill: OilAnalysisImportPrefill, ownerID: UUID, resultEpoch: UInt64) {
        guard isCurrentImport(ownerID: ownerID, resultEpoch: resultEpoch) else { return }
        draftSink?.commitImportedPrefill(prefill, ownerID: ownerID)
        analytics.track(.oilAnalysisSucceeded)
        finishActive(ownerID: ownerID, outcome: .prefill(prefill))
    }
    private func publishCallableError(
        _ error: OilAnalysisCallableError, clientIsPro: Bool, ownerID: UUID, resultEpoch: UInt64
    ) {
        guard isCurrentImport(ownerID: ownerID, resultEpoch: resultEpoch) else { return }
        switch error {
        case .freeLifetimeExhausted where clientIsPro:
            finishActive(ownerID: ownerID, outcome: .syncPending)
        case .freeLifetimeExhausted:
            analytics.track(.oilAnalysisQuotaDenied(reason: .freeLifetimeExhausted))
            finishActive(ownerID: ownerID, outcome: .showPaywall)
        case .proDailyExhausted(let resetAt):
            analytics.track(.oilAnalysisQuotaDenied(reason: .proDailyExhausted))
            finishActive(ownerID: ownerID, outcome: .dailyQuota(resetAt: resetAt))
        }
    }
    private func publish(_ outcome: OilAnalysisImportOutcome, ownerID: UUID, resultEpoch: UInt64) {
        guard isCurrentImport(ownerID: ownerID, resultEpoch: resultEpoch) else { return }
        draftSink?.abortAuthorizedImport(ownerID: ownerID)
        finishActive(ownerID: ownerID, outcome: outcome)
    }
    private func finishActive(ownerID: UUID, outcome: OilAnalysisImportOutcome) {
        guard case .importing(let active) = state, active.ownerID == ownerID else { return }
        active.watchdogTask?.cancel()
        self.outcome = outcome
        transition(to: .idle)
    }
    private func installWatchdog(for active: OilAnalysisActiveImport) {
        let ownerID = active.ownerID; let resultEpoch = active.resultEpoch
        let delay = cancellationWatchdogDelay
        active.watchdogTask?.cancel()
        active.watchdogTask = Task { @MainActor [weak self] in
            do {
                if delay == .zero {
                    await Task.yield()
                } else {
                    try await Task.sleep(for: delay)
                }
            } catch {
                return
            }
            self?.quarantineCancellation(ownerID: ownerID, resultEpoch: resultEpoch)
        }
    }
    private func quarantineCancellation(ownerID: UUID, resultEpoch: UInt64) {
        guard case .cancelling(let active) = state, active.ownerID == ownerID,
              active.resultEpoch == resultEpoch else { return }
        _ = nextResultEpoch()
        draftSink?.abortAuthorizedImport(ownerID: ownerID)
        outcome = .inlineError(.unknown(
            "The PDF import did not stop in time. You can continue editing, " +
                "but cannot save or start another import yet."
        ))
        transition(to: .quarantined(active))
    }
    private func importTaskDidExit(ownerID: UUID, resultEpoch: UInt64) {
        let active: OilAnalysisActiveImport
        switch state {
        case .importing(let value), .cancelling(let value), .quarantined(let value): active = value
        case .idle, .picking, .pending: return
        }
        guard active.ownerID == ownerID, active.resultEpoch == resultEpoch else { return }
        active.watchdogTask?.cancel()
        draftSink?.abortAuthorizedImport(ownerID: ownerID)
        if case .quarantined = state { outcome = .idle; state = .idle; return }
        transition(to: .idle)
    }
    private func isCurrentImport(ownerID: UUID, resultEpoch: UInt64) -> Bool {
        guard case .importing(let active) = state else { return false }
        return active.ownerID == ownerID && active.resultEpoch == resultEpoch && currentResultEpoch == resultEpoch
    }
    private func invalidate(_ active: OilAnalysisActiveImport) {
        _ = nextResultEpoch()
        draftSink?.abortAuthorizedImport(ownerID: active.ownerID)
        active.lease.release()
        active.importTask?.cancel()
    }
    private func nextResultEpoch() -> UInt64 { currentResultEpoch &+= 1; return currentResultEpoch }
    private func transition(to state: OilAnalysisImportState) { self.state = state; mutationEpoch &+= 1 }
}
