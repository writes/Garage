import Foundation
import Testing
@testable import Garage

@MainActor
struct OilAnalysisImportCoordinatorPickerTests {
    @Test func cancelAndPassiveDismissal_releaseTheExactPendingLease_withoutReadingOrSending() async {
        let preflighter = ScriptedPreflighter(steps: [])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let scope = RecordingOilAnalysisSecurityScope()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            preflighter: preflighter,
            caller: caller,
            analytics: analytics,
            securityScope: scope
        )

        let cancelledRequestID = OilAnalysisImportTestSupport.stage(coordinator)
        coordinator.cancelPendingConsent(requestID: cancelledRequestID)
        #expect(coordinator.pendingConsent == nil)
        #expect(scope.events == [.acquired, .released])

        let passiveRequestID = OilAnalysisImportTestSupport.stage(coordinator)
        coordinator.schedulePassiveDismissal(requestID: passiveRequestID)
        await waitForPendingConsentToClear(coordinator)

        #expect(coordinator.pendingConsent == nil)
        #expect(scope.events == [.acquired, .released, .acquired, .released])
        #expect(preflighter.callCount == 0)
        #expect(caller.callCount == 0)
        #expect(analytics.events.isEmpty)
    }

    // .timeLimit: this test deadlocked CI for 2h14m (run 30410262258) — a single Task.yield()
    // after cancelActiveImport lost the race to the cancellation-unwind chain on slow runner
    // hardware, stage() fell back to a throwaway UUID, and waitForCall(count: 2) awaited a
    // continuation nothing would ever resume. The waitForCompletion below closes the race; the
    // time limit makes any recurrence fail in a minute instead of hanging the suite.
    @Test(.timeLimit(.minutes(1))) func sendClaimWinsWhenDismissalCallbackArrivesFirst_orAfterward() async {
        let preflighter = ScriptedPreflighter(steps: [.suspended, .suspended])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let scope = RecordingOilAnalysisSecurityScope()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            preflighter: preflighter,
            caller: caller,
            analytics: analytics,
            securityScope: scope
        )

        let firstRequest = OilAnalysisImportTestSupport.stage(coordinator)
        coordinator.schedulePassiveDismissal(requestID: firstRequest)
        OilAnalysisImportTestSupport.confirm(coordinator, requestID: firstRequest)
        await preflighter.waitForCall()
        #expect(coordinator.pendingConsent == nil)
        coordinator.cancelActiveImport()
        preflighter.completeSuspended(with: .success("ignored"))
        // A single yield is not enough for .cancelling -> .idle on slow hardware; stage() would
        // then be refused and its fallback UUID stranded the later waitForCall forever.
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)

        let secondRequest = OilAnalysisImportTestSupport.stage(coordinator)
        OilAnalysisImportTestSupport.confirm(coordinator, requestID: secondRequest)
        coordinator.schedulePassiveDismissal(requestID: secondRequest)
        await preflighter.waitForCall(count: 2)
        #expect(coordinator.pendingConsent == nil)
        coordinator.cancelActiveImport()
        preflighter.completeSuspended(with: .success("ignored"))
        await Task.yield()

        #expect(analytics.events.isEmpty)
        #expect(scope.events.filter { $0 == .released }.count == 2)
    }

    @Test func inactivePickerCompletionAndPendingConsent_arePreserved() async {
        let preflighter = ScriptedPreflighter(steps: [.suspended])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let scope = RecordingOilAnalysisSecurityScope()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            preflighter: preflighter,
            caller: caller,
            analytics: analytics,
            securityScope: scope
        )

        let firstSession = coordinator.beginPicker(saveInProgress: false)
        #expect(firstSession != nil)
        guard let firstSession else { return }
        coordinator.sceneDidChange(isBackgrounded: false)
        coordinator.completePicker(
            sessionID: firstSession,
            result: .success(OilAnalysisImportTestSupport.sampleURL)
        )
        guard let requestID = coordinator.pendingConsent?.id else {
            Issue.record("Inactive picker completion should stage a consent request.")
            return
        }
        #expect(scope.events == [.acquired])
        coordinator.sceneDidChange(isBackgrounded: false)
        #expect(coordinator.pendingConsent?.id == requestID)

        OilAnalysisImportTestSupport.confirm(coordinator, requestID: requestID)
        await preflighter.waitForCall()
        coordinator.cancelActiveImport()
        preflighter.completeSuspended(with: .success("ignored"))
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)
        #expect(scope.events == [.acquired, .released])
    }

    @Test func backgroundInvalidatesPickerAndPending_andIgnoresLateCallbacks() {
        let preflighter = ScriptedPreflighter(steps: [])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let scope = RecordingOilAnalysisSecurityScope()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            preflighter: preflighter,
            caller: caller,
            analytics: analytics,
            securityScope: scope
        )

        let firstSession = coordinator.beginPicker(saveInProgress: false)
        #expect(firstSession != nil)
        guard let firstSession else { return }
        coordinator.sceneDidChange(isBackgrounded: true)
        coordinator.sceneDidChange(isBackgrounded: false)
        coordinator.completePicker(sessionID: firstSession, result: .success(OilAnalysisImportTestSupport.sampleURL))
        #expect(coordinator.pendingConsent == nil)
        #expect(scope.events.isEmpty)

        let requestID = OilAnalysisImportTestSupport.stage(coordinator)
        coordinator.sceneDidChange(isBackgrounded: true)
        coordinator.sceneDidChange(isBackgrounded: false)
        _ = coordinator.confirmConsent(requestID: requestID, clientIsPro: false)

        #expect(coordinator.pendingConsent == nil)
        #expect(preflighter.callCount == 0)
        #expect(scope.events == [.acquired, .released])
        #expect(analytics.events.isEmpty)
    }

    @Test func secondPickerAndStaleConfirmation_areRejected_whileConsentIsPending() {
        let preflighter = ScriptedPreflighter(steps: [])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            preflighter: preflighter,
            caller: caller,
            analytics: analytics
        )
        let requestID = OilAnalysisImportTestSupport.stage(coordinator)

        #expect(coordinator.beginPicker(saveInProgress: false) == nil)
        _ = coordinator.confirmConsent(requestID: UUID(), clientIsPro: false)

        #expect(coordinator.pendingConsent?.id == requestID)
        #expect(preflighter.callCount == 0)
        #expect(caller.callCount == 0)
        #expect(analytics.events.isEmpty)
    }

    @Test func failedScopeAcquisition_failsClosed_withoutStagingOrReading() {
        let preflighter = ScriptedPreflighter(steps: [.failure(.unreadableFile)])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let scope = RecordingOilAnalysisSecurityScope()
        scope.shouldAcquire = false
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            preflighter: preflighter,
            caller: caller,
            analytics: analytics,
            securityScope: scope
        )
        guard let sessionID = coordinator.beginPicker() else {
            Issue.record("Expected the idle coordinator to admit the picker.")
            return
        }
        coordinator.completePicker(sessionID: sessionID, result: .success(OilAnalysisImportTestSupport.sampleURL))

        #expect(scope.events == [.acquired])
        #expect(coordinator.pendingConsent == nil)
        #expect(coordinator.outcome == .inlineError(.unknown("Couldn't access that PDF. Please choose it again.")))
        #expect(preflighter.callCount == 0)
        #expect(caller.callCount == 0)
        #expect(analytics.events.isEmpty)
    }
}

private extension OilAnalysisImportCoordinatorPickerTests {
    func waitForPendingConsentToClear(_ coordinator: OilAnalysisImportCoordinator) async {
        for _ in 0 ..< 100 {
            if coordinator.pendingConsent == nil { return }
            await Task.yield()
        }
        #expect(coordinator.pendingConsent == nil)
    }
}
