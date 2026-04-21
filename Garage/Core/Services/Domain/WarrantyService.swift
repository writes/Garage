import FirebaseFirestore
import Observation

@MainActor
@Observable
final class WarrantyService {
    static let shared = WarrantyService()

    private var firestore: FirestoreService { .shared }

    private init() {}

    func saveWarranty(_ warranty: Warranty) async throws {
        guard !AppRuntime.isLocalDemoMode else { return }

        let reference = firestore.db.collection(FirestorePaths.vehicleWarranties(vehicleId: warranty.vehicleId))
            .document(warranty.id)
        try await reference.setData(firestore.encode(warranty), merge: true)
    }

    func fetchWarranties(vehicleId: String) async throws -> [Warranty] {
        if AppRuntime.isLocalDemoMode {
            return SeedData.warranties(for: vehicleId)
        }

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleWarranties(vehicleId: vehicleId))
            .limit(to: 20)
            .getDocuments()

        return try snapshot.documents.map { try firestore.decode(Warranty.self, from: $0.data()) }
    }

    func saveRecall(_ recall: Recall) async throws {
        guard !AppRuntime.isLocalDemoMode else { return }

        let reference = firestore.db.collection(FirestorePaths.vehicleRecalls(vehicleId: recall.vehicleId))
            .document(recall.id)
        try await reference.setData(firestore.encode(recall), merge: true)
    }

    func fetchRecalls(vehicleId: String) async throws -> [Recall] {
        if AppRuntime.isLocalDemoMode {
            return SeedData.recalls(for: vehicleId)
        }

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleRecalls(vehicleId: vehicleId))
            .limit(to: 50)
            .getDocuments()

        return try snapshot.documents.map { try firestore.decode(Recall.self, from: $0.data()) }
    }
}
