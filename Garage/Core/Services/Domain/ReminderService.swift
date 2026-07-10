import FirebaseFirestore
import Observation

@MainActor
@Observable
final class ReminderService {
    static let shared = ReminderService()

    private var firestore: FirestoreService { .shared }

    private init() {}

    func save(_ reminder: Reminder) async throws {
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(reminder)
            return
        }

        let reference = firestore.db.collection(FirestorePaths.vehicleReminders(vehicleId: reminder.vehicleId))
            .document(reminder.id)
        try await reference.setData(firestore.encode(reminder), merge: true)
    }

    func fetchUpcoming(vehicleId: String) async throws -> [Reminder] {
        if AppRuntime.isLocalDemoMode {
            return Self.sortUpcoming(DemoSessionStore.shared.reminders(for: vehicleId))
        }

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleReminders(vehicleId: vehicleId))
            .limit(to: 20)
            .getDocuments()

        let reminders = try snapshot.documents.map { try firestore.decode(Reminder.self, from: $0.data()) }
        return Self.sortUpcoming(reminders)
    }

    nonisolated static func sortUpcoming(_ reminders: [Reminder]) -> [Reminder] {
        reminders.sorted {
            ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }
}
