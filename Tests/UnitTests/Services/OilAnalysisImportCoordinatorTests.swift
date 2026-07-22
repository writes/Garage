import Foundation
import Testing
@testable import Garage

@MainActor
struct OilAnalysisImportCoordinatorTests {
    @Test func consentStage_doesNotPreflightCallOrTrack_beforeExactRequestIsSent() async {
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

        let requestID = OilAnalysisImportTestSupport.stage(coordinator)

        #expect(coordinator.pendingConsent?.id == requestID)
        #expect(preflighter.callCount == 0)
        #expect(caller.callCount == 0)
        #expect(analytics.events.isEmpty)
        #expect(scope.events == [.acquired])

        OilAnalysisImportTestSupport.confirm(coordinator, requestID: requestID)
        await preflighter.waitForCall()
        #expect(preflighter.callCount == 1)
    }

    @Test func successfulConfirmedImport_prefillsAtomicallyThenUnlocks_andTracksExactlyOnce() async {
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
        #expect(coordinator.isMutationLocked)
        await preflighter.waitForCall()
        preflighter.completeSuspended(with: .success("bounded-base64"))
        await caller.waitForCall()
        let entry = OilAnalysisImportTestSupport.sampleEntry(
            viscosity: "12.3 cSt",
            milesOnOil: 5_000,
            iron: 17,
            aluminum: 4,
            recommendation: "R"
        )
        caller.complete(with: .success(entry))
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)

        #expect(coordinator.outcome == .prefill(OilAnalysisImportPrefill(entry: entry)))
        #expect(sink.fields == OilAnalysisEditableFields(
            labName: "L",
            viscosity: "12.3 cSt",
            milesOnOil: "5000",
            iron: "17.0",
            aluminum: "4.0",
            labRecommendation: "R"
        ))
        #expect(sink.authorizedOwner == nil)
        #expect(!coordinator.isMutationLocked)
        #expect(analytics.events == [.oilAnalysisRequested, .oilAnalysisSucceeded])
        #expect(scope.events == [.acquired, .released])
    }

    @Test func freeQuota_rechecksSendTimeEntitlement_andEmitsOneValidatedDenial() async {
        let preflighter = ScriptedPreflighter(steps: [.suspended])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let sink = RecordingOilAnalysisDraftSink()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            draftSink: sink,
            preflighter: preflighter,
            caller: caller,
            analytics: analytics
        )
        let requestID = OilAnalysisImportTestSupport.stage(coordinator)

        OilAnalysisImportTestSupport.confirm(coordinator, requestID: requestID, clientIsPro: true)
        await preflighter.waitForCall()
        preflighter.completeSuspended(with: .success("bounded-base64"))
        await caller.waitForCall()
        caller.complete(with: .failure(.freeLifetimeExhausted))
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)

        #expect(coordinator.outcome == .syncPending)
        #expect(analytics.events == [.oilAnalysisRequested])
        #expect(sink.authorizedOwner == nil)
    }

    @Test func dailyQuota_emitsExactlyOneValidatedDenial_andRevokesPrefillAuthorization() async {
        let resetAt = Date(timeIntervalSince1970: 1_783_987_200)
        let preflighter = ScriptedPreflighter(steps: [.suspended])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let sink = RecordingOilAnalysisDraftSink()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            draftSink: sink,
            preflighter: preflighter,
            caller: caller,
            analytics: analytics
        )
        let requestID = OilAnalysisImportTestSupport.stage(coordinator)

        OilAnalysisImportTestSupport.confirm(coordinator, requestID: requestID, clientIsPro: true)
        await preflighter.waitForCall()
        preflighter.completeSuspended(with: .success("bounded-base64"))
        await caller.waitForCall()
        caller.complete(with: .failure(.proDailyExhausted(resetAt: resetAt)))
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)

        #expect(coordinator.outcome == .dailyQuota(resetAt: resetAt))
        #expect(analytics.events == [
            .oilAnalysisRequested,
            .oilAnalysisQuotaDenied(reason: .proDailyExhausted)
        ])
        #expect(sink.authorizedOwner == nil)
    }

    @Test func localPreflightFailure_neverCallsRemoteOrAnalytics_andRevokesAuthorization() async {
        let preflighter = ScriptedPreflighter(steps: [.failure(.invalidPDF)])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let sink = RecordingOilAnalysisDraftSink()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            draftSink: sink,
            preflighter: preflighter,
            caller: caller,
            analytics: analytics
        )
        let requestID = OilAnalysisImportTestSupport.stage(coordinator)

        OilAnalysisImportTestSupport.confirm(coordinator, requestID: requestID)
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)

        #expect(coordinator.outcome == .inlineError(.validation("Choose a valid PDF oil-analysis report.")))
        #expect(caller.callCount == 0)
        #expect(analytics.events.isEmpty)
        #expect(sink.authorizedOwner == nil)
    }
}
