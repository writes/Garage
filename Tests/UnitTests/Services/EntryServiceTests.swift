import Foundation
import Testing
@testable import Garage
@MainActor struct EntryServiceTests {
    @Test func atomicSave_encodesAndSubmitsExactlyTwoMergeWritesWithoutAcknowledgement() throws {
        let (sync, session) = activeSync()
        let order = OrderRecorder(), batch = BatchSubmitterSpy(order: order)
        let entry = makeEntry(id: "stable-entry")
        let encodedOdometer = 12_100, encodedUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let encodedVehicle: [String: Any] = [
            "id": "stale-id", "userId": "stale-user", "nickname": "Stale nickname",
            "vin": "STALE-VIN", "displayOrder": 99,
            "currentOdometer": encodedOdometer, "updatedAt": encodedUpdatedAt
        ]
        let service = EntryService(dependencies: dependencies(
            sync: sync, batch: batch, order: order, vehicleData: encodedVehicle))
        let disposition = try service.save(entry, updatingVehicle: updatingVehicle(), session: session)
        #expect(disposition == .atomicEntryAndVehicleAccepted)
        #expect(order.values == ["entry-encode", "vehicle-encode", "submit"])
        #expect(batch.writes.count == 2 && batch.writes.allSatisfy(\.merge))
        #expect(batch.writes[0].path == "vehicles/vehicle/entries/stable-entry")
        #expect(batch.writes[1].path == "vehicles/vehicle")
        #expect(batch.writes[0].data["id"] as? String == "stable-entry")
        let vehicleWrite = batch.writes[1].data
        #expect(Set(vehicleWrite.keys) == Set(["currentOdometer", "updatedAt"]))
        #expect(vehicleWrite["currentOdometer"] as? Int == encodedOdometer)
        #expect(vehicleWrite["updatedAt"] as? Date == encodedUpdatedAt)
        #expect(["id", "userId", "nickname", "vin", "displayOrder"].allSatisfy { vehicleWrite[$0] == nil })
        #expect(sync.presentationState == .savedOnThisIPhone)
    }
    @Test func synchronousAcknowledgementRunsAfterEvidenceRegistration() async throws {
        let (sync, session) = activeSync()
        let order = OrderRecorder(), batch = BatchSubmitterSpy(completesSynchronously: true)
        sync.recordConnectivity(.reachable, session: session)
        let service = EntryService(dependencies: dependencies(sync: sync, batch: batch, order: order))
        _ = try service.save(makeEntry(), updatingVehicle: updatingVehicle(), session: session)
        await Task.yield()
        sync.recordSnapshotMetadata(session: session, isFromCache: false, hasPendingWrites: false)
        #expect(batch.writes.count == 2)
        #expect(sync.presentationState == .checkingSync)
    }
    @Test func validationRejectsOwnerOrVehicleMismatchBeforeTokenOrBatch() throws {
        let (sync, session) = activeSync()
        let batch = BatchSubmitterSpy(), order = OrderRecorder()
        let service = EntryService(dependencies: dependencies(sync: sync, batch: batch, order: order))
        var wrongVehicle = updatingVehicle()
        wrongVehicle.id = "different-vehicle"
        do {
            _ = try service.save(makeEntry(), updatingVehicle: wrongVehicle, session: session)
            Issue.record("Expected vehicle mismatch to reject before submission")
        } catch {
            #expect(error as? AppError == .validation("The entry must update its matching vehicle odometer."))
        }
        #expect(batch.writes.isEmpty)
        #expect(sync.presentationState == .checkingSync)
    }
    @Test func encoderFailureLatchesFailureWithoutRegistrationOrBatch() throws {
        let (sync, session) = activeSync()
        let batch = BatchSubmitterSpy()
        let dependencies = EntryServiceDependencies(
            encodeEntry: { _ in throw EntryServiceTestError.encoder },
            encodeVehicle: { _ in ["unexpected": true] },
            batchSubmitter: batch,
            syncService: sync,
            acknowledgementSink: { _, _ in }
        )
        let service = EntryService(dependencies: dependencies)
        do {
            _ = try service.save(makeEntry(), updatingVehicle: updatingVehicle(), session: session)
            Issue.record("Expected deterministic encoder failure")
        } catch {
            #expect(error as? EntryServiceTestError == .encoder)
        }
        #expect(batch.writes.isEmpty)
        #expect(sync.presentationState == .needsAttention)
    }
    @Test func missingRequiredVehiclePatchFieldLatchesFailureBeforeRegistrationOrSubmission() throws {
        let (sync, session) = activeSync()
        let order = OrderRecorder(), batch = BatchSubmitterSpy(order: order)
        let service = EntryService(dependencies: dependencies(
            sync: sync, batch: batch, order: order, vehicleData: ["currentOdometer": 12_100]))
        do {
            _ = try service.save(makeEntry(), updatingVehicle: updatingVehicle(), session: session)
            Issue.record("Expected vehicle patch validation failure")
        } catch {
            #expect(error as? AppError == .database("Vehicle sync patch is missing currentOdometer or updatedAt."))
        }
        #expect(order.values == ["entry-encode", "vehicle-encode"])
        #expect(batch.writes.isEmpty)
        #expect(sync.diagnosticMessage == "Vehicle sync patch is missing currentOdometer or updatedAt.")
        #expect(sync.presentationState == .needsAttention)
    }
    @Test func synchronousSubmissionFailureRollsBackExactTokenThenLatchesFailure() throws {
        let (sync, session) = activeSync()
        let order = OrderRecorder(), batch = BatchSubmitterSpy(throwsOnSubmit: true)
        let service = EntryService(dependencies: dependencies(sync: sync, batch: batch, order: order))
        do {
            _ = try service.save(makeEntry(), updatingVehicle: updatingVehicle(), session: session)
            Issue.record("Expected synchronous submission failure")
        } catch {
            #expect(error as? EntryServiceTestError == .submit)
        }
        #expect(batch.writes.count == 2)
        #expect(sync.presentationState == .needsAttention)
    }
    @Test func lateBackendRejectionAfterOptimisticAcceptanceCompensatesWithARevisionBump() async throws {
        let (sync, session) = activeSync()
        let order = OrderRecorder(), batch = BatchSubmitterSpy(order: order)
        let revisionStore = VehicleDataRevisionStore()
        let entry = makeEntry()
        let service = EntryService(dependencies: dependencies(
            sync: sync, batch: batch, order: order, revisionStore: revisionStore))
        let disposition = try service.save(entry, updatingVehicle: updatingVehicle(), session: session)
        #expect(disposition == .atomicEntryAndVehicleAccepted)
        let revisionAfterOptimisticBump = revisionStore.revision(for: entry.vehicleId)

        // submitBatch is fire-and-forget: local acceptance already bumped once above, but the
        // backend can still reject the write after the fact via this captured completion.
        batch.capturedCompletion?("simulated backend rejection")
        await Task.yield()

        #expect(revisionStore.revision(for: entry.vehicleId) > revisionAfterOptimisticBump)
    }
    @Test func hermeticArrayPathSavesEntryBeforeAnyLiveDependencyResolution() async throws {
        let service = EntryService(testEntries: [])
        let entry = makeEntry(id: "hermetic")
        let session = SyncSessionToken(uid: "ignored", generation: 0)
        let disposition = try service.save(entry, updatingVehicle: updatingVehicle(), session: session)
        let saved = try await service.fetchRecent(vehicleId: entry.vehicleId)
        #expect(disposition == .entryOnlyAcceptedForHermeticStore)
        #expect(saved.map(\.id) == ["hermetic"])
    }
    @Test func deleteEntry_hermeticArrayPathRemovesOnlyTheMatchingID() async throws {
        let service = EntryService(testEntries: [makeEntry(id: "keep"), makeEntry(id: "delete-me")])
        try await service.deleteEntry(makeEntry(id: "delete-me"), updatingVehicle: nil)
        let remaining = try await service.fetchRecent(vehicleId: "vehicle")
        #expect(remaining.map(\.id) == ["keep"])
    }
    @Test func deleteEntry_hermeticArrayPathToleratesAnUnknownID() async throws {
        let service = EntryService(testEntries: [makeEntry(id: "keep")])
        try await service.deleteEntry(makeEntry(id: "never-saved"), updatingVehicle: nil)
        let remaining = try await service.fetchRecent(vehicleId: "vehicle")
        #expect(remaining.map(\.id) == ["keep"])
    }
    @Test func productionProviderUsesSharedIdentityWhileInjectedDependenciesStayIsolated() {
        let injected = isolatedSyncService()
        let batch = BatchSubmitterSpy(), order = OrderRecorder()
        let dependencies = dependencies(sync: injected, batch: batch, order: order)
        #expect(SyncServiceProvider.production.resolve() === SyncService.shared)
        #expect(dependencies.syncService === injected)
        #expect(dependencies.syncService !== SyncService.shared)
    }
}
// Query/pagination reads (filter, subsetting, ordering, cursor pagination incl. the #4
// limit+1 sentinel) live in EntryServiceQueryTests.swift; delete-time vehicle-odometer
// reconciliation lives in EntryServiceDeletionTests.swift — both split out to stay under the cap.
private extension EntryServiceTests {
    func activeSync() -> (SyncService, SyncSessionToken) { let sync = isolatedSyncService()
        return (sync, sync.activateSession(uid: "user")) }
    func dependencies(
        sync: SyncService, batch: BatchSubmitterSpy, order: OrderRecorder, vehicleData: [String: Any]? = nil,
        revisionStore: VehicleDataRevisionStore? = nil
    ) -> EntryServiceDependencies {
        EntryServiceDependencies(
            encodeEntry: {
                order.values.append("entry-encode")
                return ["id": $0.id, "userId": $0.userId]
            },
            encodeVehicle: {
                order.values.append("vehicle-encode")
                return vehicleData ?? [
                    "id": $0.id, "currentOdometer": $0.currentOdometer, "updatedAt": Date.distantPast
                ]
            },
            batchSubmitter: batch,
            syncService: sync,
            acknowledgementSink: { token, message in
                Task { @MainActor in sync.recordAcknowledgement(token, message: message) }
            },
            bumpRevision: { vehicleId in
                if let revisionStore { revisionStore.bump(vehicleId: vehicleId) }
            }
        )
    }
    func isolatedSyncService() -> SyncService { SyncService(monitorFactory: { PassiveConnectivityMonitor() }) }
    func makeEntry(
        id: String = "entry",
        type: EntryType = .fuel, odometer: Int = 12_100, date: TimeInterval = 100,
        vehicleId: String = "vehicle", notes: String? = nil
    ) -> FirestoreEntry {
        FirestoreEntry(
            id: id, vehicleId: vehicleId, userId: "user", entryType: type,
            entryDate: Date(timeIntervalSince1970: date), odometerReading: odometer, cost: nil,
            isDiy: nil, shopName: nil, notes: notes, attachmentPaths: [], isResolved: nil,
            details: [:], createdAt: nil, updatedAt: nil
        )
    }
    func updatingVehicle() -> Vehicle { Vehicle(
            id: "vehicle", userId: "user", nickname: "Test car", make: "Garage",
            model: "Test", year: 2026, currentOdometer: 12_100
        ) }
}
@MainActor private final class BatchSubmitterSpy: AtomicBatchSubmitting {
    private(set) var writes: [AtomicBatchWrite] = []
    /// Lets a test simulate a LATE backend rejection by invoking this after submitBatch returns,
    /// independent of completesSynchronously (which fires the completion inline instead).
    private(set) var capturedCompletion: (@Sendable (String?) -> Void)?
    private let completesSynchronously: Bool, throwsOnSubmit: Bool
    private let order: OrderRecorder?
    init(completesSynchronously: Bool = false, throwsOnSubmit: Bool = false, order: OrderRecorder? = nil) {
        self.completesSynchronously = completesSynchronously
        self.throwsOnSubmit = throwsOnSubmit
        self.order = order
    }
    func submitBatch(_ writes: [AtomicBatchWrite], completion: @escaping @Sendable (String?) -> Void) throws {
        self.writes = writes
        capturedCompletion = completion
        order?.values.append("submit")
        if throwsOnSubmit { throw EntryServiceTestError.submit }
        if completesSynchronously { completion(nil) }
    }
}
@MainActor private final class PassiveConnectivityMonitor: SyncConnectivityMonitoring {
    func start(_ handler: @escaping @MainActor @Sendable (SyncConnectivity) -> Void) {}
    func cancel() {} }
@MainActor private final class OrderRecorder {
    var values: [String] = []
}
private enum EntryServiceTestError: LocalizedError, Equatable { case encoder, submit
    var errorDescription: String? { self == .encoder ? "encoder failed" : "submission failed" } }
