import Foundation
import Testing
@testable import Garage

/// Tester-requested reminder editing: before this, the only way to change a reminder was
/// delete-and-recreate, which minted a new id and dropped createdAt (and, with it, whatever the
/// form does not show). These pin the edit contract against the hermetic ReminderService seam —
/// the same document id is rewritten, never a second one added.
@MainActor
struct ReminderEditingTests {
    /// Deliberately carries a value in every field, including the four the form never shows
    /// (entryType, notes, createdAt, repeatIntervalMiles) — those are what an edit must preserve.
    private static let existing = Reminder(
        id: "reminder-1", vehicleId: "vehicle-1", title: "Oil change", entryType: .oilChange,
        dueDate: Date(timeIntervalSince1970: 2_000_000_000), dueMileage: 20_620,
        repeatIntervalMonths: 6, repeatIntervalMiles: 2_500, notes: "Track-use interval",
        isProFeature: false, createdAt: Date(timeIntervalSince1970: 1_000_000_000)
    )

    @MainActor
    private struct Harness {
        let viewModel: ReminderConfigViewModel
        let service: ReminderService
        let scheduler: FakeEditNotificationScheduler
        let analytics: AnalyticsSpy

        func stored() async throws -> [Reminder] {
            try await service.fetchAll(vehicleId: "vehicle-1")
        }
    }

    private func makeHarness(reminders: [Reminder] = [ReminderEditingTests.existing]) -> Harness {
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let scheduler = FakeEditNotificationScheduler()
        let coordinator = ReminderNotificationCoordinator(scheduler: scheduler)
        let service = ReminderService(testReminders: reminders, notificationCoordinator: coordinator)
        let viewModel = ReminderConfigViewModel(
            reminderService: service, notificationCoordinator: coordinator, analytics: analytics
        )
        return Harness(viewModel: viewModel, service: service, scheduler: scheduler, analytics: analytics)
    }

    // MARK: - Entering and leaving edit mode

    @Test func beginEditing_prefillsEveryFieldSaveWrites() {
        let harness = makeHarness()

        harness.viewModel.beginEditing(Self.existing)

        #expect(harness.viewModel.isEditing)
        #expect(harness.viewModel.title == "Oil change")
        #expect(harness.viewModel.dueMileage == "20620")
        #expect(harness.viewModel.dueMonths == "6")
        #expect(harness.viewModel.hasDueDate)
        #expect(harness.viewModel.dueDate == Date(timeIntervalSince1970: 2_000_000_000))
    }

    @Test func beginEditing_dateLessReminder_leavesTheToggleOffAndKeepsAFutureDefaultDate() {
        let mileageOnly = Reminder(id: "r-mileage", vehicleId: "vehicle-1", title: "Rotate tires", dueMileage: 5_000)
        let harness = makeHarness(reminders: [mileageOnly])

        harness.viewModel.beginEditing(mileageOnly)

        #expect(!harness.viewModel.hasDueDate)
        #expect(harness.viewModel.dueMonths.isEmpty)
        #expect(harness.viewModel.dueDate > .now)
    }

    @Test func cancelEdit_restoresCreateModeAndClearsThePrefill() {
        let harness = makeHarness()
        harness.viewModel.beginEditing(Self.existing)

        harness.viewModel.cancelEdit()

        #expect(!harness.viewModel.isEditing)
        #expect(harness.viewModel.title == ReminderConfigViewModel.defaultTitle)
        #expect(harness.viewModel.dueMileage.isEmpty)
        #expect(harness.viewModel.dueMonths.isEmpty)
        #expect(!harness.viewModel.hasDueDate)
        #expect(harness.viewModel.dueDate > .now)
    }

    // MARK: - Saving an edit

    /// The point of the feature: the SAME document is rewritten, so the list still holds one
    /// reminder and its id survives — delete-and-recreate minted a new one.
    @Test func save_whileEditing_rewritesTheSameDocumentInsteadOfAddingOne() async throws {
        let harness = makeHarness()
        harness.viewModel.beginEditing(Self.existing)
        harness.viewModel.title = "Oil change + filter"
        harness.viewModel.dueMileage = "22000"
        harness.viewModel.dueMonths = "12"

        let didSave = await harness.viewModel.save(vehicleId: "vehicle-1")

        #expect(didSave)
        let all = try await harness.stored()
        #expect(all.count == 1)
        let updated = try #require(all.first)
        #expect(updated.id == "reminder-1")
        #expect(updated.title == "Oil change + filter")
        #expect(updated.dueMileage == 22_000)
        #expect(updated.repeatIntervalMonths == 12)
        #expect(harness.viewModel.reminders.map(\.id) == ["reminder-1"])
    }

    /// Fields the form never shows must survive the round trip — rebuilding a `Reminder` from the
    /// form alone would blank all of them on top of the stored document.
    @Test func save_whileEditing_carriesThroughFieldsTheFormDoesNotEdit() async throws {
        let harness = makeHarness()
        harness.viewModel.beginEditing(Self.existing)
        harness.viewModel.title = "Oil change + filter"

        _ = await harness.viewModel.save(vehicleId: "vehicle-1")

        let updated = try #require(try await harness.stored().first)
        #expect(updated.createdAt == Date(timeIntervalSince1970: 1_000_000_000))
        #expect(updated.entryType == .oilChange)
        #expect(updated.notes == "Track-use interval")
        #expect(updated.vehicleId == "vehicle-1")
        // Create seeds repeatIntervalMiles from the single mileage input; an edit must NOT, or a
        // repeat successor's genuine interval (2,500 mi) gets overwritten by an absolute odometer
        // reading (20,620 mi) during an unrelated title change.
        #expect(updated.repeatIntervalMiles == 2_500)
        #expect(updated.dueMileage == 20_620)
    }

    /// The inverse of carrying the interval through: CLEARING the mileage field ends mileage
    /// tracking entirely. Without the coupling, the reminder kept a hidden repeatIntervalMiles
    /// that would resurface a years-stale cadence the first time a mileage was re-added — the
    /// Gemini cross-check's orphaned-interval finding.
    @Test func save_whileEditing_clearingTheMileageAlsoEndsTheMileageRepeatCadence() async throws {
        let harness = makeHarness()
        harness.viewModel.beginEditing(Self.existing)
        harness.viewModel.dueMileage = ""

        _ = await harness.viewModel.save(vehicleId: "vehicle-1")

        let updated = try #require(try await harness.stored().first)
        #expect(updated.dueMileage == nil)
        #expect(updated.repeatIntervalMiles == nil)
        // The date half of the reminder is untouched by clearing the mileage half — modulo the
        // canonicalization every save applies (09:00 local on the picked day).
        let canonical = ReminderConfigViewModel.canonicalDueInstant(for: Date(timeIntervalSince1970: 2_000_000_000))
        #expect(updated.dueDate == canonical)
        #expect(updated.repeatIntervalMonths == 6)
    }

    @Test func save_whileEditing_clearsEditModeAndResetsTheFormToCreateDefaults() async {
        let harness = makeHarness()
        harness.viewModel.beginEditing(Self.existing)
        harness.viewModel.title = "Oil change + filter"

        _ = await harness.viewModel.save(vehicleId: "vehicle-1")

        #expect(!harness.viewModel.isEditing)
        #expect(harness.viewModel.title == ReminderConfigViewModel.defaultTitle)
        #expect(harness.viewModel.dueMileage.isEmpty)
        #expect(harness.viewModel.dueMonths.isEmpty)
        #expect(!harness.viewModel.hasDueDate)
    }

    /// A Save after an edit must create exactly ONE new reminder: neither a silent re-save of the
    /// edited one (edit mode left armed) nor a duplicate of it (edited values left in the form).
    @Test func save_afterAnEdit_createsExactlyOneNewReminder() async throws {
        let harness = makeHarness()
        harness.viewModel.beginEditing(Self.existing)
        harness.viewModel.title = "Oil change + filter"
        _ = await harness.viewModel.save(vehicleId: "vehicle-1")

        harness.viewModel.title = "Rotate tires"
        _ = await harness.viewModel.save(vehicleId: "vehicle-1")

        let all = try await harness.stored()
        #expect(all.count == 2)
        #expect(all.contains { $0.id == "reminder-1" && $0.title == "Oil change + filter" })
        #expect(all.contains { $0.id != "reminder-1" && $0.title == "Rotate tires" })
    }

    /// An edit is not a creation: reporting one would inflate `reminder_created` with re-saves,
    /// and this batch adds no new event names.
    @Test func save_whileEditing_doesNotTrackReminderCreated() async {
        let harness = makeHarness()
        harness.viewModel.beginEditing(Self.existing)
        harness.viewModel.title = "Oil change + filter"

        _ = await harness.viewModel.save(vehicleId: "vehicle-1")

        #expect(harness.analytics.events.isEmpty)
    }

    // MARK: - Lifecycle collisions with an open edit

    /// Deleting the reminder being edited has to leave edit mode: `save` is an id-keyed upsert, so
    /// a later Save would otherwise resurrect the document the user just deleted.
    @Test func delete_ofTheReminderBeingEdited_leavesEditModeSoASaveCannotResurrectIt() async throws {
        let harness = makeHarness()
        harness.viewModel.beginEditing(Self.existing)

        await harness.viewModel.delete(Self.existing)
        _ = await harness.viewModel.save(vehicleId: "vehicle-1")

        let all = try await harness.stored()
        #expect(!all.contains { $0.id == "reminder-1" })
    }

    /// Marking the edited reminder done leaves the held copy stale ("outstanding"); saving the
    /// edit afterwards must not write completedAt back to nil and un-complete it.
    @Test func markCompleted_ofTheReminderBeingEdited_survivesASubsequentEditSave() async throws {
        let harness = makeHarness()
        harness.viewModel.beginEditing(Self.existing)

        await harness.viewModel.markCompleted(Self.existing)
        harness.viewModel.title = "Oil change + filter"
        _ = await harness.viewModel.save(vehicleId: "vehicle-1")

        let updated = try #require(try await harness.stored().first { $0.id == "reminder-1" })
        #expect(updated.completedAt != nil)
        #expect(updated.title == "Oil change + filter")
    }
}
