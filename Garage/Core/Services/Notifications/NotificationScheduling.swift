import Foundation

/// Whether the user has granted the `.alert`/`.sound` permission a local reminder notification
/// needs to actually show. Requested lazily — the first time a date-based reminder is saved,
/// never at app launch (see `ReminderNotificationCoordinator`).
enum NotificationAuthorizationState: Sendable, Equatable {
    case authorized
    case denied
}

/// Content for one locally-scheduled reminder notification. `id` mirrors the owning
/// `Reminder.id` so re-scheduling (create → update) replaces rather than duplicates, and
/// deletion/completion can cancel it by id alone.
struct ReminderNotificationRequest: Sendable, Equatable {
    let id: String
    let title: String
    let body: String
    let dueDate: Date
}

/// Fakeable wrapper around `UNUserNotificationCenter` — mirrors `SpeechTranscribing` /
/// `RevenueCatClienting`: a thin protocol over a system framework so mutation paths are
/// unit-testable with an injected fake instead of touching real OS notification state.
///
/// Local-only delivery for v1 (push/APNs is operator-gated). Every method is best-effort: a
/// scheduling failure must never fail the reminder save that triggered it.
@MainActor
protocol NotificationScheduling: AnyObject {
    /// Returns the current authorization state, prompting the system alert only the first time
    /// (when the status is still undetermined). Safe to call on every save — once the user has
    /// answered, this returns immediately without prompting again.
    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationState

    /// Schedules (or replaces, by `request.id`) a calendar-triggered local notification.
    func schedule(_ request: ReminderNotificationRequest) async

    /// Cancels any pending notification for this id. A no-op if none is pending.
    func cancel(id: String)

    /// Cancels every pending reminder notification. Called on sign-out (and, transitively,
    /// account deletion, which funnels through the same sign-out path) — nothing else cancels a
    /// vehicle's or account's local notifications when they're purged server-side, so without
    /// this the next person on the same device could inherit a prior user's reminders.
    func cancelAll()
}
