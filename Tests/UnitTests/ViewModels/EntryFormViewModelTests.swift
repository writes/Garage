import Foundation
import Testing
@testable import Garage
private typealias FirstEntryFollowUp = EntryFormViewModel.FirstEntryFollowUp
@MainActor struct EntryFormViewModelTests {
    @Test func productionAndInjectedSyncServiceIdentitiesStayIsolatedWithoutFirebaseResolution() {
        let production = EntryFormViewModel()
        let injectedSync = makeSyncService()
        let injected = EntryFormViewModel(
            entryService: EntryService(testEntries: []), vehicleService: hermeticVehicleService(vehicles: []),
            syncService: injectedSync, analytics: NoopAnalyticsService(), userID: { "user" }
        )
        #expect(production.syncServiceIdentity == ObjectIdentifier(SyncService.shared))
        #expect(injected.syncServiceIdentity == ObjectIdentifier(injectedSync))
        #expect(injected.syncServiceIdentity != ObjectIdentifier(SyncService.shared))
    }
    @Test func odometerValidation_rejectsLowerThanLast() {
        let viewModel = makeValidationViewModel()
        viewModel.lastKnownOdometer = 50_000
        viewModel.odometerReading = "49000"
        #expect(viewModel.validateOdometer() == false)
        #expect(viewModel.error == .validation("Odometer must be at least 50,000."))
    }
    @Test func odometerValidation_acceptsHigherThanLast() {
        let viewModel = makeValidationViewModel()
        viewModel.lastKnownOdometer = 50_000
        viewModel.odometerReading = "50150"
        #expect(viewModel.validateOdometer())
    }
    @Test func save_encodesFuelDetailsAndPushesOdometerToHermeticVehicle() async throws {
        let vehicle = testVehicle(), entries = EntryService(testEntries: [])
        let vehicles = hermeticVehicleService(vehicles: [vehicle])
        let viewModel = model(entryService: entries, vehicleService: vehicles)
        viewModel.cost = "65.25"
        let saved = await viewModel.save(vehicle: vehicle, entryType: .fuel, details: fuelDetails())
        let storedEntries = try await entries.fetchRecent(vehicleId: vehicle.id)
        let storedVehicles = try await vehicles.fetchVehicles()
        #expect(saved && storedEntries.count == 1)
        #expect(storedEntries.first?.details["gallons"] == AnyCodable(12.5))
        #expect(storedEntries.first?.details["fuelGrade"] == AnyCodable("premium_91"))
        #expect(storedVehicles.first?.currentOdometer == 12_100)
    }
    @Test func save_encodesOilChangeDetails() async throws {
        let vehicle = testVehicle(), entries = EntryService(testEntries: [])
        let viewModel = model(entryService: entries, vehicleService: hermeticVehicleService(vehicles: [vehicle]))
        viewModel.odometerReading = "12000"
        let saved = await viewModel.save(vehicle: vehicle, entryType: .oilChange, details: oilDetails())
        let stored = try await entries.fetchRecent(vehicleId: vehicle.id)
        #expect(saved)
        #expect(stored.first?.details["oilBrand"] == AnyCodable("Mobil 1"))
        #expect(stored.first?.details["quantityQuarts"] == AnyCodable(8.5))
    }
    @Test func atomicDispositionNeverPerformsSeparateVehicleUpdateOrAwaitsAcknowledgement() async throws {
        let sync = makeSyncService(), vehicle = testVehicle(), batch = HoldingBatchSubmitter()
        let dependencies = EntryServiceDependencies(
            encodeEntry: { ["id": $0.id] },
            encodeVehicle: { ["id": $0.id, "currentOdometer": $0.currentOdometer, "updatedAt": Date.distantPast] },
            batchSubmitter: batch, syncService: sync,
            acknowledgementSink: { token, message in
                Task { @MainActor in sync.recordAcknowledgement(token, message: message) }
            }
        )
        let entries = EntryService(testEntries: [], dependencies: dependencies, usesHermeticSave: false)
        let vehicles = hermeticVehicleService(vehicles: [vehicle])
        let viewModel = model(entryService: entries, vehicleService: vehicles, syncService: sync)
        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())
        let storedVehicles = try await vehicles.fetchVehicles()
        #expect(saved)
        #expect(batch.writes.count == 2 && batch.completionWasRetained)
        #expect(storedVehicles.first?.currentOdometer == vehicle.currentOdometer)
        #expect(sync.presentationState == .savedOnThisIPhone)
    }
    @Test func ownerMismatchRejectsBeforeSessionOrEntryMutation() async throws {
        let vehicle = testVehicle(), sync = makeSyncService(), entries = EntryService(testEntries: [])
        let viewModel = model(
            entryService: entries, vehicleService: hermeticVehicleService(vehicles: [vehicle]),
            syncService: sync, userID: { "other-user" }
        )
        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())
        let stored = try await entries.fetchRecent(vehicleId: vehicle.id)
        #expect(saved == false)
        #expect(viewModel.error == .auth("This vehicle belongs to a different account."))
        #expect(stored.isEmpty)
        #expect(sync.presentationState == .checkingSync)
    }
    @Test func stableIDSurvivesSynchronousFailureThenRotatesAfterLocalAcceptance() async throws {
        let vehicle = testVehicle(), attempts = SaveAttemptRecorder()
        let entries = EntryService(testEntries: [], hermeticSaveFailure: { attempts.failFirstAttempt(for: $0.id) })
        let viewModel = model(entryService: entries, vehicleService: hermeticVehicleService(vehicles: [vehicle]))
        let first = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())
        let retry = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())
        let next = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())
        let saved = try await entries.fetchRecent(vehicleId: vehicle.id, limit: 10)
        #expect(first == false && retry && next && attempts.ids.count == 3)
        #expect(attempts.ids[0] == attempts.ids[1] && attempts.ids[2] != attempts.ids[1])
        #expect(Set(saved.map(\.id)).count == 2 && saved.map(\.id).contains(attempts.ids[0]))
    }
    @Test func reentryWhileSaveTaskIsActiveIsRejected() async {
        let vehicle = testVehicle(), gate = AsyncGate()
        let vehicles = VehicleService(
            testVehicles: [vehicle], purchaseService: PurchaseService(testIsPro: false),
            updateInterceptor: { _ in await gate.wait() }
        )
        let viewModel = model(entryService: EntryService(testEntries: []), vehicleService: vehicles)
        let result = SaveResult()
        Task { @MainActor in
            result.record(await viewModel.save(
                vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails()))
        }
        let didStart = await eventually { gate.isStarted }
        if !didStart {
            gate.resume(); let didFinish = await eventually { result.value != nil && !viewModel.isSaving }
            #expect(Bool(false), "Timed out waiting for the initial save task to reach its gate.")
            #expect(didFinish, "Initial save task did not finish after the gate was released."); return
        }
        #expect(didStart && viewModel.isSaving)
        let reentrant = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())
        gate.resume(); let didFinish = await eventually { result.value != nil && !viewModel.isSaving }
        #expect(didFinish && result.value == true); #expect(reentrant == false)
    }
    @Test func localAcceptanceReturnsWhileFirstEntryFollowUpRemainsBlocked() async {
        let vehicle = testVehicle(), analytics = AnalyticsSpy(), gate = AsyncGate()
        analytics.setEnabled(true)
        let viewModel = firstEntryModel(vehicles: [vehicle], tracker: analytics, gate: gate)
        let result = SaveResult()
        Task { @MainActor in
            result.record(await viewModel.save(
                vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails()))
        }
        // entry_saved lands on acceptance; first_entry_added must still be gated — the ordering is the test.
        let gated: [AnalyticsEvent] = [.entrySaved(entryType: .maintenance, isEdit: false)]
        let completedWithGateClosed = await eventually {
            result.value != nil && gate.isStarted && gate.isClosed && analytics.events == gated
        }
        gate.resume()
        let didDrain = await eventually { gate.isFinished && result.value != nil }
        #expect(completedWithGateClosed && result.value == true)
        #expect(didDrain && !viewModel.isSaving && viewModel.error == nil)
        let observed = await eventually { analytics.events == gated + [.firstEntryAdded(entryType: .maintenance)] }
        #expect(observed)
    }
    @Test func firstEntrySave_emitsTypedEventWithSchemaVersion() async {
        let vehicle = testVehicle(), analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let viewModel = EntryFormViewModel(entryService: EntryService(testEntries: []),
            vehicleService: hermeticVehicleService(vehicles: [vehicle]),
            syncService: makeSyncService(), analytics: analytics, userID: { "user" })
        viewModel.odometerReading = "12100"
        let saved = await viewModel.save(vehicle: vehicle, entryType: .fuel, details: fuelDetails())
        let observed = await eventually { analytics.events.count == 2 }
        #expect(saved && observed)
        #expect(analytics.events.map(\.definition) == [
            AnalyticsEventDefinition(name: "entry_saved", parameters: [.entryType(.fuel), .isEdit(false)]),
            AnalyticsEventDefinition(name: "first_entry_added", parameters: [.entryType(.fuel)])])
    }
    @Test func firstEntrySave_doesNotDuplicateAcrossVehiclesInTheSameAccount() async {
        let first = testVehicle()
        var second = first
        second.id = "vehicle-b"
        second.nickname = "Second car"
        let analytics = AnalyticsSpy(), gate = AsyncGate()
        analytics.setEnabled(true)
        let viewModel = firstEntryModel(
            vehicles: [first, second], entries: [existingEntry(for: first)], tracker: analytics, gate: gate)
        let saved = await viewModel.save(vehicle: second, entryType: .maintenance, details: maintenanceDetails())
        let didDrain = await releaseAndDrain(gate)
        // entry_saved fires per save; the point here is only that first_entry_added does NOT.
        #expect(saved && didDrain && analytics.events == [.entrySaved(entryType: .maintenance, isEdit: false)])
    }
    @Test func optOut_dropsFirstEntryEventAfterSuccessfulSave() async {
        let vehicle = testVehicle(), analytics = AnalyticsSpy(), gate = AsyncGate()
        analytics.setEnabled(false)
        let viewModel = firstEntryModel(vehicles: [vehicle], tracker: analytics, gate: gate)
        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())
        let didDrain = await releaseAndDrain(gate)
        #expect(saved && didDrain && analytics.events.isEmpty && analytics.enabledValues.contains(false))
    }
}
private extension EntryFormViewModelTests {
    func model(
        entryService: EntryService, vehicleService: VehicleService, syncService: SyncService? = nil,
        analytics: any AnalyticsTracking = NoopAnalyticsService(),
        firstEntryFollowUp: @escaping FirstEntryFollowUp = { _ in },
        userID: @escaping () -> String? = { "user" }
    ) -> EntryFormViewModel { let viewModel = EntryFormViewModel(
            entryService: entryService, vehicleService: vehicleService, syncService: syncService ?? makeSyncService(),
            analytics: analytics, firstEntryFollowUp: firstEntryFollowUp, userID: userID)
        viewModel.odometerReading = "12100"
        return viewModel }
    func firstEntryModel(vehicles: [Vehicle], entries: [FirestoreEntry] = [], tracker: any AnalyticsTracking,
                         gate: AsyncGate) -> EntryFormViewModel { model(
            entryService: EntryService(testEntries: entries),
            vehicleService: hermeticVehicleService(vehicles: vehicles),
            analytics: tracker, firstEntryFollowUp: { operation in await gate.run(operation) }) }
    func releaseAndDrain(_ gate: AsyncGate) async -> Bool {
        let didStart = await eventually { gate.isStarted }
        gate.resume()
        let didFinish = await eventually { gate.isFinished }
        return didStart && didFinish }
    func makeValidationViewModel() -> EntryFormViewModel { model(
            entryService: EntryService(testEntries: []), vehicleService: hermeticVehicleService(vehicles: []),
            userID: { "test-user" }) }
    func makeSyncService() -> SyncService { SyncService(monitorFactory: { SyncPassiveMonitor() }) }
    func hermeticVehicleService(vehicles: [Vehicle]) -> VehicleService { VehicleService(
        testVehicles: vehicles, purchaseService: PurchaseService(testIsPro: false)) }
    func testVehicle() -> Vehicle { Vehicle(
            id: "vehicle", userId: "user", nickname: "Test car", make: "Garage", model: "Test",
            year: 2026, currentOdometer: 10_000) }
    func existingEntry(for vehicle: Vehicle) -> FirestoreEntry { FirestoreEntry(
            id: "existing-entry", vehicleId: vehicle.id, userId: "user", entryType: .maintenance,
            entryDate: .now, odometerReading: 10_100, cost: nil, isDiy: nil, shopName: nil,
            notes: nil, attachmentPaths: [], isResolved: nil, details: [:], createdAt: nil, updatedAt: nil) }
    func maintenanceDetails() -> MaintenanceEntry { MaintenanceEntry(
            item: .airFilter, otherLabel: nil, nextDueMileage: nil, nextDueDate: nil,
            symptomDescription: nil, resolutionDescription: nil, status: .resolved) }
    func oilDetails() -> OilChangeEntry { OilChangeEntry(
        oilBrand: "Mobil 1", oilGrade: "0W-40", quantityQuarts: 8.5, filterBrand: "Mann") }
    func fuelDetails() -> FuelEntry { FuelEntry(
            gallons: 12.5, pricePerGallon: 5.22, totalCost: 65.25, stationName: "Garage Fuel",
            fuelGrade: .premium91, calculatedMPG: 20.1) } }
@MainActor private final class HoldingBatchSubmitter: AtomicBatchSubmitting {
    private(set) var writes: [AtomicBatchWrite] = []
    private var completion: (@Sendable (String?) -> Void)?; var completionWasRetained: Bool { completion != nil }
    func submitBatch(_ writes: [AtomicBatchWrite], completion: @escaping @Sendable (String?) -> Void) throws {
        self.writes = writes; self.completion = completion }
}
@MainActor private final class SaveAttemptRecorder { private(set) var ids: [String] = []; private var shouldFail = true
    func failFirstAttempt(for id: String) -> Error? { ids.append(id)
        defer { shouldFail = false }
        return shouldFail ? ViewModelTestError.persistence : nil } }
@MainActor private func eventually(attempts: Int = 100, _ condition: () -> Bool) async -> Bool {
    for _ in 0..<attempts where !condition() { try? await Task.sleep(nanoseconds: 1_000_000) }
    return condition() }
@MainActor private final class SaveResult { private(set) var value: Bool?
    func record(_ value: Bool) { self.value = value } }
@MainActor private final class AsyncGate { private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isStarted = false, isFinished = false, isReleased = false
    var isClosed: Bool { !isReleased }
    func wait() async {
        isStarted = true; guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            if isReleased { continuation.resume() } else { self.continuation = continuation }
        }
    }
    func run(_ operation: @MainActor @Sendable () async -> Void) async {
        await wait()
        await operation(); isFinished = true }
    func resume() { isReleased = true; continuation?.resume(); continuation = nil } }
private enum ViewModelTestError: LocalizedError { case persistence
    var errorDescription: String? { "temporary local persistence failure" } }
