import Foundation
import Testing
@testable import Garage

/// The rule that decides a vehicle's `currentOdometer` after an entry is saved.
///
/// It has to do two opposite things, which is why it is easy to get wrong: an entry must never
/// silently LOWER a number the owner declared, and an EDIT must be able to lower it, because
/// correcting a mistyped odometer is exactly what editing is for.
@MainActor
struct VehicleOdometerFloorTests {
    private func vehicle(currentOdometer: Int) -> Vehicle {
        var vehicle = Vehicle.empty
        vehicle.id = "v"
        vehicle.currentOdometer = currentOdometer
        return vehicle
    }

    private func entry(odometer: Int) -> FirestoreEntry {
        FirestoreEntry(
            id: "e", vehicleId: "v", userId: "u", entryType: .oilChange,
            entryDate: Date(timeIntervalSince1970: 1_700_000_000), odometerReading: odometer,
            cost: nil, isDiy: nil, shopName: nil, notes: nil, attachmentPaths: [],
            isResolved: nil, details: [:], createdAt: nil, updatedAt: nil
        )
    }

    // MARK: - Creating an entry

    /// The reported defect. Someone adds a car at 85,000 miles, then logs an oil change they had
    /// done at 84,500 — and the odometer they typed is silently replaced by the lower number, with
    /// no warning and nothing to undo. The declared reading is evidence, not a placeholder.
    @Test func aNewEntryBelowTheDeclaredOdometerDoesNotLowerIt() {
        let updated = EntryFormViewModel.updatedVehicle(
            from: vehicle(currentOdometer: 85_000),
            for: entry(odometer: 84_500),
            otherEntriesMaxOdometer: nil,
            isEditingExistingEntry: false
        )
        #expect(updated.currentOdometer == 85_000)
    }

    @Test func aNewEntryAboveTheDeclaredOdometerRaisesIt() {
        let updated = EntryFormViewModel.updatedVehicle(
            from: vehicle(currentOdometer: 85_000),
            for: entry(odometer: 91_200),
            otherEntriesMaxOdometer: nil,
            isEditingExistingEntry: false
        )
        #expect(updated.currentOdometer == 91_200)
    }

    /// The floor holds past the FIRST entry too — clamping only the first would just defer the
    /// loss to the second one.
    @Test func theDeclaredOdometerStillFloorsOnceOtherEntriesExist() {
        let updated = EntryFormViewModel.updatedVehicle(
            from: vehicle(currentOdometer: 85_000),
            for: entry(odometer: 84_800),
            otherEntriesMaxOdometer: 84_500,
            isEditingExistingEntry: false
        )
        #expect(updated.currentOdometer == 85_000)
    }

    @Test func anotherEntryAheadOfEverythingStillWins() {
        let updated = EntryFormViewModel.updatedVehicle(
            from: vehicle(currentOdometer: 85_000),
            for: entry(odometer: 84_800),
            otherEntriesMaxOdometer: 99_000,
            isEditingExistingEntry: false
        )
        #expect(updated.currentOdometer == 99_000)
    }

    // MARK: - Editing an entry

    /// The opposite requirement, and the reason this cannot simply clamp everything upward: an
    /// owner who fat-fingered 200,000 and corrects it to 100,000 must see the vehicle follow. If
    /// the old value floored the result the wrong number would be permanent.
    @Test func editingDownwardLowersTheVehicleBecauseThatIsWhatCorrectingMeans() {
        let updated = EntryFormViewModel.updatedVehicle(
            from: vehicle(currentOdometer: 200_000),
            for: entry(odometer: 100_000),
            otherEntriesMaxOdometer: nil,
            isEditingExistingEntry: true
        )
        #expect(updated.currentOdometer == 100_000)
    }

    @Test func editingDownwardStillRespectsOtherEntries() {
        let updated = EntryFormViewModel.updatedVehicle(
            from: vehicle(currentOdometer: 200_000),
            for: entry(odometer: 100_000),
            otherEntriesMaxOdometer: 150_000,
            isEditingExistingEntry: true
        )
        #expect(updated.currentOdometer == 150_000)
    }

    // MARK: - Invariant

    /// `EntryService.saveLive` rejects a save whose vehicle odometer is behind the entry's. The
    /// floor only ever raises the result, so it cannot violate that guard — asserted here because
    /// the two rules live in different files and nothing else ties them together.
    @Test func theResultIsNeverBehindTheEntryBeingSaved() {
        for declared in [0, 50_000, 120_000] {
            for reading in [0, 60_000, 130_000] {
                for editing in [true, false] {
                    let updated = EntryFormViewModel.updatedVehicle(
                        from: vehicle(currentOdometer: declared),
                        for: entry(odometer: reading),
                        otherEntriesMaxOdometer: nil,
                        isEditingExistingEntry: editing
                    )
                    #expect(updated.currentOdometer >= reading)
                }
            }
        }
    }
}
