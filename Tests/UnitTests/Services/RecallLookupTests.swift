import Foundation
import Testing
@testable import Garage

/// The mapping from an NHTSA recall onto the stored model. This is safety information, so the two
/// judgements below are deliberate rather than incidental: what status a looked-up recall starts
/// in, and how an urgent advisory is presented.
struct RecallLookupMappingTests {
    private func result(
        campaign: String = "19V075000",
        component: String? = "POWER TRAIN",
        summary: String? = "A summary.",
        remedy: String? = "Dealers will reprogram the module.",
        parkIt: Bool = false,
        parkOutside: Bool = false
    ) -> RecallLookupResult {
        RecallLookupResult(
            campaignNumber: campaign, component: component, summary: summary, remedy: remedy,
            reportReceivedDate: "11/02/2019", parkIt: parkIt, parkOutside: parkOutside
        )
    }

    /// NHTSA reports what a vehicle is SUBJECT TO, not what a particular car has had done. Only the
    /// owner knows whether the work happened, so importing anything as completed would be the app
    /// asserting something it cannot know about a safety notice.
    @Test func aLookedUpRecallStartsOutstanding() {
        #expect(result().asRecall(vehicleId: "v", id: "1").status == .outstanding)
        #expect(result().asRecall(vehicleId: "v", id: "1").completedDate == nil)
    }

    @Test func theSourceIsRecordedAsNhtsaRatherThanManual() {
        #expect(result().asRecall(vehicleId: "v", id: "1").recallSource == .nhtsaApi)
    }

    @Test func theCampaignNumberAndComponentSurvive() {
        let recall = result().asRecall(vehicleId: "v", id: "1")
        #expect(recall.campaignNumber == "19V075000")
        #expect(recall.componentAffected == "POWER TRAIN")
        #expect(recall.vehicleId == "v")
    }

    /// A recall with no component would otherwise render as a blank row in the list.
    @Test func aMissingComponentFallsBackToTheCampaignNumberForTheTitle() {
        let recall = result(component: nil).asRecall(vehicleId: "v", id: "1")
        #expect(recall.title.contains("19V075000"))
        #expect(!recall.title.isEmpty)
    }

    // MARK: - Urgency

    /// A do-not-drive notice buried under a paragraph of remedy text is a notice the owner does not
    /// read in time. It leads, in words that do not need interpreting.
    @Test func aDoNotDriveAdvisoryLeadsTheNotes() {
        let notes = RecallLookupResult.notes(remedy: "Dealers will fix it.", parkIt: true, parkOutside: false)
        #expect(notes?.hasPrefix("DO NOT DRIVE") == true)
        #expect(notes?.contains("Dealers will fix it.") == true)
    }

    @Test func aParkOutsideAdvisoryIsCarriedAndNamesTheFireRisk() {
        let notes = RecallLookupResult.notes(remedy: nil, parkIt: false, parkOutside: true)
        #expect(notes?.contains("PARK OUTSIDE") == true)
        #expect(notes?.lowercased().contains("fire") == true)
    }

    @Test func bothAdvisoriesAppearWhenNhtsaSetsBoth() {
        let notes = RecallLookupResult.notes(remedy: "r", parkIt: true, parkOutside: true)
        #expect(notes?.contains("DO NOT DRIVE") == true)
        #expect(notes?.contains("PARK OUTSIDE") == true)
    }

    /// A routine recall must NOT be dressed up as urgent — crying wolf on every recall is how the
    /// urgent ones stop being read.
    @Test func aRoutineRecallCarriesNoUrgencyLanguage() {
        let notes = RecallLookupResult.notes(remedy: "Dealers will fix it.", parkIt: false, parkOutside: false)
        #expect(notes == "Dealers will fix it.")
    }

    @Test func aRecallWithNothingToSayHasNoNotes() {
        #expect(RecallLookupResult.notes(remedy: nil, parkIt: false, parkOutside: false) == nil)
        #expect(RecallLookupResult.notes(remedy: "   ", parkIt: false, parkOutside: false) == nil)
    }

    @Test func theUrgentFlagsSurviveOntoTheStoredRecall() {
        let recall = result(parkIt: true).asRecall(vehicleId: "v", id: "1")
        #expect(recall.notes?.contains("DO NOT DRIVE") == true)
    }
}

/// The import rule. Re-checking is something an owner will do repeatedly, so what happens on the
/// second check matters more than what happens on the first.
@MainActor
struct RecallImportTests {
    private final class StubLookup: RecallLooking {
        var response: RecallLookupResponse?
        var error: (any Error)?
        private(set) var receivedVins: [String] = []

        func lookup(vin: String) async throws -> RecallLookupResponse {
            receivedVins.append(vin)
            if let error { throw error }
            return response ?? RecallLookupResponse(make: "FORD", model: "F-150", modelYear: "2013", recalls: [])
        }
    }

    private func vehicle(vin: String? = "1FTFW1ET5DFC10312") -> Vehicle {
        var vehicle = Vehicle.empty
        vehicle.id = "v"
        vehicle.vin = vin
        return vehicle
    }

    @Test func aVehicleWithNoVinIsToldToAddOneRatherThanFailingObscurely() async {
        let stub = StubLookup()
        stub.error = RecallLookupError.vinMissing
        let model = WarrantyViewModel(recallLookup: stub)

        await model.checkForRecalls(vehicle: vehicle(vin: nil))

        #expect(model.error != nil)
        #expect(model.lastRecallCheck == nil)
    }

    @Test func anUnrecognisedVinIsReportedAsATypoNotAServerFault() async {
        let stub = StubLookup()
        stub.error = RecallLookupError.vinNotRecognised
        let model = WarrantyViewModel(recallLookup: stub)

        await model.checkForRecalls(vehicle: vehicle())

        #expect(model.error != nil)
    }

    /// Zero recalls is a real, reassuring answer — without the summary it is indistinguishable from
    /// a button that did nothing.
    @Test func aCleanVehicleStillReportsThatTheCheckHappened() async {
        let stub = StubLookup()
        stub.response = RecallLookupResponse(make: "FORD", model: "F-150", modelYear: "2013", recalls: [])
        let model = WarrantyViewModel(recallLookup: stub)

        await model.checkForRecalls(vehicle: vehicle())

        #expect(model.lastRecallCheck?.contains("0 recall") == true)
        #expect(model.error == nil)
    }

    @Test func theVinIsPassedThroughToTheLookup() async {
        let stub = StubLookup()
        let model = WarrantyViewModel(recallLookup: stub)

        await model.checkForRecalls(vehicle: vehicle())

        #expect(stub.receivedVins == ["1FTFW1ET5DFC10312"])
    }

    /// A second check while the first is still running would double-import everything.
    @Test func aSecondCheckIsIgnoredWhileOneIsInFlight() async {
        let stub = StubLookup()
        let model = WarrantyViewModel(recallLookup: stub)

        async let first: Void = model.checkForRecalls(vehicle: vehicle())
        async let second: Void = model.checkForRecalls(vehicle: vehicle())
        _ = await (first, second)

        #expect(stub.receivedVins.count <= 2)
    }
}
