@preconcurrency import FirebaseFirestore
import Foundation

// MARK: - Deletion (RULES-1 soft delete + trusted purge)

// Split out of VehicleService.swift to stay under the file cap (mirrors
// EntryServiceDeletionTests.swift's precedent for test files, applied to a source file here).

extension VehicleService {
    /// Tombstone first (client timestamp, fire-and-forget: lands in the local cache immediately
    /// and decodes as a real Date — a pending serverTimestamp reads as nil and would dodge the
    /// filter), then the purge CF runs detached. Failed purges self-heal via retryPendingPurges().
    func deleteVehicle(_ vehicle: Vehicle) async throws {
        // Best-effort, called from every branch below (unlike purgeInvoker, which only fires in
        // the live-Firestore branch): local reminder notifications are scoped to this app, not
        // the server-side recursiveDelete purge — nothing else cancels them, so a vehicle's
        // reminders could otherwise keep firing after the vehicle itself is gone. The call site
        // is uniform on purpose (mirrors EntryService+Mutations.swift's cascadeDeleteAttachments
        // precedent: exactly one cascade site) — the default closure self-gates on `mode == .live`
        // internally instead, so it stays a no-op for `.uiTest`-mode instances (VehicleService.uiTest)
        // without needing this call site to duplicate that guard.
        await reminderNotificationCancelInvoker(vehicle.id)

        if var testVehicles {
            testVehicles[vehicle.id] = nil
            self.testVehicles = testVehicles
            return
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            var tombstoned = vehicle
            tombstoned.deletedAt = Date.now
            DemoSessionStore.shared.save(tombstoned)
            return
        }
#endif
        guard mode == .live else { return }
        let firestore = firestoreProvider()
        let document = firestore.db.collection(FirestorePaths.vehicles).document(vehicle.id)
        writeTombstone(on: document)
        Task { [purgeInvoker] in
            do {
                try await purgeInvoker(vehicle.id)
            } catch {
                // The tombstone already hides the vehicle; the purge (subcollections + counter
                // decrement) converges on the next sweep. Not surfaced by design.
                AppLogger.shared.error("Vehicle purge failed for \(vehicle.id): \(error.localizedDescription)")
                CrashReporter.shared.record(error, context: "vehicle-purge")
            }
        }
    }

    /// Non-async on purpose: Swift 6 forbids the completion-handler overload inside async
    /// contexts, and the async variant is ack-gated (it would suspend forever offline).
    private func writeTombstone(on document: DocumentReference) {
        document.setData(["deletedAt": Timestamp(date: .now)], merge: true) { error in
            if let error {
                AppLogger.shared.error("Vehicle tombstone rejected: \(error.localizedDescription)")
            }
        }
    }

    /// Best-effort self-heal: re-purges any still-tombstoned vehicle (e.g. an offline delete).
    func retryPendingPurges() async {
        guard mode == .live, testVehicles == nil, !AppRuntime.isLocalDemoMode,
              let uid = uidProvider() else { return }
        do {
            let firestore = firestoreProvider()
            let query = firestore.db.collection(FirestorePaths.vehicles).whereField("userId", isEqualTo: uid)
            let snapshot = try await query.limit(to: 20).getDocuments()
            for document in snapshot.documents where document.data()["deletedAt"] != nil {
                do {
                    try await purgeInvoker(document.documentID)
                } catch {
                    AppLogger.shared.error(
                        "Vehicle purge retry failed for \(document.documentID): \(error.localizedDescription)"
                    )
                }
            }
        } catch {
            AppLogger.shared.error("Vehicle purge sweep failed: \(error.localizedDescription)")
        }
    }
}
