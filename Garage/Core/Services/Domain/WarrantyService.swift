import FirebaseFirestore
import Observation

@MainActor
@Observable
final class WarrantyService {
    static let shared = WarrantyService()

    private var firestore: FirestoreService { .shared }

    private init() {}

#if DEBUG
    /// In-memory seam, mirroring `EntryService.init(testEntries:)`. Without it a test that
    /// exercises anything ending in `load()` reaches real Firestore and fails on permissions —
    /// which is how the recall-import tests first went red.
    private var testWarranties: [Warranty]?
    private var testRecalls: [Recall]?

    init(testWarranties: [Warranty], testRecalls: [Recall]) {
        self.testWarranties = testWarranties
        self.testRecalls = testRecalls
    }
#endif

    /// Demo writes go to the in-memory overlay rather than being dropped. A bare early return
    /// let the form dismiss as if it had saved while the record vanished — the screen then showed
    /// "No warranty records yet" immediately after the user added one, which is the app lying
    /// about the user's own action. Matches the entry/vehicle/reminder overlay precedent.
    func saveWarranty(_ warranty: Warranty) throws {
#if DEBUG
        if testWarranties != nil {
            testWarranties?.removeAll { $0.id == warranty.id }
            testWarranties?.append(warranty)
            return
        }
#endif
        // DemoSessionStore is `#if DEBUG` — the Release archive cannot see it, which is what the
        // regenerate-and-archive gate caught. The guard below preserves the old Release behaviour.
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(warranty)
            return
        }
#endif
        guard !AppRuntime.isLocalDemoMode else { return }

        let reference = firestore.db.collection(FirestorePaths.vehicleWarranties(vehicleId: warranty.vehicleId))
            .document(warranty.id)
        // NOT `try await setData(...)`. Firestore resolves the awaited form only on SERVER
        // acknowledgement, so offline it never resumes — and offline is where people log service:
        // garages, parking structures, rural roads. The non-awaiting form persists locally at once
        // and syncs when the device reconnects, which is the whole point of Firestore's offline
        // cache. The entry batch already works this way (`batch.commit { }` with a callback).
        reference.setData(try firestore.encode(warranty), merge: true) { error in
            if let error {
                AppLogger.shared.error("Warranty sync failed: \(error.localizedDescription)")
            }
        }
        VehicleDataRevisionStore.shared.bump(vehicleId: warranty.vehicleId)
    }

    func fetchWarranties(vehicleId: String) async throws -> [Warranty] {
#if DEBUG
        if let testWarranties { return testWarranties.filter { $0.vehicleId == vehicleId } }
#endif
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return DemoSessionStore.shared.warranties(for: vehicleId)
        }
#endif
        if AppRuntime.isLocalDemoMode {
            return SeedData.warranties(for: vehicleId)
        }

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleWarranties(vehicleId: vehicleId))
            .limit(to: 20)
            .getDocuments()

        // Tolerant, for the same reason entries and vehicles are: one undecodable document must
        // not blank a screen that is otherwise full of the user's records.
        return Self.decodeTolerantly(snapshot.documents, as: Warranty.self, using: firestore)
    }

    /// See saveWarranty: demo writes persist to the overlay instead of being silently discarded.
    func saveRecall(_ recall: Recall) throws {
#if DEBUG
        if testRecalls != nil {
            testRecalls?.removeAll { $0.id == recall.id }
            testRecalls?.append(recall)
            return
        }
#endif
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(recall)
            return
        }
#endif
        guard !AppRuntime.isLocalDemoMode else { return }

        let reference = firestore.db.collection(FirestorePaths.vehicleRecalls(vehicleId: recall.vehicleId))
            .document(recall.id)
        // See saveWarranty: the non-awaiting form, so an offline save cannot hang the sheet.
        reference.setData(try firestore.encode(recall), merge: true) { error in
            if let error {
                AppLogger.shared.error("Recall sync failed: \(error.localizedDescription)")
            }
        }
        VehicleDataRevisionStore.shared.bump(vehicleId: recall.vehicleId)
    }

    func fetchRecalls(vehicleId: String) async throws -> [Recall] {
#if DEBUG
        if let testRecalls { return testRecalls.filter { $0.vehicleId == vehicleId } }
#endif
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return DemoSessionStore.shared.recalls(for: vehicleId)
        }
#endif
        if AppRuntime.isLocalDemoMode {
            return SeedData.recalls(for: vehicleId)
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
