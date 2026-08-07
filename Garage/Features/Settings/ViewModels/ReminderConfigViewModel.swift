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

    var title = ReminderConfigViewModel.defaultTitle
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
    /// Non-nil while the form is editing an existing reminder instead of creating a new one.
    /// Holds the WHOLE stored reminder rather than just its id, because `save()` has to carry
    /// through every field this form does not show (createdAt, completedAt, notes, entryType,
    /// repeatIntervalMiles) — re-constructing a `Reminder` from the form alone would silently
    /// blank all five, and the service `save` is an id-keyed upsert, so that loss would be
    /// written straight over the stored document.
    private(set) var editingReminder: Reminder?
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

    var isEditing: Bool { editingReminder != nil }

    /// Switches the form from create to edit and prefills every field `save()` writes, so what
    /// the user sees is exactly what is stored. Re-entrant: tapping a second reminder while
    /// editing a first simply retargets the form.
    func beginEditing(_ reminder: Reminder) {
        editingReminder = reminder
        title = reminder.title
        dueMileage = reminder.dueMileage.map(String.init) ?? ""
        dueMonths = reminder.repeatIntervalMonths.map(String.init) ?? ""
        hasDueDate = reminder.dueDate != nil
        // A date-less reminder keeps the create-mode default rather than an arbitrary instant,
        // so turning the toggle ON mid-edit still lands on a genuinely future date.
        dueDate = reminder.dueDate ?? Self.defaultDueDate()
    }

    /// Leaves edit mode and returns the form to its create-mode defaults. Also the post-edit-save
    /// reset: leaving the edited values in place would arm the next Save to create a near
    /// duplicate of the reminder just updated.
    func cancelEdit() {
        editingReminder = nil
        title = Self.defaultTitle
        dueMileage = ""
        dueMonths = ""
        hasDueDate = false
        dueDate = Self.defaultDueDate()
    }

    /// `currentOdometer` is cheap-only, same contract as `vehicleName`: pass it when the caller
    /// already holds the `Vehicle`. It is what turns the create form's single mileage input into a
    /// repeat INTERVAL (see `repeatInterval`); nil simply means no interval is derivable.
    func save(vehicleId: String, vehicleName: String? = nil, currentOdometer: Int? = nil) async -> Bool {
        let wasEditing = isEditing
        do {
            let reminder = reminderToSave(vehicleId: vehicleId, currentOdometer: currentOdometer)
            try await reminderService.save(reminder, vehicleName: vehicleName)
            // An edit is not a creation: reporting it as `reminder_created` would inflate that
            // count with re-saves, and this batch adds no new event names, so edits report
            // nothing. The create path is unchanged.
            if !wasEditing {
                analytics.track(.reminderCreated)
            } else {
                cancelEdit()
            }
            error = nil
            await load(vehicleId: vehicleId)
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }

    /// Edit mode starts from the STORED reminder and overwrites only the four fields this form
    /// actually shows, which is what preserves its id — the service `save` writes
    /// `.document(reminder.id)`, so the same id updates in place instead of adding a row.
    ///
    /// `repeatIntervalMiles` is deliberately NOT re-derived on edit even though create derives it
    /// (there is only one mileage input). For a repeat successor
    /// (`ReminderService.scheduleSuccessorIfRepeating`) or a seeded reminder the two hold
    /// genuinely different numbers — e.g. due at 20,620 mi, repeating every 2,500 — so re-deriving
    /// the interval during an unrelated title edit would quietly destroy the repeat cadence.
    private func reminderToSave(vehicleId: String, currentOdometer: Int? = nil) -> Reminder {
        let resolvedDueDate = hasDueDate ? Self.canonicalDueInstant(for: dueDate) : nil
        guard var edited = editingReminder else {
            return Reminder(
                id: UUID().uuidString,
                vehicleId: vehicleId,
                title: title,
                dueDate: resolvedDueDate,
                dueMileage: Int(dueMileage),
                repeatIntervalMonths: Int(dueMonths),
                repeatIntervalMiles: Self.repeatInterval(dueMileage: Int(dueMileage), currentOdometer: currentOdometer),
                isProFeature: false
            )
        }
        edited.title = title
        edited.dueDate = resolvedDueDate
        // A non-positive entry is no due mileage at all (cross-check finding): `Int("0")` is 0,
        // not nil, so without this a "0" typed to un-track mileage would skip the interval
        // cleanup below and leave a stale repeat cadence alive in the stored document.
        edited.dueMileage = Int(dueMileage).flatMap { $0 > 0 ? $0 : nil }
        edited.repeatIntervalMonths = Int(dueMonths)
        // Clearing the mileage field ends mileage tracking outright, interval included: create
        // derives `repeatIntervalMiles` from this same input, so a nil mileage can never leave a
        // live interval behind even though their VALUES differ (successors carry a rolled-forward
        // due mileage). Keeping a hidden interval here would resurface a years-stale cadence the
        // first time a mileage is re-added and completed.
        if edited.dueMileage == nil { edited.repeatIntervalMiles = nil }
        return edited
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
            // Deleting the reminder the form is currently editing has to leave edit mode: the
            // save path is an id-keyed upsert, so a later Save would otherwise resurrect the
            // document the user just deleted.
            if editingReminder?.id == reminder.id {
                cancelEdit()
            }
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
            // Same staleness trap as delete(): the held copy still says "outstanding", so an
            // edit saved afterwards would write completedAt back to nil and un-complete it.
            if editingReminder?.id == reminder.id {
                editingReminder?.completedAt = .now
            }
            analytics.track(.reminderCompleted)
            // Attributes this completion to a recent notification open (7-day window), closing
            // the notif_scheduled → opened → task_completed funnel. No-op when the open didn't
            // come from a notification.
            NotificationFunnelService.shared.recordTaskCompletionIfAttributed(.reminderDue)
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }

    /// The create-mode title placeholder. A single constant so the property default and
    /// `cancelEdit`'s reset cannot drift apart.
    static let defaultTitle = "Oil change"

    /// The mileage the created reminder should REPEAT on: how far its due mileage sits ahead of
    /// the odometer today. The create form has a single mileage input, and seeding the interval
    /// with that absolute reading was a live defect — `ReminderService.scheduleSuccessorIfRepeating`
    /// computes `successor.dueMileage = dueMileage + repeatIntervalMiles`, so completing a
    /// reminder due at 97,300 minted one due at 194,600.
    ///
    /// Nil whenever no interval is derivable: an odometer of 0 means "not recorded" rather than
    /// mile zero (same rule as `MaintenanceSchedule.status`), and a due mileage at or below the
    /// current reading has no forward distance. Nil is the safe seed — a successor that keeps the
    /// same due mileage is stale but visible, one at double the odometer is fabricated. Internal
    /// and pure, exposed for direct unit testing.
    static func repeatInterval(dueMileage: Int?, currentOdometer: Int?) -> Int? {
        guard let dueMileage, let currentOdometer,
              currentOdometer > 0, dueMileage > currentOdometer else { return nil }
        return dueMileage - currentOdometer
    }

}
