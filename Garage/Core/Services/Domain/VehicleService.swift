@preconcurrency import FirebaseFirestore
import Foundation
import Observation
@MainActor
@Observable
final class VehicleService {
    private enum Mode { case live, uiTest }
    typealias VehicleStream = AsyncThrowingStream<VehicleSnapshotEnvelope, Error>
    static let shared = VehicleService()
    static let uiTest = VehicleService(mode: .uiTest)
    private let firestoreProvider: () -> FirestoreService; private let purchaseServiceProvider: () -> PurchaseService
    private let uidProvider: () -> String?; private let listenerFactoryProvider: () -> VehicleListenerFactory
    private let purgeInvoker: (String) async throws -> Void
    private let mode: Mode; private var testVehicles: [String: Vehicle]?
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
#if DEBUG
        testUpdateInterceptor = nil
#endif
    }
#if DEBUG
    init(testVehicles: [Vehicle], purchaseService: PurchaseService, listenerFactory: VehicleListenerFactory? = nil,
         uidProvider: @escaping () -> String? = { "test-user" },
         updateInterceptor: ((Vehicle) async throws -> Void)? = nil,
         purgeInvoker: ((String) async throws -> Void)? = nil) {
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
    }
    init(listenerFactory: VehicleListenerFactory, uidProvider: @escaping () -> String? = { "test-user" }) {
        mode = .live
        firestoreProvider = { fatalError("Injected listener factory must not resolve Firestore") }
        purchaseServiceProvider = { .uiTest }
        self.uidProvider = uidProvider
        listenerFactoryProvider = { listenerFactory }
        testUpdateInterceptor = nil
        purgeInvoker = { _ in }
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

// MARK: - Deletion (RULES-1 soft delete + trusted purge)

extension VehicleService {
    /// Tombstone first (client timestamp, fire-and-forget: lands in the local cache immediately
    /// and decodes as a real Date — a pending serverTimestamp reads as nil and would dodge the
    /// filter), then the purge CF runs detached. Failed purges self-heal via retryPendingPurges().
    func deleteVehicle(_ vehicle: Vehicle) async throws {
        if var testVehicles {
            testVehicles[vehicle.id] = nil
            self.testVehicles = testVehicles
            return
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            var tombstoned = vehicle
            tombstoned.deletedAt = Date.now
            DemoSessionStore.shared.save(tombstoned)
            return
        }
#endif
        guard mode == .live else { return }
        let firestore = firestoreProvider()
        let document = firestore.db.collection(FirestorePaths.vehicles).document(vehicle.id)
        writeTombstone(on: document)
        Task { [purgeInvoker] in
            do {
                try await purgeInvoker(vehicle.id)
            } catch {
                // The tombstone already hides the vehicle; the purge (subcollections + counter
                // decrement) converges on the next sweep. Not surfaced by design.
                AppLogger.shared.error("Vehicle purge failed for \(vehicle.id): \(error.localizedDescription)")
                CrashReporter.shared.record(error, context: "vehicle-purge")
            }
        }
    }

    /// Non-async on purpose: Swift 6 forbids the completion-handler overload inside async
    /// contexts, and the async variant is ack-gated (it would suspend forever offline).
    private func writeTombstone(on document: DocumentReference) {
        document.setData(["deletedAt": Timestamp(date: .now)], merge: true) { error in
            if let error {
                AppLogger.shared.error("Vehicle tombstone rejected: \(error.localizedDescription)")
            }
        }
    }

    /// Best-effort self-heal: re-purges any still-tombstoned vehicle (e.g. an offline delete).
    func retryPendingPurges() async {
        guard mode == .live, testVehicles == nil, !AppRuntime.isLocalDemoMode,
              let uid = uidProvider() else { return }
        do {
            let firestore = firestoreProvider()
            let query = firestore.db.collection(FirestorePaths.vehicles).whereField("userId", isEqualTo: uid)
            let snapshot = try await query.limit(to: 20).getDocuments()
            for document in snapshot.documents where document.data()["deletedAt"] != nil {
                do {
                    try await purgeInvoker(document.documentID)
                } catch {
                    AppLogger.shared.error(
                        "Vehicle purge retry failed for \(document.documentID): \(error.localizedDescription)"
                    )
                }
            }
        } catch {
            AppLogger.shared.error("Vehicle purge sweep failed: \(error.localizedDescription)")
        }
    }
}
