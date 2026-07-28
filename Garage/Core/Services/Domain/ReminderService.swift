import FirebaseFirestore
import Observation

@MainActor
@Observable
final class ReminderService {
    static let shared = ReminderService()

    private var firestore: FirestoreService { .shared }
    private let notificationCoordinator: ReminderNotificationCoordinator
    /// Hermetic in-memory store, keyed by reminder id — mirrors VehicleService.testVehicles/
    /// EntryService.testEntries. Non-nil only via the #if DEBUG initializer below.
    private var testReminders: [String: Reminder]?

    private init() {
        notificationCoordinator = .shared
    }

#if DEBUG
    /// Hermetic constructor: routes save/fetchAll/delete/markCompleted through an in-memory
    /// dictionary instead of Firestore/DemoSessionStore, with an injected coordinator so the
    /// repeat-reminder successor logic (markCompleted) and its notification scheduling are
    /// directly unit-testable against a fake `NotificationScheduling` — mirrors VehicleService/
    /// EntryService's testVehicles/testEntries precedent.
    init(testReminders: [Reminder] = [], notificationCoordinator: ReminderNotificationCoordinator) {
        self.testReminders = Dictionary(uniqueKeysWithValues: testReminders.map { ($0.id, $0) })
        self.notificationCoordinator = notificationCoordinator
    }
#endif

    /// `vehicleName` is optional and cheap-only: pass it when the caller already has the
    /// `Vehicle` in memory (e.g. the reminder config form) so the local notification body can
    /// name it. No extra fetch is ever done to obtain it.
    ///
    /// Notification sync is fire-and-forget (unstructured `Task`): review finding — the FIRST
    /// date-based save on a device blocks on the system permission dialog, which used to hold up
    /// this whole call and, with it, the "Reminder saved" confirmation. The write above is
    /// already durable by the time `save` returns; scheduling is best-effort by design anyway
    /// (see ReminderNotificationCoordinator.syncAfterSave).
    func save(_ reminder: Reminder, vehicleName: String? = nil) async throws {
        if var testReminders {
            testReminders[reminder.id] = reminder
            self.testReminders = testReminders
            Task { await notificationCoordinator.syncAfterSave(reminder, vehicleName: vehicleName) }
            return
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(reminder)
            Task { await notificationCoordinator.syncAfterSave(reminder, vehicleName: vehicleName) }
            return
        }
#endif

        let reference = firestore.db.collection(FirestorePaths.vehicleReminders(vehicleId: reminder.vehicleId))
            .document(reminder.id)
        firestore.writeLocalFirst(try firestore.encode(reminder), to: reference, context: "reminder")
        VehicleDataRevisionStore.shared.bump(vehicleId: reminder.vehicleId)
        Task { await notificationCoordinator.syncAfterSave(reminder, vehicleName: vehicleName) }
    }

    /// All reminders for the vehicle, completed or not — backs the management list in
    /// ReminderConfigView. `fetchUpcoming` layers the completed-filter on top of this.
    func fetchAll(vehicleId: String) async throws -> [Reminder] {
        if let testReminders {
            return Self.sortUpcoming(testReminders.values.filter { $0.vehicleId == vehicleId })
        }
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
        if var testReminders {
            testReminders[reminder.id] = nil
            self.testReminders = testReminders
            notificationCoordinator.cancel(id: reminder.id)
            return
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.deleteReminder(id: reminder.id)
            notificationCoordinator.cancel(id: reminder.id)
            return
        }
#endif

        let reference = firestore.db.collection(FirestorePaths.vehicleReminders(vehicleId: reminder.vehicleId))
            .document(reminder.id)
        firestore.deleteLocalFirst(reference, context: "reminder")
        VehicleDataRevisionStore.shared.bump(vehicleId: reminder.vehicleId)
        notificationCoordinator.cancel(id: reminder.id)
    }

    /// MAJOR review finding: `UNCalendarNotificationTrigger(repeats: false)` (by design — see
    /// ReminderNotificationScheduler.schedule) fires once, so `repeatIntervalMonths`/
    /// `repeatIntervalMiles` were otherwise dead — a completed repeating reminder never came
    /// back. After persisting completion + cancelling, mints a successor (scheduleSuccessorIfRepeating)
    /// through the normal `save` path so it gets its own notification the same way a
    /// manually-created reminder would.
    func markCompleted(_ reminder: Reminder) async throws {
        if var testReminders {
            var completed = reminder
            completed.completedAt = .now
            testReminders[reminder.id] = completed
            self.testReminders = testReminders
            notificationCoordinator.cancel(id: reminder.id)
            await scheduleSuccessorIfRepeating(reminder)
            return
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            var completed = reminder
            completed.completedAt = .now
            DemoSessionStore.shared.save(completed)
            notificationCoordinator.cancel(id: reminder.id)
            await scheduleSuccessorIfRepeating(reminder)
            return
        }
#endif

        let reference = firestore.db.collection(FirestorePaths.vehicleReminders(vehicleId: reminder.vehicleId))
            .document(reminder.id)
        try await reference.setData(["completedAt": Timestamp(date: .now)], merge: true)
        VehicleDataRevisionStore.shared.bump(vehicleId: reminder.vehicleId)
        notificationCoordinator.cancel(id: reminder.id)
        await scheduleSuccessorIfRepeating(reminder)
    }

    /// Only when the just-completed reminder is BOTH date-based and has a repeat interval: mints
    /// a new reminder (new id; same vehicleId/title/notes/entryType/repeat fields/isProFeature)
    /// with its due date rolled forward from whichever is later — the old due date or now, so a
    /// long-overdue completion doesn't roll forward from a stale past date — and its due mileage
    /// bumped by repeatIntervalMiles when both are set. Best-effort, same contract as
    /// ReminderNotificationCoordinator's own scheduling calls: a failed successor save must never
    /// surface as a markCompleted failure — the completion write already succeeded.
    private func scheduleSuccessorIfRepeating(_ reminder: Reminder) async {
        guard let months = reminder.repeatIntervalMonths, let dueDate = reminder.dueDate else { return }
        var successor = reminder
        successor.id = UUID().uuidString
        successor.completedAt = nil
        successor.createdAt = nil
        successor.dueDate = Calendar.current.date(byAdding: .month, value: months, to: max(dueDate, .now))
        if let dueMileage = reminder.dueMileage, let repeatMiles = reminder.repeatIntervalMiles {
            successor.dueMileage = dueMileage + repeatMiles
        }
        do {
            try await save(successor)
        } catch {
            AppLogger.shared.error("Repeat reminder successor failed to save: \(error.localizedDescription)")
        }
    }

    nonisolated static func sortUpcoming(_ reminders: [Reminder]) -> [Reminder] {
        reminders.sorted {
            ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }
}
