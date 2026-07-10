import FirebaseFirestore
import Observation

@MainActor
@Observable
final class PartsService {
    static let shared = PartsService()

    private var firestore: FirestoreService { .shared }

    private init() {}

    func save(_ part: SparePart) async throws {
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(part)
            return
        }

        let reference = firestore.db.collection(FirestorePaths.vehicleParts(vehicleId: part.vehicleId))
            .document(part.id)
        try await reference.setData(firestore.encode(part), merge: true)
    }

    func fetchParts(vehicleId: String) async throws -> [SparePart] {
        if AppRuntime.isLocalDemoMode {
            return DemoSessionStore.shared.parts(for: vehicleId)
        }

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleParts(vehicleId: vehicleId))
            .limit(to: 100)
            .getDocuments()

        return try snapshot.documents.map { try firestore.decode(SparePart.self, from: $0.data()) }
    }
}
