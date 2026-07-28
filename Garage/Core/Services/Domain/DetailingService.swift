import FirebaseFirestore
import Observation

@MainActor
@Observable
final class DetailingService {
    static let shared = DetailingService()

    private var firestore: FirestoreService { .shared }

    private init() {}

    func save(_ record: DetailingRecord) async throws {
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(record)
            return
        }
#endif

        let reference = firestore.db.collection(FirestorePaths.vehicleDetailing(vehicleId: record.vehicleId))
            .document(record.id)
        firestore.writeLocalFirst(try firestore.encode(record), to: reference, context: "detailing record")
        VehicleDataRevisionStore.shared.bump(vehicleId: record.vehicleId)
    }

    func fetchRecords(vehicleId: String) async throws -> [DetailingRecord] {
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return DemoSessionStore.shared.detailingRecords(for: vehicleId)
        }
#endif

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleDetailing(vehicleId: vehicleId))
            .limit(to: 100)
            .getDocuments()

        return try snapshot.documents.map { try firestore.decode(DetailingRecord.self, from: $0.data()) }
    }
}
