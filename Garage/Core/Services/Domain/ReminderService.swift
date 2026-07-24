import FirebaseFirestore
import Observation

@MainActor
@Observable
final class ReminderService {
    static let shared = ReminderService()

    private var firestore: FirestoreService { .shared }

    private init() {}

    func save(_ reminder: Reminder) async throws {
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(reminder)
            return
        }
#endif

        let reference = firestore.db.collection(FirestorePaths.vehicleReminders(vehicleId: reminder.vehicleId))
            .document(reminder.id)
        try await reference.setData(firestore.encode(reminder), merge: true)
        VehicleDataRevisionStore.shared.bump(vehicleId: reminder.vehicleId)
    }

    /// All reminders for the vehicle, completed or not — backs the management list in
    /// ReminderConfigView. `fetchUpcoming` layers the completed-filter on top of this.
    func fetchAll(vehicleId: String) async throws -> [Reminder] {
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return Self.sortUpcoming(DemoSessionStore.shared.reminders(for: vehicleId))
        }
#endif

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleReminders(vehicleId: vehicleId))
            .limit(to: 20)
            .getDocuments()

        let reminders = try snapshot.documents.map { try firestore.decode(Reminder.self, from: $0.data()) }
        return Self.sortUpcoming(reminders)
    }

    /// Excludes completed reminders client-side (no composite index needed) so the Dashboard's
    /// card and reload gate never resurface something the user already marked done.
    func fetchUpcoming(vehicleId: String) async throws -> [Reminder] {
        Self.excludingCompleted(try await fetchAll(vehicleId: vehicleId))
    }

    nonisolated static func excludingCompleted(_ reminders: [Reminder]) -> [Reminder] {
        reminders.filter { $0.completedAt == nil }
    }

    func delete(_ reminder: Reminder) async throws {
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.deleteReminder(id: reminder.id)
            return
        }
#endif

        let reference = firestore.db.collection(FirestorePaths.vehicleReminders(vehicleId: reminder.vehicleId))
            .document(reminder.id)
        try await reference.delete()
        VehicleDataRevisionStore.shared.bump(vehicleId: reminder.vehicleId)
    }

    func markCompleted(_ reminder: Reminder) async throws {
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            var completed = reminder
            completed.completedAt = .now
            DemoSessionStore.shared.save(completed)
            return
        }
#endif

        let reference = firestore.db.collection(FirestorePaths.vehicleReminders(vehicleId: reminder.vehicleId))
            .document(reminder.id)
        try await reference.setData(["completedAt": Timestamp(date: .now)], merge: true)
        VehicleDataRevisionStore.shared.bump(vehicleId: reminder.vehicleId)
    }

    nonisolated static func sortUpcoming(_ reminders: [Reminder]) -> [Reminder] {
        reminders.sorted {
            ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }
}
