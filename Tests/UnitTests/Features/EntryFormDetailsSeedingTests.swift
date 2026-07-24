import Foundation
import Testing
@testable import Garage

/// Review BLOCKER (details wipe): edit-in-place used to save over an entry without re-seeding its
/// type-specific `details`, silently wiping them. Each of the 12 forms now seeds its own @State
/// from `entry.decodedDetails(as:)` (FirestoreEntry+decodedDetails, Entry.swift) in its
/// onEditEntry callback. What's actually risky — and what these tests exercise — is the
/// encode/decode round-trip that `decodedDetails` and save()'s `makeAnyCodableMap` both go
/// through, not the trivial 1:1 field copies each form's own `seed(from:)` does after that.
/// Covers 3 representative forms end to end via the real save() -> fetch -> decode path: OilChange
/// (plain fields), Repair (a `[String]` array field), and Fuel (a Codable enum field, plus the
/// MPG-recompute-must-exclude-itself edit case).
@MainActor
struct EntryFormDetailsSeedingTests {
    @Test func oilChangeDetails_roundTripThroughSaveAndDecodeExactly() async throws {
        let vehicle = testVehicle()
        let entries = EntryService(testEntries: [])
        let viewModel = model(entryService: entries, vehicleService: hermeticVehicleService(vehicles: [vehicle]))
        let original = OilChangeEntry(
            oilBrand: "Mobil 1", oilGrade: "0W-40", quantityQuarts: 8.5, filterBrand: "Mann"
        )

        let saved = await viewModel.save(vehicle: vehicle, entryType: .oilChange, details: original)

        let stored = try await entries.fetchRecent(vehicleId: vehicle.id).first
        #expect(saved)
        #expect(stored?.decodedDetails(as: OilChangeEntry.self) == original)
    }

    @Test func repairDetailsWithAnArrayField_roundTripThroughSaveAndDecodeExactly() async throws {
        let vehicle = testVehicle()
        let entries = EntryService(testEntries: [])
        let viewModel = model(entryService: entries, vehicleService: hermeticVehicleService(vehicles: [vehicle]))
        let original = RepairEntry(
            title: "Coolant leak", symptomDescription: "Puddle under the car",
            resolutionDescription: "Replaced water pump", status: .resolved,
            replacedParts: ["Water pump", "Serpentine belt"]
        )

        let saved = await viewModel.save(vehicle: vehicle, entryType: .repair, details: original)

        let stored = try await entries.fetchRecent(vehicleId: vehicle.id).first
        #expect(saved)
        #expect(stored?.decodedDetails(as: RepairEntry.self) == original)
    }

    @Test func fuelDetails_roundTripThroughSaveAndDecodeExactly() async throws {
        let vehicle = testVehicle()
        let entries = EntryService(testEntries: [])
        let viewModel = model(entryService: entries, vehicleService: hermeticVehicleService(vehicles: [vehicle]))
        let original = FuelEntry(
            gallons: 12.4, pricePerGallon: 4.10, totalCost: 50.84, stationName: "Journey Fuel",
            fuelGrade: .premium91, calculatedMPG: 21.5
        )

        let saved = await viewModel.save(vehicle: vehicle, entryType: .fuel, details: original)

        let stored = try await entries.fetchRecent(vehicleId: vehicle.id).first
        #expect(saved)
        #expect(stored?.decodedDetails(as: FuelEntry.self) == original)
    }

    /// The MPG-edit case (review callout): editing the vehicle's own most-recent fill-up must not
    /// find ITSELF as "the previous fill-up" — this is FuelFormView.mpg's excludingEntryID, tested
    /// directly against the service method it calls (FuelFormView itself isn't unit-testable; it's
    /// a SwiftUI View). Covered here rather than duplicated with EntryServiceQueryTests' identical
    /// assertion so this file's MPG-specific intent stays explicit.
    @Test func lastFuelEntry_excludingTheEditedEntryFindsTheTruePreviousFillUpNotItself() async throws {
        let vehicle = testVehicle()
        let previousFillUp = FirestoreEntry(
            id: "fill-1", vehicleId: vehicle.id, userId: "user", entryType: .fuel,
            entryDate: Date(timeIntervalSince1970: 100), odometerReading: 10_000, cost: nil,
            isDiy: nil, shopName: nil, notes: nil, attachmentPaths: [], isResolved: nil,
            details: [:], createdAt: nil, updatedAt: nil
        )
        let entryBeingEdited = FirestoreEntry(
            id: "fill-2", vehicleId: vehicle.id, userId: "user", entryType: .fuel,
            entryDate: Date(timeIntervalSince1970: 200), odometerReading: 10_300, cost: nil,
            isDiy: nil, shopName: nil, notes: nil, attachmentPaths: [], isResolved: nil,
            details: [:], createdAt: nil, updatedAt: nil
        )
        let entries = EntryService(testEntries: [previousFillUp, entryBeingEdited])

        let foundWhileEditing = try await entries.lastFuelEntry(
            vehicleId: vehicle.id, before: entryBeingEdited.entryDate, excludingEntryID: entryBeingEdited.id
        )

        #expect(foundWhileEditing?.id == previousFillUp.id)
    }

    private func model(entryService: EntryService, vehicleService: VehicleService) -> EntryFormViewModel {
        let viewModel = EntryFormViewModel(
            entryService: entryService, vehicleService: vehicleService,
            syncService: SyncService(monitorFactory: { SeedingPassiveMonitor() }),
            analytics: NoopAnalyticsService(), userID: { "user" }
        )
        viewModel.odometerReading = "12100"
        return viewModel
    }

    private func hermeticVehicleService(vehicles: [Vehicle]) -> VehicleService {
        VehicleService(testVehicles: vehicles, purchaseService: PurchaseService(testIsPro: false))
    }

    private func testVehicle() -> Vehicle {
        Vehicle(
            id: "vehicle", userId: "user", nickname: "Test car", make: "Garage", model: "Test",
            year: 2026, currentOdometer: 12_100
        )
    }
}

@MainActor private final class SeedingPassiveMonitor: SyncConnectivityMonitoring {
    func start(_ handler: @escaping @MainActor @Sendable (SyncConnectivity) -> Void) {}
    func cancel() {}
}
