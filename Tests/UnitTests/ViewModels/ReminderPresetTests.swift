import Foundation
import Testing
@testable import Garage

@MainActor
private final class FakePresetNotificationScheduler: NotificationScheduling {
    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationState { .authorized }
    func schedule(_ request: ReminderNotificationRequest) async {}
    func cancel(id: String) {}
    func cancelAll() {}
}

/// Tester-requested "reminder timeframes": the form's one-tap due dates, plus the create-path
/// defect they make reachable in one tap — `repeatIntervalMiles` used to be seeded with the
/// ABSOLUTE due odometer, so `ReminderService.scheduleSuccessorIfRepeating` (successor.dueMileage
/// = dueMileage + repeatIntervalMiles) minted a successor at roughly double the odometer.
@MainActor
struct ReminderPresetTests {
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

    @MainActor
    private struct Harness {
        let viewModel: ReminderConfigViewModel
        let service: ReminderService

        func stored() async throws -> [Reminder] {
            try await service.fetchAll(vehicleId: "vehicle-1")
        }
    }

    private func makeHarness(reminders: [Reminder] = []) -> Harness {
        let coordinator = ReminderNotificationCoordinator(scheduler: FakePresetNotificationScheduler())
        let service = ReminderService(testReminders: reminders, notificationCoordinator: coordinator)
        let viewModel = ReminderConfigViewModel(
            reminderService: service, notificationCoordinator: coordinator, analytics: AnalyticsSpy()
        )
        return Harness(viewModel: viewModel, service: service)
    }

    // MARK: - Preset date math

    @Test func presetDueDate_landsOnNineAMLocal_NMonthsOut() throws {
        // A Tuesday at 2:30pm — the time of day must not survive into the result.
        let now = try date(year: 2026, month: 7, day: 21, hour: 14, minute: 30)
        let expected: [ReminderDueDatePreset: Date] = [
            .threeMonths: try date(year: 2026, month: 10, day: 21, hour: 9),
            .sixMonths: try date(year: 2027, month: 1, day: 21, hour: 9),
            .oneYear: try date(year: 2027, month: 7, day: 21, hour: 9)
        ]

        for preset in ReminderDueDatePreset.allCases {
            #expect(preset.dueDate(now: now, calendar: Self.calendar) == (try #require(expected[preset])))
        }
    }

    /// The presets land on exactly the shape `save()` normalizes to, so canonicalization is a
    /// fixed point — a preset can never be silently moved off the day the user tapped for.
    @Test func presetDueDate_isStrictlyFuture_and_canonicalizationIsAFixedPoint() throws {
        let now = try date(year: 2026, month: 7, day: 21, hour: 14, minute: 30)

        for preset in ReminderDueDatePreset.allCases {
            let presetDate = preset.dueDate(now: now, calendar: Self.calendar)
            let canonical = ReminderConfigViewModel.canonicalDueInstant(
                for: presetDate, now: now, calendar: Self.calendar
            )
            #expect(presetDate > now)
            #expect(canonical == presetDate)
        }
    }

    @Test func applyDueDatePreset_forcesToggleOn_andOverwritesDate() throws {
        let now = try date(year: 2026, month: 7, day: 21, hour: 14, minute: 30)
        let harness = makeHarness()
        #expect(!harness.viewModel.hasDueDate)

        harness.viewModel.applyDueDatePreset(.sixMonths, now: now, calendar: Self.calendar)

        #expect(harness.viewModel.hasDueDate)
        #expect(harness.viewModel.dueDate == (try date(year: 2027, month: 1, day: 21, hour: 9)))
    }

    /// Pins the Calendar's ACTUAL month-end behavior rather than an assumed one: Jan 31 + 3 months
    /// has no April 31 to land on, so it clamps — and the clamped date must still be future.
    @Test func applyDueDatePreset_monthEndRollover() throws {
        let now = try date(year: 2026, month: 1, day: 31, hour: 8)
        let harness = makeHarness()

        harness.viewModel.applyDueDatePreset(.threeMonths, now: now, calendar: Self.calendar)

        #expect(harness.viewModel.dueDate == (try date(year: 2026, month: 4, day: 30, hour: 9)))
        #expect(harness.viewModel.dueDate > now)
    }

    // MARK: - Create-path repeat interval

    /// The defect the presets make one tap away: a created date+repeat reminder due at 97,300 with
    /// the odometer at 92,347 repeats every 4,953 miles, not "every 97,300 miles" — which would
    /// have rolled the successor forward to 194,600.
    @Test func createSave_seedsRepeatIntervalMiles_asDelta_notAbsolute() async throws {
        let harness = makeHarness()
        harness.viewModel.dueMileage = "97300"
        harness.viewModel.dueMonths = "6"

        let didSave = await harness.viewModel.save(vehicleId: "vehicle-1", currentOdometer: 92_347)

        #expect(didSave)
        let saved = try #require(try await harness.stored().first)
        #expect(saved.dueMileage == 97_300)
        #expect(saved.repeatIntervalMiles == 4_953)
    }

    /// An odometer of 0 means "not recorded", and a due mileage at or below the current reading has
    /// no forward distance — neither yields a derivable interval.
    @Test func createSave_odometerUnrecordedOrPastDue_seedsNilInterval() async throws {
        for odometer in [0, 98_000] {
            let harness = makeHarness()
            harness.viewModel.dueMileage = "97300"

            _ = await harness.viewModel.save(vehicleId: "vehicle-1", currentOdometer: odometer)

            let saved = try #require(try await harness.stored().first)
            #expect(saved.dueMileage == 97_300)
            #expect(saved.repeatIntervalMiles == nil)
        }
    }

    /// The documented edit-path invariant ("clearing the mileage field ends mileage tracking
    /// outright, interval included") — for both ways a user clears it: emptying the field, and
    /// typing 0, which `Int(_:)` parses as a value and previously slipped past the nil-coupling
    /// cleanup, leaving a stale repeat cadence live in the stored document (cross-check finding).
    @Test func editSave_clearingDueMileage_alsoClearsRepeatIntervalMiles() async throws {
        for clearedInput in ["", "0"] {
            let existing = Reminder(
                id: "reminder-1", vehicleId: "vehicle-1", title: "Oil change", dueMileage: 20_620,
                repeatIntervalMonths: 6, repeatIntervalMiles: 2_500
            )
            let harness = makeHarness(reminders: [existing])
            harness.viewModel.beginEditing(existing)
            harness.viewModel.dueMileage = clearedInput

            _ = await harness.viewModel.save(vehicleId: "vehicle-1", currentOdometer: 18_000)

            let updated = try #require(try await harness.stored().first)
            #expect(updated.dueMileage == nil)
            #expect(updated.repeatIntervalMiles == nil)
        }
    }

    /// The odometer the create path now derives from must NOT leak into the edit branch: a stored
    /// interval of 2,500 mi survives an unrelated title edit, exactly as before.
    @Test func editSave_stillPreservesStoredRepeatIntervalMiles() async throws {
        let existing = Reminder(
            id: "reminder-1", vehicleId: "vehicle-1", title: "Oil change", dueMileage: 20_620,
            repeatIntervalMonths: 6, repeatIntervalMiles: 2_500
        )
        let harness = makeHarness(reminders: [existing])
        harness.viewModel.beginEditing(existing)
        harness.viewModel.title = "Oil change + filter"

        _ = await harness.viewModel.save(vehicleId: "vehicle-1", currentOdometer: 18_000)

        let updated = try #require(try await harness.stored().first)
        #expect(updated.title == "Oil change + filter")
        #expect(updated.dueMileage == 20_620)
        #expect(updated.repeatIntervalMiles == 2_500)
    }
}
