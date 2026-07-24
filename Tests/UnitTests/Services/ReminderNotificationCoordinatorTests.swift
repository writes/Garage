import Foundation
import Testing
@testable import Garage

@MainActor
private final class FakeNotificationScheduler: NotificationScheduling {
    var authorizationState: NotificationAuthorizationState = .authorized
    private(set) var authorizationRequestCount = 0
    private(set) var scheduleCallCount = 0
    private(set) var scheduled: [String: ReminderNotificationRequest] = [:]
    private(set) var cancelledIDs: [String] = []
    private(set) var cancelAllCallCount = 0

    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationState {
        authorizationRequestCount += 1
        return authorizationState
    }

    func schedule(_ request: ReminderNotificationRequest) async {
        scheduleCallCount += 1
        scheduled[request.id] = request
    }

    func cancel(id: String) {
        cancelledIDs.append(id)
        scheduled[id] = nil
    }

    func cancelAll() {
        cancelAllCallCount += 1
        scheduled.removeAll()
    }
}

private let referenceNow = Date(timeIntervalSince1970: 1_000_000)

private func futureReminder(
    id: String = "reminder-1",
    dueDate: Date = referenceNow.addingTimeInterval(3_600),
    completedAt: Date? = nil
) -> Reminder {
    Reminder(id: id, vehicleId: "vehicle-1", title: "Oil change", dueDate: dueDate, completedAt: completedAt)
}

@MainActor
struct ReminderNotificationCoordinatorTests {
    @Test func scheduleOnCreate_dateBasedReminderSchedulesWithVehicleName() async {
        let scheduler = FakeNotificationScheduler()
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler)
        let reminder = futureReminder()

        await coordinator.syncAfterSave(reminder, vehicleName: "1996 Dodge Viper", now: referenceNow)

        #expect(scheduler.scheduleCallCount == 1)
        #expect(scheduler.scheduled[reminder.id]?.title == "Oil change")
        #expect(scheduler.scheduled[reminder.id]?.body == "Due for 1996 Dodge Viper")
        #expect(scheduler.scheduled[reminder.id]?.dueDate == reminder.dueDate)
        #expect(coordinator.isAuthorizationDenied == false)
    }

    @Test func scheduleOnCreate_missingVehicleNameFallsBackToGenericBody() async {
        let scheduler = FakeNotificationScheduler()
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler)

        await coordinator.syncAfterSave(futureReminder(), vehicleName: nil, now: referenceNow)

        #expect(scheduler.scheduled["reminder-1"]?.body == "Reminder due")
    }

    @Test func replaceOnUpdate_secondSaveWithSameIDOverwritesThePendingRequest() async {
        let scheduler = FakeNotificationScheduler()
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler)
        let firstDueDate = referenceNow.addingTimeInterval(3_600)
        let updatedDueDate = referenceNow.addingTimeInterval(7_200)

        await coordinator.syncAfterSave(futureReminder(dueDate: firstDueDate), vehicleName: nil, now: referenceNow)
        await coordinator.syncAfterSave(futureReminder(dueDate: updatedDueDate), vehicleName: nil, now: referenceNow)

        #expect(scheduler.scheduleCallCount == 2)
        #expect(scheduler.scheduled.count == 1)
        #expect(scheduler.scheduled["reminder-1"]?.dueDate == updatedDueDate)
    }

    @Test func cancelOnDelete_routesThroughToTheScheduler() {
        let scheduler = FakeNotificationScheduler()
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler)

        coordinator.cancel(id: "reminder-1")

        #expect(scheduler.cancelledIDs == ["reminder-1"])
        #expect(scheduler.scheduleCallCount == 0)
    }

    /// FIX 2 review finding: nothing cancelled scheduled local notifications on sign-out (or,
    /// transitively, account deletion) — the next person on the same device could inherit a
    /// prior user's reminders. AppState.signOut() calls this.
    @Test func cancelAll_routesThroughToTheSchedulersCancelAll() async {
        let scheduler = FakeNotificationScheduler()
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler)
        await coordinator.syncAfterSave(futureReminder(), vehicleName: nil, now: referenceNow)
        #expect(scheduler.scheduled.count == 1)

        coordinator.cancelAll()

        #expect(scheduler.cancelAllCallCount == 1)
        #expect(scheduler.scheduled.isEmpty)
    }

    @Test func cancelOnComplete_savingACompletedReminderCancelsRatherThanSchedules() async {
        let scheduler = FakeNotificationScheduler()
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler)
        let completed = futureReminder(completedAt: referenceNow)

        await coordinator.syncAfterSave(completed, vehicleName: nil, now: referenceNow)

        #expect(scheduler.cancelledIDs == ["reminder-1"])
        #expect(scheduler.scheduleCallCount == 0)
        #expect(scheduler.authorizationRequestCount == 0)
    }

    @Test func pastDueSkip_doesNotScheduleOrPromptForAuthorization() async {
        let scheduler = FakeNotificationScheduler()
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler)
        let pastDue = futureReminder(dueDate: referenceNow.addingTimeInterval(-60))

        await coordinator.syncAfterSave(pastDue, vehicleName: nil, now: referenceNow)

        #expect(scheduler.scheduleCallCount == 0)
        #expect(scheduler.cancelledIDs == ["reminder-1"])
        #expect(scheduler.authorizationRequestCount == 0)
    }

    @Test func odometerOnlyReminder_neverSchedulesEvenWhenAuthorized() async {
        let scheduler = FakeNotificationScheduler()
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler)
        let odometerOnly = Reminder(id: "reminder-2", vehicleId: "vehicle-1", title: "Rotate tires", dueMileage: 5_000)

        await coordinator.syncAfterSave(odometerOnly, vehicleName: "Viper", now: referenceNow)

        #expect(scheduler.scheduleCallCount == 0)
        #expect(scheduler.cancelledIDs == ["reminder-2"])
    }

    @Test func deniedAuthorization_savesStillSucceedAndSurfaceTheDeniedFlag() async {
        let scheduler = FakeNotificationScheduler()
        scheduler.authorizationState = .denied
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler)

        await coordinator.syncAfterSave(futureReminder(), vehicleName: nil, now: referenceNow)

        #expect(coordinator.isAuthorizationDenied)
        #expect(scheduler.scheduleCallCount == 0)
        #expect(scheduler.cancelledIDs == ["reminder-1"])
    }

    @Test func deniedFlagClearsOnceAuthorizationIsLaterGranted() async {
        let scheduler = FakeNotificationScheduler()
        scheduler.authorizationState = .denied
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler)
        await coordinator.syncAfterSave(futureReminder(), vehicleName: nil, now: referenceNow)
        #expect(coordinator.isAuthorizationDenied)

        scheduler.authorizationState = .authorized
        await coordinator.syncAfterSave(futureReminder(), vehicleName: nil, now: referenceNow)

        #expect(coordinator.isAuthorizationDenied == false)
        #expect(scheduler.scheduleCallCount == 1)
    }

    @Test func planIsAPureFunctionOfReminderState() {
        let plan = ReminderNotificationCoordinator.plan(
            for: futureReminder(),
            vehicleName: "Viper",
            now: referenceNow
        )
        #expect(plan?.id == "reminder-1")
        #expect(plan?.body == "Due for Viper")

        let odometerOnly = Reminder(id: "reminder-3", vehicleId: "vehicle-1", title: "Brake fluid", dueMileage: 1)
        #expect(ReminderNotificationCoordinator.plan(for: odometerOnly, vehicleName: nil, now: referenceNow) == nil)
    }
}
