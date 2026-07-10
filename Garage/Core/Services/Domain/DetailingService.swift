import FirebaseFirestore
import Observation

@MainActor
@Observable
final class DetailingService {
    static let shared = DetailingService()

    private var firestore: FirestoreService { .shared }

    private init() {}

    func save(_ record: DetailingRecord) async throws {
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(record)
            return
        }

        let reference = firestore.db.collection(FirestorePaths.vehicleDetailing(vehicleId: record.vehicleId))
            .document(record.id)
        try await reference.setData(firestore.encode(record), merge: true)
    }

    func fetchRecords(vehicleId: String) async throws -> [DetailingRecord] {
        if AppRuntime.isLocalDemoMode {
            return DemoSessionStore.shared.detailingRecords(for: vehicleId)
        }

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleDetailing(vehicleId: vehicleId))
            .limit(to: 100)
            .getDocuments()

        return try snapshot.documents.map { try firestore.decode(DetailingRecord.self, from: $0.data()) }
    }
}
