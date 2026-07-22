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
    @Test func hermeticArrayPathSavesEntryBeforeAnyLiveDependencyResolution() async throws {
        let service = EntryService(testEntries: [])
        let entry = makeEntry(id: "hermetic")
        let session = SyncSessionToken(uid: "ignored", generation: 0)
        let disposition = try service.save(entry, updatingVehicle: updatingVehicle(), session: session)
        let saved = try await service.fetchRecent(vehicleId: entry.vehicleId)
        #expect(disposition == .entryOnlyAcceptedForHermeticStore)
        #expect(saved.map(\.id) == ["hermetic"])
    }
    @Test func productionProviderUsesSharedIdentityWhileInjectedDependenciesStayIsolated() {
        let injected = isolatedSyncService()
        let batch = BatchSubmitterSpy(), order = OrderRecorder()
        let dependencies = dependencies(sync: injected, batch: batch, order: order)
        #expect(SyncServiceProvider.production.resolve() === SyncService.shared)
        #expect(dependencies.syncService === injected)
        #expect(dependencies.syncService !== SyncService.shared)
    }
    @Test func filter_matchesNotesAndType() {
        let oil = makeEntry(id: "oil", type: .oilChange, notes: "Mobil 1 service")
        let fuel = makeEntry(id: "fuel", type: .fuel, notes: "Station visit")
        #expect(EntryService.filter([oil, fuel], with: "mobil").map(\.id) == ["oil"])
    }
    @Test func fetchEntries_subsetsTypesForVehicle() async throws {
        let service = EntryService(testEntries: [
            makeEntry(id: "fuel", type: .fuel, odometer: 30_000, date: 300),
            makeEntry(id: "oil", type: .oilChange, odometer: 29_000, date: 200),
            makeEntry(id: "repair", type: .repair, odometer: 28_000, date: 100),
            makeEntry(id: "other", type: .fuel, odometer: 1, date: 400, vehicleId: "other")
        ])
        let entries = try await service.fetchEntries(
            query: EntryQuery(vehicleId: "vehicle", entryTypes: [.fuel, .oilChange], searchText: "")
        )
        #expect(entries.map(\.id) == ["fuel", "oil"])
    }
    @Test func latestOdometerAndFuelEntry_useTheirDedicatedOrdering() async throws {
        let service = EntryService(testEntries: [
            makeEntry(id: "older-fuel", type: .fuel, odometer: 31_000, date: 100),
            makeEntry(id: "latest-fuel", type: .fuel, odometer: 30_000, date: 300),
            makeEntry(id: "highest-odometer", type: .repair, odometer: 32_000, date: 200)
        ])
        let odometer = try await service.fetchLatestOdometer(vehicleId: "vehicle")
        let fuel = try await service.lastFuelEntry(vehicleId: "vehicle")
        #expect(odometer == 32_000)
        #expect(fuel?.id == "latest-fuel")
    }
    @Test func fetchEntries_pagesStablyAcrossEqualTimestampBoundaries() async throws {
        let entries = (0..<1_203).map {
            makeEntry(
                id: String(format: "entry-%04d", $0),
                type: .maintenance, odometer: $0, date: paginationDate(for: $0)
            )
        }
        let service = EntryService(testEntries: Array(entries.reversed()))
        var cursor: EntryCursor?
        var counts: [Int] = []
        var ids: [String] = []
        repeat {
            let page = try await service.fetchEntries(
                query: EntryQuery(vehicleId: "vehicle"),
                limit: 500,
                after: cursor
            )
            counts.append(page.entries.count)
            ids += page.entries.map(\.id)
            cursor = page.nextCursor
        } while cursor != nil
        let expected = entries.sorted {
            $0.entryDate != $1.entryDate ? $0.entryDate > $1.entryDate : $0.id > $1.id
        }.map(\.id)
        #expect(counts == [500, 500, 203])
        #expect(ids.count == 1_203 && Set(ids).count == 1_203)
        #expect(ids == expected)
    }
}
private extension EntryServiceTests {
    func activeSync() -> (SyncService, SyncSessionToken) { let sync = isolatedSyncService()
        return (sync, sync.activateSession(uid: "user")) }
    func dependencies(
        sync: SyncService, batch: BatchSubmitterSpy, order: OrderRecorder, vehicleData: [String: Any]? = nil
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
    func paginationDate(for index: Int) -> TimeInterval {
        if (495...505).contains(index) { return 1_999_505 }
        if (995...1_005).contains(index) { return 1_999_005 }
        return 2_000_000 - Double(index)
    }
}
@MainActor private final class BatchSubmitterSpy: AtomicBatchSubmitting {
    private(set) var writes: [AtomicBatchWrite] = []
    private let completesSynchronously: Bool, throwsOnSubmit: Bool
    private let order: OrderRecorder?
    init(completesSynchronously: Bool = false, throwsOnSubmit: Bool = false, order: OrderRecorder? = nil) {
        self.completesSynchronously = completesSynchronously
        self.throwsOnSubmit = throwsOnSubmit
        self.order = order
    }
    func submitBatch(_ writes: [AtomicBatchWrite], completion: @escaping @Sendable (String?) -> Void) throws {
        self.writes = writes
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
