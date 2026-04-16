import FirebaseFirestore
import Observation

@MainActor
@Observable
final class WearService {
    static let shared = WearService()

    private let firestore = FirestoreService.shared

    private init() {}

    func fetchDashboard(vehicleId: String) async throws -> [WearItem] {
        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleWear(vehicleId: vehicleId))
            .order(by: "recordedAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        let snapshots = try snapshot.documents.map { try firestore.decode(WearSnapshot.self, from: $0.data()) }
        return Self.latestDashboardItems(from: snapshots)
    }

    func saveSnapshots(_ snapshots: [WearSnapshot], vehicleId: String) async throws {
        for snapshot in snapshots {
            let reference = firestore.db
                .collection(FirestorePaths.vehicleWear(vehicleId: vehicleId))
                .document(snapshot.id)
            try await reference.setData(firestore.encode(snapshot))
        }
    }

    nonisolated static func latestDashboardItems(from snapshots: [WearSnapshot]) -> [WearItem] {
        let latestByType = Dictionary(grouping: snapshots.sorted(by: { $0.recordedAt > $1.recordedAt }), by: \.wearItem)
            .compactMapValues(\.first)

        return WearItemType.allCases.compactMap { type in
            guard let snapshot = latestByType[type], let percentage = snapshot.valuePct else { return nil }
            return WearItem(type: type, percentage: percentage, rawValue: snapshot.valueRaw)
        }
    }
}
