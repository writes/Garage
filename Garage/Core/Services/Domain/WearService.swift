import FirebaseFirestore
import Observation

@MainActor
@Observable
final class WearService {
    static let shared = WearService()

    private var firestore: FirestoreService { .shared }

    private init() {}

    func fetchDashboard(vehicleId: String) async throws -> [WearItem] {
        if AppRuntime.isLocalDemoMode {
            return Self.latestDashboardItems(from: SeedData.wearSnapshots(for: vehicleId))
        }

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleWear(vehicleId: vehicleId))
            .order(by: "recordedAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        let snapshots = try snapshot.documents.map { try firestore.decode(WearSnapshot.self, from: $0.data()) }
        return Self.latestDashboardItems(from: snapshots)
    }

    func saveSnapshots(_ snapshots: [WearSnapshot], vehicleId: String) async throws {
        try await apply(
            WearSnapshotFactory.WearWrite(snapshots: snapshots), vehicleId: vehicleId
        )
    }

    /// Writes readings and removes the ones the user cleared, in that order.
    ///
    /// Deletes are best-effort: a snapshot id that was never written is an ordinary case (most
    /// entries record no wear at all), and Firestore treats deleting a missing document as
    /// success, so this needs no existence check. What it must not do is fail the save.
    func apply(_ write: WearSnapshotFactory.WearWrite, vehicleId: String) async throws {
        guard !AppRuntime.isLocalDemoMode else { return }
        guard !write.snapshots.isEmpty || !write.clearedIDs.isEmpty else { return }

        let collection = firestore.db.collection(FirestorePaths.vehicleWear(vehicleId: vehicleId))
        for snapshot in write.snapshots {
            try await collection.document(snapshot.id).setData(firestore.encode(snapshot))
        }
        for id in write.clearedIDs {
            try await collection.document(id).delete()
        }
        VehicleDataRevisionStore.shared.bump(vehicleId: vehicleId)
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
