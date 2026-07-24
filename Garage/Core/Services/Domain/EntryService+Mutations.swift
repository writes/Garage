import FirebaseFirestore
import Foundation

// MARK: - Deletion (audit finding: records could not be corrected — entries were write-once)

extension EntryService {
    /// Hard delete: entries have no soft-delete/tombstone concept (unlike Vehicle's RULES-1
    /// pattern), so this removes the document outright and bumps the revision store the same way
    /// `save` does, so gated dashboard/log reads pick up the removal on their next check.
    ///
    /// `updatingVehicle` is required (not defaulted) so a caller can't silently forget it: review
    /// finding — deleting the entry currently holding the vehicle's `currentOdometer` left that
    /// field stale (still pointing at a document that no longer exists) unless the caller passes
    /// its vehicle snapshot here for reconciliation. Pass `nil` only when no vehicle context is
    /// available (reconciliation is then skipped, matching the pre-fix behavior).
    func deleteEntry(_ entry: FirestoreEntry, updatingVehicle vehicle: Vehicle?) async throws {
        if var testEntries {
#if DEBUG
            if !usesHermeticSave {
                try await deleteLive(entry, updatingVehicle: vehicle)
                return
            }
#endif
            // Hermetic array mode has no companion vehicle doc to reconcile against — entry-only,
            // regardless of what `vehicle` is passed. See EntryServiceTests for the explicit note.
            testEntries.removeAll { $0.id == entry.id }
            self.testEntries = testEntries
            return
        }
#if DEBUG
        if isLocalDemoMode() {
            deleteDemo(entry, updatingVehicle: vehicle)
            return
        }
#endif
        try await deleteLive(entry, updatingVehicle: vehicle)
    }

    private func deleteLive(_ entry: FirestoreEntry, updatingVehicle vehicle: Vehicle?) async throws {
        let dependencies = liveDependenciesProvider()
        try await firestore.db.collection(
            FirestorePaths.vehicleEntries(vehicleId: entry.vehicleId)
        ).document(entry.id).delete()
        if Self.shouldReconcileOdometer(afterDeleting: entry, from: vehicle) {
            let remainingMax = try await fetchLatestOdometer(vehicleId: entry.vehicleId) ?? 0
            try await firestore.db.collection(FirestorePaths.vehicles).document(entry.vehicleId).setData(
                ["currentOdometer": remainingMax, "updatedAt": Timestamp(date: .now)], merge: true
            )
        }
        dependencies.bumpRevision(entry.vehicleId)
    }

#if DEBUG
    private func deleteDemo(_ entry: FirestoreEntry, updatingVehicle vehicle: Vehicle?) {
        DemoSessionStore.shared.deleteEntry(id: entry.id)
        guard Self.shouldReconcileOdometer(afterDeleting: entry, from: vehicle),
              var demoVehicle = DemoSessionStore.shared.vehicles().first(where: { $0.id == entry.vehicleId })
        else { return }
        demoVehicle.currentOdometer = Self.latestOdometer(
            in: DemoSessionStore.shared.entries(for: entry.vehicleId), vehicleId: entry.vehicleId
        ) ?? 0
        demoVehicle.updatedAt = .now
        DemoSessionStore.shared.save(demoVehicle)
    }
#endif

    /// Pure predicate (independently testable without Firestore/DemoSessionStore): whether
    /// deleting `entry` might leave `vehicle.currentOdometer` pointing at something no longer
    /// backed by any entry, so a reconciliation recompute+write is due. Relaxed from `==` to `>=`
    /// (review BLOCKER): a `==`-only trigger could never self-heal an already-stale/"ghost"
    /// currentOdometer left behind by an unrelated race — recompute is idempotent and cheap, so
    /// triggering on `>=` means any accumulated ghost value heals the next time an entry at or
    /// below it is deleted.
    static func shouldReconcileOdometer(afterDeleting entry: FirestoreEntry, from vehicle: Vehicle?) -> Bool {
        guard let vehicle else { return false }
        return vehicle.id == entry.vehicleId && vehicle.currentOdometer >= entry.odometerReading
    }
}
