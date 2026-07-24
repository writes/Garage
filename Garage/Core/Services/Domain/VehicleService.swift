@preconcurrency import FirebaseFirestore
import Foundation
import Observation
@MainActor
@Observable
final class VehicleService {
    // `Mode`/`firestoreProvider`/`uidProvider`/`purgeInvoker`/`mode`/`testVehicles`: `internal`
    // (not `private`) because VehicleService+Deletion.swift's deleteVehicle/retryPendingPurges
    // need them — same precedent as EntryService's liveDependenciesProvider/isLocalDemoMode.
    enum Mode { case live, uiTest }
    typealias VehicleStream = AsyncThrowingStream<VehicleSnapshotEnvelope, Error>
    static let shared = VehicleService()
    static let uiTest = VehicleService(mode: .uiTest)
    let firestoreProvider: () -> FirestoreService; private let purchaseServiceProvider: () -> PurchaseService
    let uidProvider: () -> String?; private let listenerFactoryProvider: () -> VehicleListenerFactory
    let purgeInvoker: (String) async throws -> Void
    /// Best-effort cancellation of a deleted vehicle's local reminder notifications — see
    /// VehicleService+Deletion.swift's deleteVehicle. Mirrors purgeInvoker's seam style.
    let reminderNotificationCancelInvoker: (String) async -> Void
    let mode: Mode; var testVehicles: [String: Vehicle]?
#if DEBUG
    private let testUpdateInterceptor: ((Vehicle) async throws -> Void)?
#endif
    private init(
        mode: Mode = .live,
        firestoreProvider: (() -> FirestoreService)? = nil,
        purchaseServiceProvider: (() -> PurchaseService)? = nil,
        uidProvider: (() -> String?)? = nil,
        listenerFactoryProvider: (() -> VehicleListenerFactory)? = nil
    ) {
        self.mode = mode
        let resolvedFirestoreProvider = firestoreProvider ?? { FirestoreService.shared }
        self.firestoreProvider = resolvedFirestoreProvider
        let resolvedPurchaseServiceProvider = purchaseServiceProvider ?? {
            AppRuntime.isLocalDemoMode ? PurchaseService.uiTest : PurchaseService.shared
        }
        self.purchaseServiceProvider = resolvedPurchaseServiceProvider
        self.uidProvider = uidProvider ?? { AuthService.shared.uid }
        self.listenerFactoryProvider = listenerFactoryProvider ?? {
            Self.makeFirebaseListenerFactory(firestore: resolvedFirestoreProvider())
        }
        // Resolved inside the closure so constructing the service never touches Functions
        // pre-FirebaseApp.configure (the deleteAccount launch-crash lesson).
        purgeInvoker = { try await VehiclePurgeService.shared.purgeVehicle(id: $0) }
        // Same reasoning: resolved inside the closure, never at construction time. `[mode]`
        // (not a call-site `guard`, since VehicleService+Deletion.swift calls this from every
        // branch of deleteVehicle so it's reachable hermetically too): must independently no-op
        // for `.uiTest` mode — the `VehicleService.uiTest` singleton GarageApp's non-production
        // bootstrap modes use — so a real XCUITest run never touches ReminderService/Firestore,
        // mirroring `guard mode == .live` everywhere else in this file.
        reminderNotificationCancelInvoker = { [mode] vehicleId in
            guard mode == .live else { return }
            guard let reminders = try? await ReminderService.shared.fetchAll(vehicleId: vehicleId) else { return }
            for reminder in reminders { ReminderNotificationCoordinator.shared.cancel(id: reminder.id) }
        }
#if DEBUG
        testUpdateInterceptor = nil
#endif
    }
#if DEBUG
    init(testVehicles: [Vehicle], purchaseService: PurchaseService, listenerFactory: VehicleListenerFactory? = nil,
         uidProvider: @escaping () -> String? = { "test-user" },
         updateInterceptor: ((Vehicle) async throws -> Void)? = nil,
         purgeInvoker: ((String) async throws -> Void)? = nil,
         reminderNotificationCancelInvoker: ((String) async -> Void)? = nil) {
        mode = .uiTest
        firestoreProvider = { fatalError("Hermetic VehicleService must not resolve Firestore") }
        purchaseServiceProvider = { purchaseService }
        self.uidProvider = uidProvider
        listenerFactoryProvider = {
            guard let listenerFactory else { fatalError("Hermetic VehicleService must not construct a live listener") }
            return listenerFactory
        }
        self.testVehicles = Dictionary(uniqueKeysWithValues: testVehicles.map { ($0.id, $0) })
        testUpdateInterceptor = updateInterceptor
        self.purgeInvoker = purgeInvoker ?? { _ in }
        self.reminderNotificationCancelInvoker = reminderNotificationCancelInvoker ?? { _ in }
    }
    init(listenerFactory: VehicleListenerFactory, uidProvider: @escaping () -> String? = { "test-user" }) {
        mode = .live
        firestoreProvider = { fatalError("Injected listener factory must not resolve Firestore") }
        purchaseServiceProvider = { .uiTest }
        self.uidProvider = uidProvider
        listenerFactoryProvider = { listenerFactory }
        testUpdateInterceptor = nil
        purgeInvoker = { _ in }
        reminderNotificationCancelInvoker = { _ in }
    }
#endif
    private var purchaseService: PurchaseService { purchaseServiceProvider() }
    func createVehicle(_ vehicle: Vehicle) async throws -> Vehicle {
        if var testVehicles {
            try Self.validateVehicleLimit(existingVehicleCount: testVehicles.count, isPro: purchaseService.isPro)
            testVehicles[vehicle.id] = vehicle
            self.testVehicles = testVehicles
            return vehicle
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            let existingVehicleCount = DemoSessionStore.shared.vehicles().filter { $0.deletedAt == nil }.count
            try Self.validateVehicleLimit(existingVehicleCount: existingVehicleCount, isPro: purchaseService.isPro)
            var vehicle = vehicle
            vehicle.userId = AppRuntime.demoUserId
            vehicle.displayOrder = DemoSessionStore.shared.vehicles().count
            DemoSessionStore.shared.save(vehicle)
            return vehicle
        }
#endif
        guard mode == .live else { return vehicle }
        guard let uid = uidProvider() else { throw AppError.auth("Not authenticated") }
        let firestore = firestoreProvider()
        let collection = firestore.db.collection(FirestorePaths.vehicles)
        // UX precheck only — the rules enforce the cap server-side (RULES-1). Bound is cap+1,
        // not a magic 5, so an at-cap account stays detectable if the caps ever grow (#15).
        let snapshot = try await collection.whereField("userId", isEqualTo: uid)
            .limit(to: Constants.maxProVehicles + 1).getDocuments()
        // A tombstoned doc still holds a server counter slot until its purge lands; heal it NOW
        // so the counted create below isn't denied by a stale counter right after a deletion.
        for document in snapshot.documents where document.data()["deletedAt"] != nil {
            try? await purgeInvoker(document.documentID)
        }
        let existingCount = snapshot.documents.filter { $0.data()["deletedAt"] == nil }.count
        try Self.validateVehicleLimit(existingVehicleCount: existingCount, isPro: purchaseService.isPro)
        var vehicle = vehicle
        vehicle.userId = uid
        try await commitCountedCreate(vehicle, uid: uid, firestore: firestore)
        return vehicle
    }
    func updateVehicle(_ vehicle: Vehicle) async throws {
        if var testVehicles {
#if DEBUG
            if let testUpdateInterceptor { try await testUpdateInterceptor(vehicle) }
#endif
            testVehicles[vehicle.id] = vehicle
            self.testVehicles = testVehicles
            return
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode { DemoSessionStore.shared.save(vehicle); return }
#endif
        guard mode == .live else { return }
        let firestore = firestoreProvider()
        let document = firestore.db.collection(FirestorePaths.vehicles).document(vehicle.id)
        try await document.setData(firestore.encode(vehicle), merge: true)
    }
    func fetchVehicles() async throws -> [Vehicle] {
        if let testVehicles { return testVehicles.values.sorted { $0.displayOrder < $1.displayOrder } }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return DemoSessionStore.shared.vehicles().filter { $0.deletedAt == nil }
        }
#endif
        guard mode == .live else { return SeedData.vehicles }
        guard let uid = uidProvider() else { throw AppError.auth("Not authenticated") }
        let firestore = firestoreProvider()
        let query = firestore.db.collection(FirestorePaths.vehicles).whereField("userId", isEqualTo: uid)
        let snapshot = try await query.order(by: "displayOrder").limit(to: 20).getDocuments()
        // Tolerant decode (#19): one corrupt doc must not blank the garage; failures are non-fatals.
        var vehicles: [Vehicle] = []
        for document in snapshot.documents {
            do {
                vehicles.append(try firestore.decode(Vehicle.self, from: document.data()))
            } catch {
                AppLogger.shared.error(
                    "Vehicle decode failed for \(document.documentID): \(error.localizedDescription)"
                )
                CrashReporter.shared.record(error, context: "vehicle-decode")
            }
        }
        return vehicles.filter { $0.deletedAt == nil }
    }

    func listenToVehicles() -> VehicleStream {
        if let fixtureStream { return fixtureStream }
        guard let uid = uidProvider() else {
            return Self.failedVehicleStream(VehicleListenerError(message: "Not authenticated"))
        }
        return Self.liveVehicleStream(uid: uid, factory: listenerFactoryProvider())
    }
    func listenToVehicles(uid: String) -> VehicleStream {
        if let fixtureStream { return fixtureStream }
        return Self.liveVehicleStream(uid: uid, factory: listenerFactoryProvider())
    }
    /// Non-live stream sources (hermetic tests, local demo, seed data); nil in live mode.
    private var fixtureStream: VehicleStream? {
        if let testVehicles {
            return Self.singleVehicleStream(testVehicles.values.sorted { $0.displayOrder < $1.displayOrder })
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return Self.singleVehicleStream(DemoSessionStore.shared.vehicles().filter { $0.deletedAt == nil })
        }
#endif
        guard mode == .live else { return Self.singleVehicleStream(SeedData.vehicles) }
        return nil
    }
    static func validateVehicleLimit(existingVehicleCount: Int, isPro: Bool) throws {
        let maxVehicles = isPro ? Constants.maxProVehicles : Constants.maxFreeVehicles
        guard existingVehicleCount < maxVehicles else { throw AppError.vehicleLimitReached }
    }
}

// Deletion (RULES-1 soft delete + trusted purge): VehicleService+Deletion.swift — split out to
// stay under the file cap; needs `mode`/`testVehicles`/`firestoreProvider`/`purgeInvoker`/
// `reminderNotificationCancelInvoker` above, hence their `internal` (not `private`) access.
