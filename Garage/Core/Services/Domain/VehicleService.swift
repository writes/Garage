@preconcurrency import FirebaseFirestore
import Foundation
import Observation
struct VehicleSnapshotEnvelope: Sendable, Equatable {
    let vehicles: [Vehicle]; let isFromCache: Bool
    let hasPendingWrites: Bool; let decodeFailureDocumentIDs: [String]
    init(vehicles: [Vehicle], isFromCache: Bool, hasPendingWrites: Bool, decodeFailureDocumentIDs: [String] = []) {
        self.vehicles = vehicles
        self.isFromCache = isFromCache; self.hasPendingWrites = hasPendingWrites
        self.decodeFailureDocumentIDs = decodeFailureDocumentIDs.sorted()
    }
}
struct VehicleListenerError: Error, Sendable, Equatable, LocalizedError {
    let message: String; var errorDescription: String? { message }
}
enum VehicleListenerEvent: Sendable, Equatable {
    case snapshot(VehicleSnapshotEnvelope), failure(VehicleListenerError), finished
}
protocol VehicleListenerRemoval: AnyObject { func remove() }
@MainActor struct VehicleListenerFactory {
    let register: (String, @escaping @Sendable (VehicleListenerEvent) -> Void) -> any VehicleListenerRemoval
}
/// Stream termination is the only removal path; this locked box makes it idempotent off-actor.
private final class ListenerRemovalBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: (any VehicleListenerRemoval)?
    private var removed = false
    func install(_ handle: any VehicleListenerRemoval) {
        lock.lock()
        if removed { lock.unlock(); handle.remove(); return }
        self.handle = handle; lock.unlock()
    }
    func remove() {
        lock.lock()
        guard !removed else { lock.unlock(); return }
        removed = true; let handle = self.handle
        self.handle = nil; lock.unlock()
        handle?.remove()
    }
}
private final class FirebaseVehicleListenerRemoval: VehicleListenerRemoval {
    private let registration: ListenerRegistration
    init(registration: ListenerRegistration) { self.registration = registration }
    func remove() { registration.remove() }
}
@MainActor
@Observable
final class VehicleService {
    private enum Mode { case live, uiTest }
    typealias VehicleStream = AsyncThrowingStream<VehicleSnapshotEnvelope, Error>
    static let shared = VehicleService()
    static let uiTest = VehicleService(mode: .uiTest)
    private let firestoreProvider: () -> FirestoreService; private let purchaseServiceProvider: () -> PurchaseService
    private let uidProvider: () -> String?; private let listenerFactoryProvider: () -> VehicleListenerFactory
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
#if DEBUG
        testUpdateInterceptor = nil
#endif
    }
#if DEBUG
    init(testVehicles: [Vehicle], purchaseService: PurchaseService, listenerFactory: VehicleListenerFactory? = nil,
         uidProvider: @escaping () -> String? = { "test-user" },
         updateInterceptor: ((Vehicle) async throws -> Void)? = nil) {
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
    }
    init(listenerFactory: VehicleListenerFactory, uidProvider: @escaping () -> String? = { "test-user" }) {
        mode = .live
        firestoreProvider = { fatalError("Injected listener factory must not resolve Firestore") }
        purchaseServiceProvider = { .uiTest }
        self.uidProvider = uidProvider
        listenerFactoryProvider = { listenerFactory }
        testUpdateInterceptor = nil
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
            let existingVehicleCount = DemoSessionStore.shared.vehicles().count
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
        let snapshot = try await collection.whereField("userId", isEqualTo: uid).limit(to: 5).getDocuments()
        try Self.validateVehicleLimit(existingVehicleCount: snapshot.documents.count, isPro: purchaseService.isPro)
        var vehicle = vehicle
        vehicle.userId = uid
        let document = firestore.db.collection(FirestorePaths.vehicles).document(vehicle.id)
        try await document.setData(firestore.encode(vehicle))
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
        if AppRuntime.isLocalDemoMode { return DemoSessionStore.shared.vehicles() }
#endif
        guard mode == .live else { return SeedData.vehicles }
        guard let uid = uidProvider() else { throw AppError.auth("Not authenticated") }
        let firestore = firestoreProvider()
        let query = firestore.db.collection(FirestorePaths.vehicles).whereField("userId", isEqualTo: uid)
        let snapshot = try await query.order(by: "displayOrder").limit(to: 20).getDocuments()
        return try snapshot.documents.map { try firestore.decode(Vehicle.self, from: $0.data()) }
    }
    func listenToVehicles() -> VehicleStream {
        if let testVehicles {
            return Self.singleVehicleStream(testVehicles.values.sorted { $0.displayOrder < $1.displayOrder })
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode { return Self.singleVehicleStream(DemoSessionStore.shared.vehicles()) }
#endif
        guard mode == .live else { return Self.singleVehicleStream(SeedData.vehicles) }
        guard let uid = uidProvider() else {
            return Self.failedVehicleStream(VehicleListenerError(message: "Not authenticated"))
        }
        return listenToVehicles(uid: uid)
    }
    func listenToVehicles(uid: String) -> VehicleStream {
        if let testVehicles {
            return Self.singleVehicleStream(testVehicles.values.sorted { $0.displayOrder < $1.displayOrder })
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode { return Self.singleVehicleStream(DemoSessionStore.shared.vehicles()) }
#endif
        guard mode == .live else { return Self.singleVehicleStream(SeedData.vehicles) }
        return Self.liveVehicleStream(uid: uid, factory: listenerFactoryProvider())
    }
    private static func singleVehicleStream(_ vehicles: [Vehicle]) -> VehicleStream {
        AsyncThrowingStream { continuation in
            continuation.yield(VehicleSnapshotEnvelope(vehicles: vehicles, isFromCache: false, hasPendingWrites: false))
            continuation.finish()
        }
    }
    private static func failedVehicleStream(_ error: VehicleListenerError) -> VehicleStream {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
    private static func liveVehicleStream(uid: String, factory: VehicleListenerFactory) -> VehicleStream {
        AsyncThrowingStream { continuation in
            let removalBox = ListenerRemovalBox()
            continuation.onTermination = { _ in removalBox.remove() }
            let handle = factory.register(uid) { event in
                switch event {
                case .snapshot(let envelope): continuation.yield(envelope)
                case .failure(let error): continuation.finish(throwing: error)
                case .finished: continuation.finish()
                }
            }
            removalBox.install(handle)
        }
    }
    private static func makeFirebaseListenerFactory(firestore: FirestoreService) -> VehicleListenerFactory {
        VehicleListenerFactory { uid, handler in
            let query = firestore.db.collection(FirestorePaths.vehicles)
                .whereField("userId", isEqualTo: uid)
                .order(by: "displayOrder")
                .limit(to: 20)
            let registration = query.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                let event: VehicleListenerEvent
                if let error {
                    event = .failure(VehicleListenerError(message: error.localizedDescription))
                } else if let snapshot {
                    var vehicles: [Vehicle] = []
                    var failedIDs: [String] = []
                    for document in snapshot.documents {
                        do {
                            vehicles.append(try firestore.decode(Vehicle.self, from: document.data()))
                        } catch {
                            failedIDs.append(document.documentID)
                        }
                    }
                    event = .snapshot(VehicleSnapshotEnvelope(
                        vehicles: vehicles, isFromCache: snapshot.metadata.isFromCache,
                        hasPendingWrites: snapshot.metadata.hasPendingWrites,
                        decodeFailureDocumentIDs: failedIDs
                    ))
                } else {
                    event = .failure(VehicleListenerError(message: "The vehicle listener returned no snapshot."))
                }
                handler(event)
            }
            return FirebaseVehicleListenerRemoval(registration: registration)
        }
    }
    static func validateVehicleLimit(existingVehicleCount: Int, isPro: Bool) throws {
        let maxVehicles = isPro ? Constants.maxProVehicles : Constants.maxFreeVehicles
        guard existingVehicleCount < maxVehicles else { throw AppError.vehicleLimitReached }
    }
}
