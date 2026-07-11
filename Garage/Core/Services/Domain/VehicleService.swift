@preconcurrency import FirebaseFirestore
import Observation

@MainActor
@Observable
final class VehicleService {
    private enum Mode {
        case live
        case uiTest
    }

    static let shared = VehicleService()
    static let uiTest = VehicleService(mode: .uiTest)

    private let firestore: FirestoreService?
    private let purchaseService: PurchaseService
    private let mode: Mode
    private var testVehicles: [String: Vehicle]?

    private init(
        mode: Mode = .live,
        firestore: FirestoreService? = nil,
        purchaseService: PurchaseService? = nil
    ) {
        self.mode = mode
#if DEBUG
        self.firestore = firestore ?? (mode == .live && !AppRuntime.isLocalDemoMode ? .shared : nil)
        self.purchaseService = purchaseService ?? (mode == .live && !AppRuntime.isLocalDemoMode ? .shared : .uiTest)
#else
        self.firestore = firestore ?? (mode == .live ? .shared : nil)
        self.purchaseService = purchaseService ?? (mode == .live ? .shared : .uiTest)
#endif
    }

#if DEBUG
    init(testVehicles: [Vehicle], purchaseService: PurchaseService) {
        mode = .uiTest
        firestore = nil
        self.purchaseService = purchaseService
        self.testVehicles = Dictionary(uniqueKeysWithValues: testVehicles.map { ($0.id, $0) })
    }
#endif

    func createVehicle(_ vehicle: Vehicle) async throws -> Vehicle {
        if var testVehicles {
            try Self.validateVehicleLimit(existingVehicleCount: testVehicles.count, isPro: purchaseService.isPro)
            testVehicles[vehicle.id] = vehicle
            self.testVehicles = testVehicles
            return vehicle
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            try Self.validateVehicleLimit(
                existingVehicleCount: DemoSessionStore.shared.vehicles().count,
                isPro: purchaseService.isPro
            )
            var demoVehicle = vehicle
            demoVehicle.userId = AppRuntime.demoUserId
            demoVehicle.displayOrder = DemoSessionStore.shared.vehicles().count
            DemoSessionStore.shared.save(demoVehicle)
            return demoVehicle
        }
#endif
        guard mode == .live else { return vehicle }
        guard let uid = AuthService.shared.uid else {
            throw AppError.auth("Not authenticated")
        }
        guard let firestore else {
            throw AppError.database("Firestore unavailable")
        }

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicles)
            .whereField("userId", isEqualTo: uid)
            .limit(to: 5)
            .getDocuments()

        try Self.validateVehicleLimit(
            existingVehicleCount: snapshot.documents.count,
            isPro: purchaseService.isPro
        )

        var newVehicle = vehicle
        newVehicle.userId = uid
        let reference = firestore.db.collection(FirestorePaths.vehicles).document(newVehicle.id)
        try await reference.setData(firestore.encode(newVehicle))
        return newVehicle
    }

    func updateVehicle(_ vehicle: Vehicle) async throws {
        if var testVehicles {
            testVehicles[vehicle.id] = vehicle
            self.testVehicles = testVehicles
            return
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(vehicle)
            return
        }
#endif
        guard mode == .live else { return }
        guard let firestore else {
            throw AppError.database("Firestore unavailable")
        }

        try await firestore.db.collection(FirestorePaths.vehicles)
            .document(vehicle.id)
            .setData(firestore.encode(vehicle), merge: true)
    }

    func fetchVehicles() async throws -> [Vehicle] {
        if let testVehicles {
            return testVehicles.values.sorted { $0.displayOrder < $1.displayOrder }
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return DemoSessionStore.shared.vehicles()
        }
#endif
        guard mode == .live else {
            return SeedData.vehicles
        }
        guard let uid = AuthService.shared.uid else {
            throw AppError.auth("Not authenticated")
        }
        guard let firestore else {
            throw AppError.database("Firestore unavailable")
        }

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicles)
            .whereField("userId", isEqualTo: uid)
            .order(by: "displayOrder")
            .limit(to: 20)
            .getDocuments()

        return try snapshot.documents.map { document in
            try firestore.decode(Vehicle.self, from: document.data())
        }
    }

    func listenToVehicles() -> AsyncThrowingStream<[Vehicle], Error> {
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return Self.singleVehicleStream(DemoSessionStore.shared.vehicles())
        }
#endif
        guard mode == .live else {
            return Self.singleVehicleStream(SeedData.vehicles)
        }
        guard let uid = AuthService.shared.uid else {
            return Self.failedVehicleStream(AppError.auth("Not authenticated"))
        }
        guard let firestore else {
            return Self.failedVehicleStream(AppError.database("Firestore unavailable"))
        }

        return Self.liveVehicleStream(uid: uid, firestore: firestore)
    }

    private static func singleVehicleStream(_ vehicles: [Vehicle]) -> AsyncThrowingStream<[Vehicle], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(vehicles)
            continuation.finish()
        }
    }

    private static func failedVehicleStream(_ error: AppError) -> AsyncThrowingStream<[Vehicle], Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }

    private static func liveVehicleStream(
        uid: String,
        firestore: FirestoreService
    ) -> AsyncThrowingStream<[Vehicle], Error> {
        AsyncThrowingStream { continuation in
            let listener = firestore.db.collection(FirestorePaths.vehicles)
                .whereField("userId", isEqualTo: uid)
                .order(by: "displayOrder")
                .limit(to: 20)
                .addSnapshotListener { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }

                    do {
                        let vehicles = try snapshot?.documents.map {
                            try firestore.decode(Vehicle.self, from: $0.data())
                        } ?? []
                        continuation.yield(vehicles)
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    static func validateVehicleLimit(existingVehicleCount: Int, isPro: Bool) throws {
        guard isPro || existingVehicleCount < Constants.maxFreeVehicles else {
            throw AppError.vehicleLimitReached
        }
    }
}
