import Foundation
import Testing
@testable import Garage

/// Review finding (odometer semantics for edit-in-place): saveLive's guard relaxed from `==` to
/// `>=` — flagged prominently, this is a validation-semantics change — so editing a non-max-
/// odometer entry (whose caller-computed updatedVehicle.currentOdometer can be strictly ahead of
/// the entry's own reading) is no longer rejected. Split out from EntryServiceTests.swift to stay
/// under the file cap; duplicates a minimal local dependencies/spy set for the same reason
/// EntryServiceDeletionTests.swift does (those helpers are private to EntryServiceTests.swift).
@MainActor
struct EntryServiceOdometerGuardTests {
    @Test func saveLive_acceptsVehicleOdometerStrictlyAheadOfTheEnteredEntry() throws {
        let (sync, session) = activeSync()
        let batch = GuardBatchSubmitterSpy()
        let service = EntryService(dependencies: dependencies(sync: sync, batch: batch))
        var vehicle = testVehicle()
        vehicle.currentOdometer = 20_000
        let entry = makeEntry(odometer: 15_000)

        let disposition = try service.save(entry, updatingVehicle: vehicle, session: session)

        #expect(disposition == .atomicEntryAndVehicleAccepted)
        #expect(batch.writes.count == 2)
    }

    @Test func saveLive_stillRejectsVehicleOdometerBehindTheEnteredEntry() throws {
        let (sync, session) = activeSync()
        let batch = GuardBatchSubmitterSpy()
        let service = EntryService(dependencies: dependencies(sync: sync, batch: batch))
        var vehicle = testVehicle()
        vehicle.currentOdometer = 5_000
        let entry = makeEntry(odometer: 15_000)

        do {
            _ = try service.save(entry, updatingVehicle: vehicle, session: session)
            Issue.record("Expected vehicle-behind-entry to still be rejected")
        } catch {
            #expect(error as? AppError == .validation("The entry must update its matching vehicle odometer."))
        }
        #expect(batch.writes.isEmpty)
    }

    private func activeSync() -> (SyncService, SyncSessionToken) {
        let sync = SyncService(monitorFactory: { GuardPassiveMonitor() })
        return (sync, sync.activateSession(uid: "user"))
    }

    private func dependencies(sync: SyncService, batch: GuardBatchSubmitterSpy) -> EntryServiceDependencies {
        EntryServiceDependencies(
            encodeEntry: { ["id": $0.id, "userId": $0.userId] },
            encodeVehicle: { ["id": $0.id, "currentOdometer": $0.currentOdometer, "updatedAt": Date.distantPast] },
            batchSubmitter: batch,
            syncService: sync,
            acknowledgementSink: { token, message in
                Task { @MainActor in sync.recordAcknowledgement(token, message: message) }
            }
        )
    }

    private func makeEntry(odometer: Int) -> FirestoreEntry {
        FirestoreEntry(
            id: "entry", vehicleId: "vehicle", userId: "user", entryType: .fuel,
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

@MainActor
private final class GuardBatchSubmitterSpy: AtomicBatchSubmitting {
    private(set) var writes: [AtomicBatchWrite] = []
    func submitBatch(_ writes: [AtomicBatchWrite], completion: @escaping @Sendable (String?) -> Void) throws {
        self.writes = writes
        completion(nil)
    }
}

@MainActor
private final class GuardPassiveMonitor: SyncConnectivityMonitoring {
    func start(_ handler: @escaping @MainActor @Sendable (SyncConnectivity) -> Void) {}
    func cancel() {}
}
