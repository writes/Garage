import Foundation
import UserNotifications

/// Live `NotificationScheduling` backed by `UNUserNotificationCenter`. Never constructed
/// directly by feature code — go through `NotificationSchedulerFactory.shared`, which swaps in
/// `NoOpNotificationScheduler` for demo/UI-test runs so those never touch real OS notification
/// state.
@MainActor
final class ReminderNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            return granted ? .authorized : .denied
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func schedule(_ request: ReminderNotificationRequest) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        // Category tag for funnel attribution in the notification-center delegate.
        content.userInfo = [
            NotificationFunnelService.categoryUserInfoKey: NotificationCategory.reminderDue.rawValue
        ]

        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: request.dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let osRequest = UNNotificationRequest(identifier: request.id, content: content, trigger: trigger)
        // Best-effort: a failed schedule call must never surface as a reminder-save failure.
        try? await center.add(osRequest)
    }

    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}

/// Demo/UI-test double: never touches `UNUserNotificationCenter`. Reports `.denied` so any
/// authorization-dependent UI (the "notifications off" hint) reflects reality — these runs never
/// actually prompt the OS, so nothing is ever really authorized.
@MainActor
final class NoOpNotificationScheduler: NotificationScheduling {
    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationState { .denied }

    func schedule(_: ReminderNotificationRequest) async {}

    func cancel(id _: String) {}

    func cancelAll() {}
}

/// Picks the real scheduler in production/TestFlight, the no-op in demo/UI-test runs — same
/// shape as `AnalyticsService`/`CrashReporter`'s DEBUG-mode swap.
@MainActor
enum NotificationSchedulerFactory {
    static let shared: any NotificationScheduling = {
#if DEBUG
        if AppRuntime.isLocalDemoMode || AppRuntime.isUITestMode {
            return NoOpNotificationScheduler()
        }
#endif
        return ReminderNotificationScheduler()
    }()
}
