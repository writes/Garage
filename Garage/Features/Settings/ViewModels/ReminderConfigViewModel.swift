import Foundation
import Observation

@MainActor
@Observable
final class ReminderConfigViewModel {
    private let reminderService: ReminderService
    private let notificationCoordinator: ReminderNotificationCoordinator
    private let analytics: any AnalyticsTracking
    /// Guards `.notificationPermissionDenied` to at most once per VM instance — the view re-reads
    /// `isNotificationAuthorizationDenied` on every render, and without this the event would fire
    /// once per render rather than once per denial. `@ObservationIgnored` is load-bearing: the
    /// getter mutates this DURING view rendering, and mutating an observed property mid-render
    /// is an AttributeGraph cycle.
    @ObservationIgnored private var reportedNotificationDenial = false

    var title = "Oil change"
    var dueMileage = ""
    var dueMonths = ""
    /// Off by default: most reminders here are odometer/repeat-interval only (existing shape).
    /// Turning this on is what makes the reminder date-based and eligible for a local
    /// notification — see ReminderNotificationCoordinator.plan.
    var hasDueDate = false
    /// BLOCKER review finding: an untouched picker used to default to `Date.now`'s exact
    /// instant, which read as already-past by the time save() ran moments later —
    /// ReminderNotificationCoordinator.plan requires `dueDate > now`, so it silently returned
    /// nil and nothing ever scheduled (no error, no hint — "Reminder saved" just lied). Defaults
    /// to tomorrow 9am local instead, so an untouched "Remind me on a date" save always lands on
    /// a genuinely future instant; save() additionally canonicalizes whatever day is picked.
    var dueDate = ReminderConfigViewModel.defaultDueDate()
    private(set) var error: AppError?
    /// Backs the management list above the create form (D: reminders lifecycle) — every
    /// reminder for the vehicle, completed or not, soonest-due first via ReminderService.fetchAll.
    private(set) var reminders: [Reminder] = []
    private(set) var isLoading = false
    /// Mirrors LogViewModel.reloadToken: review finding — without it, an in-flight load()
    /// racing a NEWER load() (e.g. rapid vehicle switches) could let the stale response's
    /// `reminders`/`error` overwrite what the newer call already resolved.
    private var loadToken = 0

    /// Forwards ReminderNotificationCoordinator.isAuthorizationDenied (same pattern as
    /// AppState.isPro forwarding PurchaseService.isPro) — true only after a date-based save
    /// found notification permission denied. Drives the one-line hint in ReminderConfigView.
    var isNotificationAuthorizationDenied: Bool {
        let denied = notificationCoordinator.isAuthorizationDenied
        if denied, !reportedNotificationDenial {
            reportedNotificationDenial = true
            analytics.track(.notificationPermissionDenied)
        }
        return denied
    }

    init(
        reminderService: ReminderService = .shared,
        notificationCoordinator: ReminderNotificationCoordinator = .shared,
        analytics: any AnalyticsTracking = AnalyticsService.shared
    ) {
        self.reminderService = reminderService
        self.notificationCoordinator = notificationCoordinator
        self.analytics = analytics
    }

    func save(vehicleId: String, vehicleName: String? = nil) async -> Bool {
        do {
            let reminder = Reminder(
                id: UUID().uuidString,
                vehicleId: vehicleId,
                title: title,
                dueDate: hasDueDate ? Self.canonicalDueInstant(for: dueDate) : nil,
                dueMileage: Int(dueMileage),
                repeatIntervalMonths: Int(dueMonths),
                repeatIntervalMiles: Int(dueMileage),
                isProFeature: false
            )
            try await reminderService.save(reminder, vehicleName: vehicleName)
            analytics.track(.reminderCreated)
            error = nil
            await load(vehicleId: vehicleId)
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }

    func load(vehicleId: String) async {
        loadToken &+= 1
        let token = loadToken
        isLoading = true
        defer { if token == loadToken { isLoading = false } }
        do {
            let loaded = try await reminderService.fetchAll(vehicleId: vehicleId)
            guard token == loadToken else { return }
            reminders = loaded
            error = nil
        } catch {
            guard token == loadToken else { return }
            self.error = AppError(from: error)
        }
    }

    func delete(_ reminder: Reminder) async {
        do {
            try await reminderService.delete(reminder)
            reminders.removeAll { $0.id == reminder.id }
            analytics.track(.reminderDeleted)
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }

    func markCompleted(_ reminder: Reminder) async {
        do {
            try await reminderService.markCompleted(reminder)
            if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
                reminders[index].completedAt = .now
            }
            analytics.track(.reminderCompleted)
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }

    /// Tomorrow at 09:00 local. Internal (not private) and parameterized over `now`/`calendar` —
    /// exposed for direct unit testing, mirroring ReminderNotificationCoordinator.plan's
    /// precedent. Falls back to now+24h in the (practically unreachable) case the calendar can't
    /// produce a startOfDay/9h instant.
    static func defaultDueDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let tomorrowAt9 = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) else {
            return now.addingTimeInterval(24 * 60 * 60)
        }
        return tomorrowAt9
    }

    /// Canonicalizes whatever DAY the picker landed on to a fixed local time-of-day (09:00), so a
    /// future day always yields a future instant regardless of what wall-clock time-of-day the
    /// picker's value happens to carry (BLOCKER fix: an untouched picker previously kept
    /// `Date.now`'s exact instant, which read as already-past moments later). A TODAY selection
    /// that still normalizes into the past must not silently skip scheduling — it falls forward
    /// to now+5min instead. Internal, exposed for direct unit testing.
    static func canonicalDueInstant(for pickedDate: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        let normalized = calendar.date(
            bySettingHour: 9, minute: 0, second: 0, of: calendar.startOfDay(for: pickedDate)
        ) ?? pickedDate
        if normalized > now {
            return normalized
        }
        if calendar.isDate(pickedDate, inSameDayAs: now) {
            return now.addingTimeInterval(5 * 60)
        }
        return normalized
    }
}
