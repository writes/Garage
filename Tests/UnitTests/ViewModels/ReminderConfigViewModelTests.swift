import Foundation
import Testing
@testable import Garage

@MainActor
private final class FakeReminderNotificationScheduler: NotificationScheduling {
    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationState { .authorized }
    func schedule(_ request: ReminderNotificationRequest) async {}
    func cancel(id: String) {}
    func cancelAll() {}
}

/// BLOCKER review finding: an untouched "Remind me on a date" picker defaulted to `Date.now`'s
/// exact instant, which read as already-past by the time save() ran moments later —
/// ReminderNotificationCoordinator.plan requires `dueDate > now`, so it silently returned nil and
/// nothing ever scheduled (no error surfaced — "Reminder saved" just lied). These tests cover the
/// pure date-math fix directly, mirroring ReminderNotificationCoordinatorTests' style.
@MainActor
struct ReminderConfigViewModelTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return calendar
    }()

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) throws -> Date {
        try #require(Self.calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )))
    }

    @Test func defaultDueDate_isTomorrowAt9AMLocal() throws {
        // A Tuesday at 2:30pm.
        let now = try date(year: 2026, month: 7, day: 21, hour: 14, minute: 30)
        let expected = try date(year: 2026, month: 7, day: 22, hour: 9)

        let result = ReminderConfigViewModel.defaultDueDate(now: now, calendar: Self.calendar)

        #expect(result == expected)
    }

    /// The exact regression this fix closes: construct the VM's default, then simulate save()
    /// running a few seconds later — ReminderNotificationCoordinator.plan must still find a
    /// future due date and schedule (before the fix, the default carried `now`'s literal instant,
    /// so a few seconds later it already read as past-due and plan returned nil).
    @Test func defaultDueDate_secondsLaterSaveStillProducesAScheduleableReminder() {
        let initNow = Date(timeIntervalSince1970: 1_753_142_400) // arbitrary fixed instant
        let defaultDate = ReminderConfigViewModel.defaultDueDate(now: initNow, calendar: Self.calendar)
        let saveNow = initNow.addingTimeInterval(5)

        let canonical = ReminderConfigViewModel.canonicalDueInstant(
            for: defaultDate, now: saveNow, calendar: Self.calendar
        )
        let reminder = Reminder(id: "r1", vehicleId: "v1", title: "Oil change", dueDate: canonical)
        let plan = ReminderNotificationCoordinator.plan(for: reminder, vehicleName: nil, now: saveNow)

        #expect(plan != nil)
    }

    @Test func canonicalDueInstant_futureDaySelection_normalizesToNineAMLocalOnThatDay() throws {
        let now = try date(year: 2026, month: 7, day: 21, hour: 8)
        let picked = try date(year: 2026, month: 7, day: 25, hour: 23, minute: 45)
        let expected = try date(year: 2026, month: 7, day: 25, hour: 9)

        let result = ReminderConfigViewModel.canonicalDueInstant(for: picked, now: now, calendar: Self.calendar)

        #expect(result == expected)
    }

    /// The fallback the review explicitly called out: a TODAY selection that normalizes to a
    /// past 09:00 must not silently skip scheduling — it falls forward to now+5min instead.
    @Test func canonicalDueInstant_todaySelectionAfter9AM_fallsForwardToNowPlus5Minutes() throws {
        let now = try date(year: 2026, month: 7, day: 21, hour: 14)

        let result = ReminderConfigViewModel.canonicalDueInstant(for: now, now: now, calendar: Self.calendar)

        #expect(result == now.addingTimeInterval(5 * 60))
    }

    @Test func canonicalDueInstant_todaySelectionBefore9AM_normalizesToNineAMToday() throws {
        let now = try date(year: 2026, month: 7, day: 21, hour: 6)
        let expected = try date(year: 2026, month: 7, day: 21, hour: 9)

        let result = ReminderConfigViewModel.canonicalDueInstant(for: now, now: now, calendar: Self.calendar)

        #expect(result == expected)
    }

    // MARK: - Analytics

    @Test func save_succeeds_tracksReminderCreated() async {
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let coordinator = ReminderNotificationCoordinator(scheduler: FakeReminderNotificationScheduler())
        let viewModel = ReminderConfigViewModel(
            reminderService: ReminderService(testReminders: [], notificationCoordinator: coordinator),
            notificationCoordinator: coordinator,
            analytics: analytics
        )
        viewModel.title = "Oil change"
        viewModel.dueMileage = "5000"

        let didSave = await viewModel.save(vehicleId: "vehicle-1")

        #expect(didSave)
        #expect(analytics.events == [.reminderCreated])
    }

    @Test func delete_succeeds_tracksReminderDeleted() async {
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let coordinator = ReminderNotificationCoordinator(scheduler: FakeReminderNotificationScheduler())
        let reminder = Reminder(id: "r1", vehicleId: "vehicle-1", title: "Oil change", dueMileage: 5_000)
        let viewModel = ReminderConfigViewModel(
            reminderService: ReminderService(testReminders: [reminder], notificationCoordinator: coordinator),
            notificationCoordinator: coordinator,
            analytics: analytics
        )

        await viewModel.delete(reminder)

        #expect(analytics.events == [.reminderDeleted])
    }
}
