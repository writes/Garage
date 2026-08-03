import Foundation
import Testing
@testable import Garage

@MainActor
private final class FakeReminderNotificationScheduler: NotificationScheduling {
    private(set) var scheduled: [String: ReminderNotificationRequest] = [:]
    private(set) var cancelledIDs: [String] = []

    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationState { .authorized }
    func schedule(_ request: ReminderNotificationRequest) async { scheduled[request.id] = request }
    func cancel(id: String) { cancelledIDs.append(id); scheduled[id] = nil }
    func cancelAll() { scheduled.removeAll() }
}

@MainActor
struct ReminderServiceTests {
    @Test func sortUpcoming_ordersByDateAscending() {
        let later = Reminder(id: "2", vehicleId: "vehicle", title: "Later", dueDate: Date(timeIntervalSince1970: 200))
        let sooner = Reminder(id: "1", vehicleId: "vehicle", title: "Sooner", dueDate: Date(timeIntervalSince1970: 100))

        let sorted = ReminderService.sortUpcoming([later, sooner])

        #expect(sorted.map(\.id) == ["1", "2"])
    }

    @Test func sortUpcoming_placesMissingDueDateLast() {
        let unscheduled = Reminder(id: "none", vehicleId: "vehicle", title: "Unscheduled", dueDate: nil)
        let scheduled = Reminder(
            id: "scheduled",
            vehicleId: "vehicle",
            title: "Scheduled",
            dueDate: Date(timeIntervalSince1970: 100)
        )

        let sorted = ReminderService.sortUpcoming([unscheduled, scheduled])

        #expect(sorted.map(\.id) == ["scheduled", "none"])
    }

    @Test func excludingCompleted_dropsOnlyRemindersWithACompletedAt() {
        let outstanding = Reminder(id: "outstanding", vehicleId: "vehicle", title: "Outstanding")
        var completed = Reminder(id: "completed", vehicleId: "vehicle", title: "Completed")
        completed.completedAt = Date(timeIntervalSince1970: 100)

        let filtered = ReminderService.excludingCompleted([outstanding, completed])

        #expect(filtered.map(\.id) == ["outstanding"])
    }

    // MARK: - Merge-write field clearing (reminder editing: a `setData(merge: true)` leaves keys
    // it isn't handed alone, and synthesized Codable omits nil optionals, so a cleared field would
    // otherwise survive the edit on the stored document)

    @Test func fieldsToClear_listsEveryFormOwnedFieldTheReminderNoLongerCarries() {
        let mileageOnly = Reminder(id: "r", vehicleId: "v", title: "Rotate tires", dueMileage: 5_000)

        #expect(ReminderService.fieldsToClear(in: mileageOnly) == [
            "dueDate", "repeatIntervalMonths", "repeatIntervalMiles"
        ])
    }

    @Test func fieldsToClear_isEmptyWhenEveryFormOwnedFieldIsPopulated() {
        let full = Reminder(
            id: "r", vehicleId: "v", title: "Oil change", dueDate: Date(timeIntervalSince1970: 100),
            dueMileage: 5_000, repeatIntervalMonths: 6, repeatIntervalMiles: 2_500
        )

        #expect(ReminderService.fieldsToClear(in: full).isEmpty)
    }

    /// Never touches fields the reminder form does not own — clearing those is not an edit this
    /// screen can express, and deleting them would be silent data loss.
    @Test func fieldsToClear_neverIncludesFieldsTheReminderFormDoesNotOwn() {
        let bare = Reminder(id: "r", vehicleId: "v", title: "Oil change")

        let fields = ReminderService.fieldsToClear(in: bare)

        #expect(!fields.contains("notes"))
        #expect(!fields.contains("entryType"))
        #expect(!fields.contains("createdAt"))
        #expect(!fields.contains("completedAt"))
    }

    // MARK: - markCompleted repeat-successor (FIX 3: repeats otherwise never reschedule, since
    // UNCalendarNotificationTrigger(repeats:false) fires once)

    @Test func markCompleted_repeatingDateBasedReminder_savesRolledForwardSuccessorAndSchedulesIt() async throws {
        let dueDate = Date.now.addingTimeInterval(60 * 60 * 24 * 10) // 10 days out, safely future
        let reminder = Reminder(
            id: "reminder-1", vehicleId: "vehicle-1", title: "Oil change", dueDate: dueDate,
            dueMileage: 5_000, repeatIntervalMonths: 3, repeatIntervalMiles: 3_000
        )
        let scheduler = FakeReminderNotificationScheduler()
        let service = ReminderService(
            testReminders: [reminder], notificationCoordinator: ReminderNotificationCoordinator(scheduler: scheduler)
        )

        try await service.markCompleted(reminder)
        for _ in 0..<8 { await Task.yield() }

        let all = try await service.fetchAll(vehicleId: "vehicle-1")
        #expect(all.count == 2)
        let successor = try #require(all.first { $0.id != "reminder-1" })
        let original = try #require(all.first { $0.id == "reminder-1" })
        #expect(original.completedAt != nil)
        #expect(successor.completedAt == nil)
        #expect(successor.vehicleId == "vehicle-1")
        #expect(successor.title == "Oil change")
        #expect(successor.repeatIntervalMonths == 3)
        #expect(successor.repeatIntervalMiles == 3_000)
        #expect(successor.dueMileage == 8_000)
        let expectedDueDate = try #require(Calendar.current.date(byAdding: .month, value: 3, to: dueDate))
        #expect(successor.dueDate == expectedDueDate)
        #expect(scheduler.cancelledIDs.contains("reminder-1"))
        #expect(scheduler.scheduled[successor.id]?.dueDate == expectedDueDate)
    }

    @Test func markCompleted_nonRepeatingReminder_doesNotCreateASuccessor() async throws {
        let reminder = Reminder(
            id: "reminder-2", vehicleId: "vehicle-1", title: "Rotate tires",
            dueDate: Date.now.addingTimeInterval(60 * 60 * 24 * 10), dueMileage: 5_000
        )
        let scheduler = FakeReminderNotificationScheduler()
        let service = ReminderService(
            testReminders: [reminder], notificationCoordinator: ReminderNotificationCoordinator(scheduler: scheduler)
        )

        try await service.markCompleted(reminder)
        for _ in 0..<8 { await Task.yield() }

        let all = try await service.fetchAll(vehicleId: "vehicle-1")
        #expect(all.count == 1)
        #expect(all.first?.id == "reminder-2")
        #expect(all.first?.completedAt != nil)
        #expect(scheduler.scheduled.isEmpty)
    }

    @Test func markCompleted_repeatingButNoDueDate_doesNotCreateASuccessor() async throws {
        let reminder = Reminder(
            id: "reminder-3", vehicleId: "vehicle-1", title: "Rotate tires",
            dueMileage: 5_000, repeatIntervalMonths: 3, repeatIntervalMiles: 3_000
        )
        let scheduler = FakeReminderNotificationScheduler()
        let service = ReminderService(
            testReminders: [reminder], notificationCoordinator: ReminderNotificationCoordinator(scheduler: scheduler)
        )

        try await service.markCompleted(reminder)
        for _ in 0..<8 { await Task.yield() }

        let all = try await service.fetchAll(vehicleId: "vehicle-1")
        #expect(all.count == 1)
    }
}
