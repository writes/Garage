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

    func saveSnapshots(_ snapshots: [WearSnapshot], vehicleId: String) throws {
        try apply(
            WearSnapshotFactory.WearWrite(snapshots: snapshots), vehicleId: vehicleId
        )
    }

    /// Writes readings and removes the ones the user cleared, in that order.
    ///
    /// Deletes are best-effort: a snapshot id that was never written is an ordinary case (most
    /// entries record no wear at all), and Firestore treats deleting a missing document as
    /// success, so this needs no existence check. What it must not do is fail the save.
    func apply(_ write: WearSnapshotFactory.WearWrite, vehicleId: String) throws {
        guard !AppRuntime.isLocalDemoMode else { return }
        guard !write.snapshots.isEmpty || !write.clearedIDs.isEmpty else { return }

        let collection = firestore.db.collection(FirestorePaths.vehicleWear(vehicleId: vehicleId))
        // NOT `try await setData(...)`. Firestore resolves the awaited form only on SERVER
        // acknowledgement, so offline it never resumes — and offline is where people log service:
        // garages, parking structures, rural roads. The non-awaiting form persists locally at once
        // and syncs when the device reconnects, which is the whole point of Firestore's offline
        // cache. The entry batch already works this way (`batch.commit { }` with a callback).
        // This method is deliberately NOT async. Firestore ships both `setData(_:completion:)`
        // (persists locally, returns now) and `setData(_:) async throws` (resolves only on SERVER
        // acknowledgement, so offline it never resumes). Inside an async function Swift picks the
        // latter, and Swift 6 then refuses the callback form outright — so the only way to get the
        // offline-safe write is for this function not to be async. It never awaited anything
        // meaningful anyway. The completion keeps a real sync failure visible in the log.
        for snapshot in write.snapshots {
            collection.document(snapshot.id).setData(try firestore.encode(snapshot)) { error in
                if let error {
                    AppLogger.shared.error("Wear snapshot sync failed: \(error.localizedDescription)")
                }
            }
        }
        for id in write.clearedIDs {
            collection.document(id).delete { error in
                if let error {
                    AppLogger.shared.error("Wear snapshot clear failed: \(error.localizedDescription)")
                }
            }
        }
        VehicleDataRevisionStore.shared.bump(vehicleId: vehicleId)
    }

    /// Removes snapshots produced by an entry that has been deleted. Fail-soft: a stale wear bar
    /// is a smaller harm than a delete that appears to fail, and Firestore treats deleting a
    /// missing document as success, so no existence check is needed.
    func deleteSnapshots(ids: [String], vehicleId: String) {
        guard !ids.isEmpty, !AppRuntime.isLocalDemoMode else { return }
        // See `apply` — the non-awaiting form so an offline delete cannot hang its caller.
        let collection = firestore.db.collection(FirestorePaths.vehicleWear(vehicleId: vehicleId))
        for id in ids {
            collection.document(id).delete { error in
                if let error {
                    AppLogger.shared.error("Wear snapshot delete failed: \(error.localizedDescription)")
                }
            }
        }
        VehicleDataRevisionStore.shared.bump(vehicleId: vehicleId)
    }

    /// Collapses the history to one row per item — and, unlike before, keeps the RATE it implies.
    /// The fetch has always pulled fifty snapshots and this discarded every one but the newest per
    /// type, throwing away the only thing in the collection the owner cannot read off a bar.
    nonisolated static func latestDashboardItems(from snapshots: [WearSnapshot]) -> [WearItem] {
        let latestByType = Dictionary(grouping: snapshots.sorted(by: { $0.recordedAt > $1.recordedAt }), by: \.wearItem)
            .compactMapValues(\.first)

        return WearItemType.allCases.compactMap { type in
            guard let snapshot = latestByType[type], let percentage = snapshot.valuePct else { return nil }
            return WearItem(
                type: type,
                percentage: percentage,
                rawValue: snapshot.valueRaw,
                // Nil far more often than not — every guard in WearProjection is a case where the
                // honest answer is silence. Callers must render nothing, never a placeholder.
                milesToReplacement: WearProjection.milesToReplacement(for: type, from: snapshots)
            )
        }
    }
}
