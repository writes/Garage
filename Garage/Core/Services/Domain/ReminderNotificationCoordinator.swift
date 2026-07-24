import Foundation
import Observation

/// Keeps a reminder's locally-scheduled notification consistent with its saved state. Pure
/// translation logic (reminder → schedule/cancel) lives here, decoupled from Firestore/
/// DemoSessionStore, so it's unit-testable end to end with a fake `NotificationScheduling`
/// (mirrors `VoiceQuickAddService`'s fakeable-protocol pattern) without a Firestore emulator.
///
/// `@Observable` so `isAuthorizationDenied` can drive a UI hint the same way `AppState.isPro`
/// forwards from `PurchaseService` — a plain computed property that reads a nested `@Observable`
/// still participates in SwiftUI's observation tracking.
@MainActor
@Observable
final class ReminderNotificationCoordinator {
    static let shared = ReminderNotificationCoordinator(scheduler: NotificationSchedulerFactory.shared)

    private let scheduler: any NotificationScheduling
    /// Set after a date-based save couldn't schedule because notification permission is denied.
    /// The reminder itself still saved — this only drives the one-line hint in
    /// ReminderConfigView. Cleared the next time a date-based save succeeds in scheduling.
    private(set) var isAuthorizationDenied = false

    init(scheduler: any NotificationScheduling) {
        self.scheduler = scheduler
    }

    /// Called after a reminder is created or updated. Schedules (replacing any prior
    /// notification for this id) when it's date-based, not completed, and not past due;
    /// cancels otherwise — covers odometer-only reminders, a due date that moved into the
    /// past, and a save that also marks the reminder completed.
    func syncAfterSave(_ reminder: Reminder, vehicleName: String?, now: Date = .now) async {
        guard let plan = Self.plan(for: reminder, vehicleName: vehicleName, now: now) else {
            scheduler.cancel(id: reminder.id)
            return
        }

        let state = await scheduler.requestAuthorizationIfNeeded()
        guard state == .authorized else {
            isAuthorizationDenied = true
            scheduler.cancel(id: reminder.id)
            return
        }
        isAuthorizationDenied = false
        await scheduler.schedule(plan)
    }

    /// Called on delete and on markCompleted — cancellation never needs authorization.
    func cancel(id: String) {
        scheduler.cancel(id: id)
    }

    /// Called from the sign-out choke point (AppState.signOut(), which plain sign-out AND
    /// account deletion both funnel through) — review finding: nothing cancelled scheduled
    /// local notifications on sign-out, so the next person on the same device could inherit a
    /// prior user's reminders. Cancellation never needs authorization, same as cancel(id:).
    func cancelAll() {
        scheduler.cancelAll()
    }

    /// Pure decision: nil means "cancel, don't schedule" (odometer-only, past-due, or already
    /// completed); otherwise the request to schedule. Exposed for direct unit testing.
    nonisolated static func plan(
        for reminder: Reminder,
        vehicleName: String?,
        now: Date
    ) -> ReminderNotificationRequest? {
        guard reminder.completedAt == nil,
              let dueDate = reminder.dueDate,
              dueDate > now else {
            return nil
        }
        return ReminderNotificationRequest(
            id: reminder.id,
            title: reminder.title,
            body: notificationBody(vehicleName: vehicleName),
            dueDate: dueDate
        )
    }

    nonisolated static func notificationBody(vehicleName: String?) -> String {
        guard let vehicleName, vehicleName.isNotEmpty else { return "Reminder due" }
        return "Due for \(vehicleName)"
    }
}
