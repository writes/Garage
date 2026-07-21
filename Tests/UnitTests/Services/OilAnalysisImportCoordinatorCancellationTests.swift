import Foundation
import Testing
import SwiftUI
@testable import Garage

@MainActor
struct OilAnalysisImportCancellationTests {
    @Test func cancellationInsensitiveCallableCannotPublishStalePrefillErrorOrAnalytics() async {
        let preflighter = ScriptedPreflighter(steps: [.suspended])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let scope = RecordingOilAnalysisSecurityScope()
        let sink = RecordingOilAnalysisDraftSink()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            draftSink: sink,
            preflighter: preflighter,
            caller: caller,
            analytics: analytics,
            securityScope: scope
        )
        let requestID = OilAnalysisImportTestSupport.stage(coordinator)

        OilAnalysisImportTestSupport.confirm(coordinator, requestID: requestID)
        await preflighter.waitForCall()
        preflighter.completeSuspended(with: .success("bounded-base64"))
        await caller.waitForCall()
        #expect(analytics.events == [.oilAnalysisRequested])

        coordinator.cancelActiveImport()
        #expect(scope.events == [.acquired, .released])
        caller.complete(with: .success(OilAnalysisImportTestSupport.sampleEntry(iron: 99)))
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)

        #expect(coordinator.outcome == .idle)
        #expect(sink.fields.iron.isEmpty)
        #expect(sink.authorizedOwner == nil)
        #expect(analytics.events == [.oilAnalysisRequested])
        #expect(scope.events == [.acquired, .released])
    }

    @Test func cancellationWatchdog_blocksSaveButKeepsLiveEdits_whenQuarantined() async {
        let preflighter = ScriptedPreflighter(steps: [.suspended])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let scope = RecordingOilAnalysisSecurityScope()
        let draft = OilAnalysisDraft()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            draftSink: draft,
            preflighter: preflighter,
            caller: caller,
            analytics: analytics,
            securityScope: scope,
            watchdogDelay: .zero
        )
        let requestID = OilAnalysisImportTestSupport.stage(coordinator)

        OilAnalysisImportTestSupport.confirm(coordinator, requestID: requestID)
        await preflighter.waitForCall()
        coordinator.cancelActiveImport()
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)

        #expect(!coordinator.isImporting)
        #expect(coordinator.canBeginPicker == false)
        let liveEditEpoch = coordinator.mutationEpoch
        #expect(!coordinator.canCommitSave(epoch: liveEditEpoch))
        #expect(coordinator.beginSave() == nil)
        #expect(coordinator.acceptsUserMutation(epoch: liveEditEpoch))
        #expect(!coordinator.isMutationLocked)
        #expect(scope.events == [.acquired, .released])
        let iron = draft.textBinding(\.iron, gate: coordinator)
        iron.wrappedValue = "17"
        #expect(draft.editableFields.iron == "17")

        preflighter.completeSuspended(with: .success("ignored"))
        for _ in 0 ..< 100 {
            if coordinator.canBeginPicker { break }
            await Task.yield()
        }

        #expect(coordinator.canBeginPicker)
        #expect(coordinator.mutationEpoch == liveEditEpoch)
        iron.wrappedValue = "18"
        #expect(draft.editableFields.iron == "18")
        #expect(scope.events == [.acquired, .released])
        #expect(analytics.events.isEmpty)
    }

    @Test func explicitRecovery_preservesEdits_andRejectsLateTaskCompletion_withoutChangingMutationEpoch() async {
        let preflighter = ScriptedPreflighter(steps: [.suspended])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let scope = RecordingOilAnalysisSecurityScope()
        let draft = OilAnalysisDraft()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            draftSink: draft,
            preflighter: preflighter,
            caller: caller,
            analytics: analytics,
            securityScope: scope,
            watchdogDelay: .zero
        )
        let requestID = OilAnalysisImportTestSupport.stage(coordinator)

        OilAnalysisImportTestSupport.confirm(coordinator, requestID: requestID)
        await preflighter.waitForCall()
        coordinator.cancelActiveImport()
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)
        #expect(coordinator.needsCancellationRecovery)

        let liveEditEpoch = coordinator.mutationEpoch
        let iron = draft.textBinding(\.iron, gate: coordinator)
        iron.wrappedValue = "17"
        coordinator.cancelActiveImport()
        #expect(coordinator.mutationEpoch == liveEditEpoch)
        coordinator.recoverFromQuarantinedCancellation()

        #expect(!coordinator.needsCancellationRecovery)
        #expect(coordinator.outcome == .idle)
        #expect(coordinator.mutationEpoch == liveEditEpoch)
        #expect(coordinator.canBeginPicker)
        #expect(coordinator.canCommitSave(epoch: liveEditEpoch))
        iron.wrappedValue = "18"
        #expect(draft.editableFields.iron == "18")

        preflighter.completeSuspended(with: .success("ignored"))
        for _ in 0 ..< 4 { await Task.yield() }

        #expect(coordinator.outcome == .idle)
        #expect(coordinator.mutationEpoch == liveEditEpoch)
        #expect(coordinator.canBeginPicker)
        #expect(scope.events == [.acquired, .released])
        #expect(analytics.events.isEmpty)
    }

    @Test func completedCancellation_cancelsItsWatchdog_beforeItCanQuarantineANewerLifecycle() async {
        let preflighter = ScriptedPreflighter(steps: [.suspended, .suspended])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            preflighter: preflighter,
            caller: caller,
            analytics: analytics,
            watchdogDelay: .seconds(1)
        )
        let firstRequest = OilAnalysisImportTestSupport.stage(coordinator)

        OilAnalysisImportTestSupport.confirm(coordinator, requestID: firstRequest)
        await preflighter.waitForCall()
        coordinator.cancelActiveImport()
        preflighter.completeSuspended(with: .success("ignored"))
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)

        let secondRequest = OilAnalysisImportTestSupport.stage(coordinator)
        OilAnalysisImportTestSupport.confirm(coordinator, requestID: secondRequest)
        await preflighter.waitForCall(count: 2)

        #expect(coordinator.isImporting)
        coordinator.cancelActiveImport()
        preflighter.completeSuspended(with: .success("ignored"))
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)
    }

    @Test func teardown_revokesAuthorizedPrefill_andReleasesTheLeaseBeforeTheOwnerTaskExits() async {
        let preflighter = ScriptedPreflighter(steps: [.suspended])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let scope = RecordingOilAnalysisSecurityScope()
        let sink = RecordingOilAnalysisDraftSink()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            draftSink: sink,
            preflighter: preflighter,
            caller: caller,
            analytics: analytics,
            securityScope: scope
        )

        let requestID = OilAnalysisImportTestSupport.stage(coordinator)
        OilAnalysisImportTestSupport.confirm(coordinator, requestID: requestID)
        await preflighter.waitForCall()

        coordinator.tearDown()
        #expect(sink.authorizedOwner == nil)
        #expect(scope.events == [.acquired, .released])

        preflighter.completeSuspended(with: .success("ignored"))
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)

        #expect(scope.events == [.acquired, .released])
        #expect(analytics.events.isEmpty)
    }

    @Test func deinit_revokesAuthorizedPrefill_andCancelsTheOwnerTask() async {
        let preflighter = ScriptedPreflighter(steps: [.suspended])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let scope = RecordingOilAnalysisSecurityScope()
        let sink = RecordingOilAnalysisDraftSink()
        var coordinator: OilAnalysisImportCoordinator? = OilAnalysisImportTestSupport.makeCoordinator(
            draftSink: sink,
            preflighter: preflighter,
            caller: caller,
            analytics: analytics,
            securityScope: scope
        )

        if let coordinator {
            let requestID = OilAnalysisImportTestSupport.stage(coordinator)
            OilAnalysisImportTestSupport.confirm(coordinator, requestID: requestID)
        } else {
            Issue.record("Expected the coordinator to be created.")
            return
        }
        await preflighter.waitForCall()

        coordinator = nil
        #expect(sink.authorizedOwner == nil)

        preflighter.completeSuspended(with: .success("ignored"))
        for _ in 0 ..< 4 { await Task.yield() }

        #expect(scope.events == [.acquired, .released])
        #expect(analytics.events.isEmpty)
    }
}
