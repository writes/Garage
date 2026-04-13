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

    private init(
        mode: Mode = .live,
        firestore: FirestoreService? = nil,
        purchaseService: PurchaseService? = nil
    ) {
        self.mode = mode
        self.firestore = firestore ?? (mode == .live ? .shared : nil)
        self.purchaseService = purchaseService ?? (mode == .live ? .shared : .uiTest)
    }

    func createVehicle(_ vehicle: Vehicle) async throws -> Vehicle {
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

        if !purchaseService.isPro && snapshot.documents.count >= Constants.maxFreeVehicles {
            throw AppError.vehicleLimitReached
        }

        var newVehicle = vehicle
        newVehicle.userId = uid
        let reference = firestore.db.collection(FirestorePaths.vehicles).document(newVehicle.id)
        try await reference.setData(firestore.encode(newVehicle))
        return newVehicle
    }

    func updateVehicle(_ vehicle: Vehicle) async throws {
        guard mode == .live else { return }
        guard let firestore else {
            throw AppError.database("Firestore unavailable")
        }

        try await firestore.db.collection(FirestorePaths.vehicles)
            .document(vehicle.id)
            .setData(firestore.encode(vehicle), merge: true)
    }

    func fetchVehicles() async throws -> [Vehicle] {
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
        guard mode == .live else {
            return AsyncThrowingStream { continuation in
                continuation.yield(SeedData.vehicles)
                continuation.finish()
            }
        }
        guard let uid = AuthService.shared.uid else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AppError.auth("Not authenticated"))
            }
        }
        guard let firestore else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AppError.database("Firestore unavailable"))
            }
        }

        let firestoreService = firestore

        return AsyncThrowingStream { continuation in
            let listener = firestoreService.db.collection(FirestorePaths.vehicles)
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
                            try firestoreService.decode(Vehicle.self, from: $0.data())
                        } ?? []
                        continuation.yield(vehicles)
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            continuation.onTermination = { _ in listener.remove() }
        }
    }
}
