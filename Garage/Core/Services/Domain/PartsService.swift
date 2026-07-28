import FirebaseFirestore
import Observation

@MainActor
@Observable
final class PartsService {
    static let shared = PartsService()

    private var firestore: FirestoreService { .shared }

    private init() {}

    func save(_ part: SparePart) async throws {
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(part)
            return
        }
#endif

        let reference = firestore.db.collection(FirestorePaths.vehicleParts(vehicleId: part.vehicleId))
            .document(part.id)
        firestore.writeLocalFirst(try firestore.encode(part), to: reference, context: "spare part")
        VehicleDataRevisionStore.shared.bump(vehicleId: part.vehicleId)
    }

    func fetchParts(vehicleId: String) async throws -> [SparePart] {
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return DemoSessionStore.shared.parts(for: vehicleId)
        }
#endif

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleParts(vehicleId: vehicleId))
            .limit(to: 100)
            .getDocuments()

        return try snapshot.documents.map { try firestore.decode(SparePart.self, from: $0.data()) }
    }
}
