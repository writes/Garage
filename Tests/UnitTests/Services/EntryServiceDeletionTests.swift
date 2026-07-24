import Foundation
import Testing
@testable import Garage

/// Review finding (currentOdometer staleness on delete): deleting the entry that backed a
/// vehicle's currentOdometer left that field pointing at a document that no longer exists unless
/// the caller's vehicle snapshot is passed in for reconciliation. Split out of EntryServiceTests
/// to stay under the file cap — mirrors that file's EntryServiceQueryTests precedent.
@MainActor
struct EntryServiceDeletionTests {
    // Hermetic testEntries mode has no companion vehicle doc, so even passing a vehicle whose
    // currentOdometer matches the deleted entry must NOT attempt reconciliation — entry-only,
    // same as passing nil. The live-Firestore reconciliation path (deleteLive) isn't reachable
    // through this seam (it calls firestore.db directly, not the mockable `dependencies`), so
    // it's covered by the pure isCurrentOdometerEntry/latestOdometer tests below plus code review.
    @Test func hermeticArrayPathIgnoresAPassedVehicleAndNeverAttemptsReconciliation() async throws {
        let vehicle = testVehicle()
        let entry = makeEntry(id: "delete-me", odometer: vehicle.currentOdometer)
        let service = EntryService(testEntries: [entry])
        try await service.deleteEntry(entry, updatingVehicle: vehicle)
        let remaining = try await service.fetchRecent(vehicleId: "vehicle")
        #expect(remaining.isEmpty)
    }

    @Test func isCurrentOdometerEntry_trueOnlyWhenVehicleIDAndOdometerBothMatch() {
        let vehicle = testVehicle()
        #expect(EntryService.isCurrentOdometerEntry(makeEntry(odometer: vehicle.currentOdometer), for: vehicle))
        #expect(!EntryService.isCurrentOdometerEntry(makeEntry(odometer: vehicle.currentOdometer - 1), for: vehicle))
        #expect(!EntryService.isCurrentOdometerEntry(
            makeEntry(vehicleId: "other-vehicle", odometer: vehicle.currentOdometer), for: vehicle))
        #expect(!EntryService.isCurrentOdometerEntry(makeEntry(odometer: vehicle.currentOdometer), for: nil))
    }

    @Test func latestOdometer_recomputesTheRemainingMaxAfterTheHighestEntryIsRemoved() {
        // Simulates the state deleteLive/deleteDemo observe right after removing the vehicle's
        // current-max entry: the next-highest remaining entry wins, or nil if none remain.
        let remaining = [makeEntry(id: "low", odometer: 100), makeEntry(id: "mid", odometer: 200)]
        #expect(EntryService.latestOdometer(in: remaining, vehicleId: "vehicle") == 200)
        #expect(EntryService.latestOdometer(in: [], vehicleId: "vehicle") == nil)
    }

    private func makeEntry(
        id: String = "entry", vehicleId: String = "vehicle", odometer: Int = 12_100
    ) -> FirestoreEntry {
        FirestoreEntry(
            id: id, vehicleId: vehicleId, userId: "user", entryType: .fuel,
            entryDate: .now, odometerReading: odometer, cost: nil, isDiy: nil, shopName: nil,
            notes: nil, attachmentPaths: [], isResolved: nil, details: [:], createdAt: nil, updatedAt: nil
        )
    }

    private func testVehicle() -> Vehicle {
        Vehicle(
            id: "vehicle", userId: "user", nickname: "Test car", make: "Garage",
            model: "Test", year: 2026, currentOdometer: 12_100
        )
    }
}
