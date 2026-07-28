import FirebaseFirestore
import Observation

@MainActor
@Observable
final class WarrantyService {
    static let shared = WarrantyService()

    private var firestore: FirestoreService { .shared }

    private init() {}

    /// Demo writes go to the in-memory overlay rather than being dropped. A bare early return
    /// let the form dismiss as if it had saved while the record vanished — the screen then showed
    /// "No warranty records yet" immediately after the user added one, which is the app lying
    /// about the user's own action. Matches the entry/vehicle/reminder overlay precedent.
    func saveWarranty(_ warranty: Warranty) async throws {
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(warranty)
            return
        }

        let reference = firestore.db.collection(FirestorePaths.vehicleWarranties(vehicleId: warranty.vehicleId))
            .document(warranty.id)
        try await reference.setData(firestore.encode(warranty), merge: true)
        VehicleDataRevisionStore.shared.bump(vehicleId: warranty.vehicleId)
    }

    func fetchWarranties(vehicleId: String) async throws -> [Warranty] {
        if AppRuntime.isLocalDemoMode {
            return DemoSessionStore.shared.warranties(for: vehicleId)
        }

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleWarranties(vehicleId: vehicleId))
            .limit(to: 20)
            .getDocuments()

        // Tolerant, for the same reason entries and vehicles are: one undecodable document must
        // not blank a screen that is otherwise full of the user's records.
        return Self.decodeTolerantly(snapshot.documents, as: Warranty.self, using: firestore)
    }

    /// See saveWarranty: demo writes persist to the overlay instead of being silently discarded.
    func saveRecall(_ recall: Recall) async throws {
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(recall)
            return
        }

        let reference = firestore.db.collection(FirestorePaths.vehicleRecalls(vehicleId: recall.vehicleId))
            .document(recall.id)
        try await reference.setData(firestore.encode(recall), merge: true)
        VehicleDataRevisionStore.shared.bump(vehicleId: recall.vehicleId)
    }

    func fetchRecalls(vehicleId: String) async throws -> [Recall] {
        if AppRuntime.isLocalDemoMode {
            return DemoSessionStore.shared.recalls(for: vehicleId)
        }

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleRecalls(vehicleId: vehicleId))
            .limit(to: 50)
            .getDocuments()

        return Self.decodeTolerantly(snapshot.documents, as: Recall.self, using: firestore)
    }

    /// Skips documents that fail to decode instead of throwing the whole fetch away, and records
    /// each failure as a Crashlytics non-fatal so "dropped quietly for the user" still means
    /// "visible to us". Mirrors VehicleService.fetchVehicles and EntryService.decodeTolerantly.
    private static func decodeTolerantly<T: Decodable>(
        _ documents: [QueryDocumentSnapshot],
        as type: T.Type,
        using firestore: FirestoreService
    ) -> [T] {
        documents.compactMap { document in
            do {
                return try firestore.decode(T.self, from: document.data())
            } catch {
                AppLogger.shared.error(
                    "\(T.self) decode failed for \(document.documentID): \(error.localizedDescription)"
                )
                CrashReporter.shared.record(error, context: "warranty-decode")
                return nil
            }
        }
    }
}
