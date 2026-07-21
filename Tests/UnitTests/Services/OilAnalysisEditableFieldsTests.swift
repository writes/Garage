import Testing
import SwiftUI
@testable import Garage

@MainActor
struct OilAnalysisEditableFieldsTests {
    @Test func importPrefill_overwritesOnlyNonNilEditableFields() {
        var fields = OilAnalysisEditableFields(
            labName: "M",
            viscosity: "V",
            milesOnOil: "1",
            iron: "2",
            aluminum: "3",
            labRecommendation: "R"
        )
        fields.apply(OilAnalysisImportPrefill(entry: OilAnalysisImportTestSupport.sampleEntry(
            viscosity: "V2",
            milesOnOil: 4,
            iron: 5,
            aluminum: 6,
            recommendation: "R2"
        )))
        #expect(fields.labName == "L")
        #expect(fields.viscosity == "V2")
        #expect(fields.milesOnOil == "4")
        #expect(fields.iron == "5.0")
        #expect(fields.aluminum == "6.0")
        #expect(fields.labRecommendation == "R2")

        let partialPrefill = OilAnalysisImportPrefill(
            entry: OilAnalysisImportTestSupport.sampleEntry()
        )
        fields.apply(partialPrefill)

        #expect(fields.labName == "L")
        #expect(fields.viscosity == "V2")
        #expect(fields.milesOnOil == "4")
        #expect(fields.iron == "5.0")
        #expect(fields.aluminum == "6.0")
        #expect(fields.labRecommendation == "R2")
    }

    @Test func privilegedDraftPrefill_requiresTheExactOwner_andUpdatesAllFieldsBeforeUnlock() {
        let draft = OilAnalysisDraft()
        let authorizedOwner = UUID()
        draft.commitImportedPrefill(
            OilAnalysisImportPrefill(entry: OilAnalysisImportTestSupport.sampleEntry(iron: 1)),
            ownerID: UUID()
        )
        #expect(draft.editableFields.iron.isEmpty)

        draft.beginAuthorizedImport(ownerID: authorizedOwner)
        draft.commitImportedPrefill(
            OilAnalysisImportPrefill(entry: OilAnalysisImportTestSupport.sampleEntry(
                viscosity: "V",
                milesOnOil: 2,
                iron: 3,
                aluminum: 4,
                recommendation: "R"
            )),
            ownerID: authorizedOwner
        )

        #expect(draft.editableFields == OilAnalysisEditableFields(
            labName: "L",
            viscosity: "V",
            milesOnOil: "2",
            iron: "3.0",
            aluminum: "4.0",
            labRecommendation: "R"
        ))
    }

    @Test func liveBindingRejectsAQueuedWriteAfterConfirmAdvancesMutationEpoch() async {
        let draft = OilAnalysisDraft()
        let preflighter = ScriptedPreflighter(steps: [.suspended])
        let caller = SuspendedOilAnalysisCaller()
        let analytics = OilAnalysisImportTestSupport.enabledAnalytics()
        let coordinator = OilAnalysisImportTestSupport.makeCoordinator(
            draftSink: draft,
            preflighter: preflighter,
            caller: caller,
            analytics: analytics
        )
        let binding = draft.textBinding(\.iron, gate: coordinator)
        binding.wrappedValue = "10"
        let requestID = OilAnalysisImportTestSupport.stage(coordinator)

        OilAnalysisImportTestSupport.confirm(coordinator, requestID: requestID)
        binding.wrappedValue = "999"
        #expect(draft.editableFields.iron == "10")

        await preflighter.waitForCall()
        coordinator.cancelActiveImport()
        preflighter.completeSuspended(with: .success("ignored"))
        await OilAnalysisImportTestSupport.waitForCompletion(coordinator)
    }
}
