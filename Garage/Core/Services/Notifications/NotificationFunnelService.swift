import Foundation
import UserNotifications

/// Notification-funnel instrumentation: `notif_scheduled` → `notif_opened` →
/// `notif_task_completed`. This is the app's FIRST `UNUserNotificationCenterDelegate` — before
/// it, tapping a reminder notification just opened the app with nothing observing it.
///
/// The delegate callbacks are deliberately the completion-handler variants marked
/// `nonisolated`, with Sendable values extracted BEFORE hopping to the main actor. A
/// MainActor-inferred ObjC completion handler that the OS invokes off-main traps at runtime on
/// device only — the exact Swift 6 isolation class behind the TestFlight voice crash
/// (swift6-isolation-callback-trap).
@MainActor
final class NotificationFunnelService: NSObject {
    /// Task completion within this window of an open is attributed to the notification.
    static let attributionWindow: TimeInterval = 7 * 24 * 60 * 60
    private static let storageKey = "garage.notification-funnel.v1"
    /// `userInfo` key carrying the category on every scheduled notification, so the delegate
    /// can attribute opens once more categories than reminders exist. `nonisolated`: read from
    /// the OS-thread delegate callback.
    nonisolated static let categoryUserInfoKey = "notif_category"

    static let shared = NotificationFunnelService(
        defaults: AppRuntime.isLocalDemoMode || AppRuntime.isUITestMode ? nil : .standard,
        analytics: AnalyticsService.shared
    )

    private let defaults: UserDefaults?
    private let analytics: any AnalyticsTracking
    /// Last open per category raw value, persisted so an open in one session still attributes
    /// a completion in the next.
    private var openedAt: [String: Date]

    init(defaults: UserDefaults?, analytics: any AnalyticsTracking) {
        self.defaults = defaults
        self.analytics = analytics
        if let data = defaults?.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            openedAt = decoded
        } else {
            openedAt = [:]
        }
        super.init()
    }

    /// Installs this service as the notification-center delegate. Production only — demo and
    /// UI-test runs never touch real OS notification state (same rule as the scheduler no-op).
    func activate() {
#if DEBUG
        if AppRuntime.isLocalDemoMode || AppRuntime.isUITestMode { return }
#endif
        UNUserNotificationCenter.current().delegate = self
    }

    func recordScheduled(_ category: NotificationCategory) {
        analytics.track(.notifScheduled(category: category))
    }

    func recordOpen(_ category: NotificationCategory, now: Date = .now) {
        openedAt[category.rawValue] = now
        persist()
        analytics.track(.notifOpened(category: category))
    }

    /// Call from the task's completion choke point (e.g. beside `reminder_completed`). Fires at
    /// most once per open, only inside the attribution window, and clears the open either way
    /// once consumed — a completion months later must not credit a long-dead notification.
    func recordTaskCompletionIfAttributed(_ category: NotificationCategory, now: Date = .now) {
        guard let opened = openedAt[category.rawValue] else { return }
        openedAt.removeValue(forKey: category.rawValue)
        persist()
        guard now.timeIntervalSince(opened) >= 0,
              now.timeIntervalSince(opened) <= Self.attributionWindow else { return }
        analytics.track(.notifTaskCompleted(category: category))
    }

    private func persist() {
        guard let defaults, let data = try? JSONEncoder().encode(openedAt) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

extension NotificationFunnelService: UNUserNotificationCenterDelegate {
    /// Foreground arrivals still present (banner + sound) — without a delegate iOS suppresses
    /// foreground banners entirely, so this also FIXES silent foreground reminders.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Extract the Sendable payload BEFORE crossing to the main actor (see class doc).
        let rawCategory = response.notification.request.content
            .userInfo[Self.categoryUserInfoKey] as? String
        Task { @MainActor in
            // Every notification the app has ever scheduled is a reminder; the userInfo key
            // takes over routing as soon as a second category ships.
            let category = NotificationCategory(rawValue: rawCategory ?? "") ?? .reminderDue
            NotificationFunnelService.shared.recordOpen(category)
        }
        completionHandler()
    }
}
