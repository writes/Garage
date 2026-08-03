import Foundation
import Testing
@testable import Garage

/// Shared with ReminderEditingTests (same module): records what the coordinator schedules and
/// cancels so notification identity is assertable without UNUserNotificationCenter.
@MainActor
final class FakeEditNotificationScheduler: NotificationScheduling {
    private(set) var scheduled: [String: ReminderNotificationRequest] = [:]
    private(set) var cancelledIDs: [String] = []

    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationState { .authorized }
    func schedule(_ request: ReminderNotificationRequest) async { scheduled[request.id] = request }
    func cancel(id: String) { cancelledIDs.append(id); scheduled[id] = nil }
    func cancelAll() { scheduled.removeAll() }
}

/// The notification half of the reminder-editing contract, split from ReminderEditingTests for
/// the 250-line file cap: an edit rides the SAME reminder id all the way into the
/// UNNotificationRequest identifier, so a moved due date replaces the pending alert and a removed
/// one retires it.
@MainActor
struct ReminderEditingNotificationTests {
    @MainActor
    private struct Harness {
        let viewModel: ReminderConfigViewModel
        let service: ReminderService
        let scheduler: FakeEditNotificationScheduler

        func stored() async throws -> [Reminder] {
            try await service.fetchAll(vehicleId: "vehicle-1")
        }
    }

    private func makeHarness(reminders: [Reminder]) -> Harness {
        let scheduler = FakeEditNotificationScheduler()
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler)
        let service = ReminderService(testReminders: reminders, notificationCoordinator: coordinator)
        let viewModel = ReminderConfigViewModel(
            reminderService: service, notificationCoordinator: coordinator, analytics: AnalyticsSpy()
        )
        return Harness(viewModel: viewModel, service: service, scheduler: scheduler)
    }

    /// Same reminder id = same UNNotificationRequest identifier, so an edited due date replaces
    /// the pending notification instead of leaving the old one to fire at the old time.
    @Test func save_whileEditing_reschedulesTheNotificationUnderTheSameIdentifier() async throws {
        let dueSoon = Date.now.addingTimeInterval(60 * 60 * 24 * 3)
        let reminder = Reminder(id: "reminder-1", vehicleId: "vehicle-1", title: "Oil change", dueDate: dueSoon)
        let harness = makeHarness(reminders: [reminder])
        harness.viewModel.beginEditing(reminder)
        let movedDueDate = Date.now.addingTimeInterval(60 * 60 * 24 * 30)
        harness.viewModel.dueDate = movedDueDate

        _ = await harness.viewModel.save(vehicleId: "vehicle-1")
        for _ in 0..<8 { await Task.yield() }

        #expect(harness.scheduler.scheduled.keys.sorted() == ["reminder-1"])
        let expected = ReminderConfigViewModel.canonicalDueInstant(for: movedDueDate)
        #expect(harness.scheduler.scheduled["reminder-1"]?.dueDate == expected)
    }

    /// Turning the date toggle off on an edit must retire the pending notification — otherwise a
    /// reminder that no longer has a due date still alerts.
    @Test func save_whileEditing_removingTheDueDateCancelsThePendingNotification() async throws {
        let dated = Date.now.addingTimeInterval(60 * 60 * 24 * 3)
        let reminder = Reminder(id: "reminder-1", vehicleId: "vehicle-1", title: "Oil change", dueDate: dated)
        let harness = makeHarness(reminders: [reminder])
        harness.viewModel.beginEditing(reminder)
        harness.viewModel.hasDueDate = false

        _ = await harness.viewModel.save(vehicleId: "vehicle-1")
        for _ in 0..<8 { await Task.yield() }

        #expect(harness.scheduler.cancelledIDs.contains("reminder-1"))
        #expect(harness.scheduler.scheduled.isEmpty)
        let updated = try #require(try await harness.stored().first)
        #expect(updated.dueDate == nil)
    }
}
