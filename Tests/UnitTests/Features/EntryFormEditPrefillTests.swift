import Foundation
import Testing
@testable import Garage

@MainActor
struct EntryFormEditPrefillTests {
    @Test func applyExistingEntrySeedsSharedFields() {
        let viewModel = EntryFormViewModel()
        let entry = makeEntry(
            odometer: 18_120, cost: 65.25, isDiy: false, shopName: "Willow Springs",
            notes: "Mobil 1 change", entryDate: Date(timeIntervalSince1970: 1_700_000_000)
        )

        viewModel.applyExistingEntry(entry)

        #expect(viewModel.entryDate == entry.entryDate)
        #expect(viewModel.odometerReading == "18120")
        #expect(viewModel.cost == "65.25")
        #expect(viewModel.isDiy == false)
        #expect(viewModel.shopName == "Willow Springs")
        #expect(viewModel.notes == "Mobil 1 change")
        #expect(viewModel.attachmentPaths == entry.attachmentPaths)
        #expect(viewModel.editingEntryID == entry.id)
    }

    @Test func applyExistingEntryDefaultsMissingOptionalsToDiyAndEmptyFields() {
        let viewModel = EntryFormViewModel()
        let entry = makeEntry(cost: nil, isDiy: nil, shopName: nil, notes: nil)

        viewModel.applyExistingEntry(entry)

        #expect(viewModel.cost.isEmpty)
        #expect(viewModel.isDiy == true)
        #expect(viewModel.shopName.isEmpty)
        #expect(viewModel.notes.isEmpty)
    }

    @Test func saveAfterApplyingExistingEntryOverwritesTheSameDocumentInsteadOfCreatingANewOne() async throws {
        let vehicle = testVehicle()
        let existing = makeEntry(id: "existing-entry", vehicleId: vehicle.id, odometer: vehicle.currentOdometer)
        let entries = EntryService(testEntries: [existing])
        let viewModel = model(entryService: entries, vehicleService: hermeticVehicleService(vehicles: [vehicle]))

        viewModel.applyExistingEntry(existing)
        viewModel.notes = "Updated after edit"
        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())

        let stored = try await entries.fetchRecent(vehicleId: vehicle.id, limit: 10)
        #expect(saved)
        #expect(stored.map(\.id) == ["existing-entry"])
        #expect(stored.first?.notes == "Updated after edit")
    }

    @Test func saveAfterApplyingExistingEntryPreservesTheOriginalCreatedAt() async throws {
        let vehicle = testVehicle()
        let originalCreatedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let existing = makeEntry(
            id: "existing-entry", vehicleId: vehicle.id, odometer: vehicle.currentOdometer,
            createdAt: originalCreatedAt
        )
        let entries = EntryService(testEntries: [existing])
        let viewModel = model(entryService: entries, vehicleService: hermeticVehicleService(vehicles: [vehicle]))

        viewModel.applyExistingEntry(existing)
        // A plain (non-edit) save would stamp createdAt = .now; confirm edit does not.
        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())

        let stored = try await entries.fetchRecent(vehicleId: vehicle.id, limit: 10).first
        #expect(saved)
        #expect(stored?.createdAt == originalCreatedAt)
    }

    @Test func editingANonMaxEntryChangingOnlyNotesLeavesVehicleOdometerUnchanged() async throws {
        var vehicle = testVehicle()
        vehicle.currentOdometer = 20_000
        let maxEntry = makeEntry(id: "entry-max", vehicleId: vehicle.id, odometer: 20_000)
        let editedEntry = makeEntry(id: "entry-edited", vehicleId: vehicle.id, odometer: 15_000)
        let entries = EntryService(testEntries: [maxEntry, editedEntry])
        let vehicles = hermeticVehicleService(vehicles: [vehicle])
        let viewModel = model(entryService: entries, vehicleService: vehicles)

        viewModel.applyExistingEntry(editedEntry)
        await viewModel.prepare(vehicleId: vehicle.id)
        viewModel.notes = "Just a note update"
        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())

        let storedVehicle = try await vehicles.fetchVehicles().first { $0.id == vehicle.id }
        let storedEdited = try await entries.fetchRecent(vehicleId: vehicle.id, limit: 10)
            .first { $0.id == "entry-edited" }
        #expect(saved)
        #expect(storedVehicle?.currentOdometer == 20_000)
        #expect(storedEdited?.odometerReading == 15_000)
        #expect(storedEdited?.notes == "Just a note update")
    }

    @Test func loweringTheMaxEntrysOdometerDropsVehicleOdometerToTheNextHighestRemaining() async throws {
        var vehicle = testVehicle()
        vehicle.currentOdometer = 20_000
        let other = makeEntry(id: "entry-other", vehicleId: vehicle.id, odometer: 15_000)
        let editedEntry = makeEntry(id: "entry-edited", vehicleId: vehicle.id, odometer: 20_000)
        let entries = EntryService(testEntries: [other, editedEntry])
        let vehicles = hermeticVehicleService(vehicles: [vehicle])
        let viewModel = model(entryService: entries, vehicleService: vehicles)

        viewModel.applyExistingEntry(editedEntry)
        await viewModel.prepare(vehicleId: vehicle.id)
        viewModel.odometerReading = "16000"
        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())

        let storedVehicle = try await vehicles.fetchVehicles().first { $0.id == vehicle.id }
        #expect(saved)
        #expect(storedVehicle?.currentOdometer == 16_000)
    }

    /// Review BLOCKER: saving an edit against a DIFFERENT vehicle than the entry was opened from
    /// would silently reparent it (duplicate under the wrong vehicle + write that vehicle's
    /// odometer). Nothing may be written when this is caught.
    @Test func savingAnEditAgainstADifferentVehicleFailsAndWritesNothing() async throws {
        let originalVehicle = testVehicle()
        var otherVehicle = testVehicle()
        otherVehicle.id = "other-vehicle"
        let editedEntry = makeEntry(
            id: "entry-edited", vehicleId: originalVehicle.id, odometer: originalVehicle.currentOdometer
        )
        let entries = EntryService(testEntries: [editedEntry])
        let vehicles = hermeticVehicleService(vehicles: [originalVehicle, otherVehicle])
        let viewModel = model(entryService: entries, vehicleService: vehicles)

        viewModel.applyExistingEntry(editedEntry)
        let saved = await viewModel.save(
            vehicle: otherVehicle, entryType: .maintenance, details: maintenanceDetails()
        )

        let stored = try await entries.fetchRecent(vehicleId: originalVehicle.id, limit: 10)
        let storedOtherVehicle = try await vehicles.fetchVehicles().first { $0.id == otherVehicle.id }
        #expect(!saved)
        #expect(viewModel.error == .validation(
            "This entry belongs to a different vehicle. Reopen it from that vehicle's log."
        ))
        #expect(stored.map(\.id) == ["entry-edited"])
        #expect(stored.first?.vehicleId == originalVehicle.id)
        #expect(storedOtherVehicle?.currentOdometer == otherVehicle.currentOdometer)
    }

    @Test func raisingANonMaxEntryAboveTheCurrentMaxRaisesVehicleOdometerToFollow() async throws {
        var vehicle = testVehicle()
        vehicle.currentOdometer = 20_000
        let maxEntry = makeEntry(id: "entry-max", vehicleId: vehicle.id, odometer: 20_000)
        let editedEntry = makeEntry(id: "entry-edited", vehicleId: vehicle.id, odometer: 10_000)
        let entries = EntryService(testEntries: [maxEntry, editedEntry])
        let vehicles = hermeticVehicleService(vehicles: [vehicle])
        let viewModel = model(entryService: entries, vehicleService: vehicles)

        viewModel.applyExistingEntry(editedEntry)
        await viewModel.prepare(vehicleId: vehicle.id)
        viewModel.odometerReading = "25000"
        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())

        let storedVehicle = try await vehicles.fetchVehicles().first { $0.id == vehicle.id }
        #expect(saved)
        #expect(storedVehicle?.currentOdometer == 25_000)
    }

    /// Review BLOCKER: a stale cached lastKnownOdometer (from prepare(), possibly minutes old)
    /// must never be used to compute the WRITTEN vehicle.currentOdometer — only a fresh re-fetch
    /// at save time can. Simulates the race by mutating testEntries directly after prepare() but
    /// before save(): the max entry (entry-a) is removed out from under the cached value, leaving
    /// only the edited entry (entry-b, unchanged at 5,000) — the old cache (20,000) would write a
    /// ghost currentOdometer backed by nothing.
    @Test func staleCachedLastKnownOdometerDoesNotWriteAGhostVehicleOdometer() async throws {
        var vehicle = testVehicle()
        vehicle.currentOdometer = 20_000
        let maxEntry = makeEntry(id: "entry-a", vehicleId: vehicle.id, odometer: 20_000)
        let editedEntry = makeEntry(id: "entry-b", vehicleId: vehicle.id, odometer: 5_000)
        let entries = EntryService(testEntries: [maxEntry, editedEntry])
        let vehicles = hermeticVehicleService(vehicles: [vehicle])
        let viewModel = model(entryService: entries, vehicleService: vehicles)

        viewModel.applyExistingEntry(editedEntry)
        await viewModel.prepare(vehicleId: vehicle.id)
        #expect(viewModel.lastKnownOdometer == 20_000)

        // The race: entry-a (the max) is gone by the time we save — testEntries is `internal`
        // precisely so tests can reach in and simulate this without a second full save flow.
        entries.testEntries = [editedEntry]

        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())

        let storedVehicle = try await vehicles.fetchVehicles().first { $0.id == vehicle.id }
        #expect(saved)
        #expect(storedVehicle?.currentOdometer == 5_000)
    }

    private func model(
        entryService: EntryService, vehicleService: VehicleService
    ) -> EntryFormViewModel {
        EntryFormViewModel(
            entryService: entryService, vehicleService: vehicleService,
            syncService: SyncService(monitorFactory: { EditPrefillPassiveMonitor() }),
            analytics: NoopAnalyticsService(), userID: { "user" }
        )
    }

    private func hermeticVehicleService(vehicles: [Vehicle]) -> VehicleService {
        VehicleService(testVehicles: vehicles, purchaseService: PurchaseService(testIsPro: false))
    }

    private func maintenanceDetails() -> MaintenanceEntry {
        MaintenanceEntry(
            item: .airFilter, otherLabel: nil, nextDueMileage: nil, nextDueDate: nil,
            symptomDescription: nil, resolutionDescription: nil, status: .resolved
        )
    }

    private func makeEntry(
        id: String = "entry", vehicleId: String = "vehicle", odometer: Int = 12_100,
        cost: Double? = nil, isDiy: Bool? = nil, shopName: String? = nil, notes: String? = nil,
        entryDate: Date = .now, createdAt: Date? = nil
    ) -> FirestoreEntry {
        FirestoreEntry(
            id: id, vehicleId: vehicleId, userId: "user", entryType: .maintenance,
            entryDate: entryDate, odometerReading: odometer, cost: cost, isDiy: isDiy,
            shopName: shopName, notes: notes, attachmentPaths: [], isResolved: nil,
            details: [:], createdAt: createdAt, updatedAt: nil
        )
    }

    private func testVehicle() -> Vehicle {
        Vehicle(
            id: "vehicle", userId: "user", nickname: "Test car", make: "Garage", model: "Test",
            year: 2026, currentOdometer: 12_100
        )
    }
}

@MainActor private final class EditPrefillPassiveMonitor: SyncConnectivityMonitoring {
    func start(_ handler: @escaping @MainActor @Sendable (SyncConnectivity) -> Void) {}
    func cancel() {}
}
