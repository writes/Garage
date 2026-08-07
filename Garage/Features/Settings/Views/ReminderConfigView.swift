import SwiftUI

struct ReminderConfigView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ReminderConfigViewModel()
    @State private var didSave = false
    /// The .ics file built by the most recent "Add to Calendar" tap, if any. View-local rather
    /// than view-model state: it is a temp file bound to this screen's lifetime, discarded on
    /// disappear, and never part of the reminder record. `internal` (not `private`) only because
    /// the calendar affordance lives in ReminderConfigView+Calendar.swift, split out to stay under
    /// the file cap.
    @State var calendarArtifact: ReminderCalendarArtifact?
    /// The reminder whose export failed, so the message appears under THAT row rather than under
    /// every row in the list.
    @State var calendarExportFailedID: String?
    @FocusState private var isEditingField: Bool
#if DEBUG
    @State private var demoStore = DemoSessionStore.shared
#endif

    var body: some View {
        Group {
            // Audit finding (mirrors ExportView.swift's currentVehicle == nil pattern): the
            // create form used to render even with no vehicle, so Save silently no-op'd on
            // `guard let vehicleId = appState.currentVehicle?.id else { return }`.
            if let vehicle = appState.currentVehicle {
                reminderForm(for: vehicle)
            } else {
                EmptyStateView(
                    title: "Add a vehicle first",
                    message: "Reminders are created per vehicle.",
                    systemImage: "car"
                )
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Reminders")
    }

    private func reminderForm(for vehicle: Vehicle) -> some View {
        Form {
            if !viewModel.reminders.isEmpty {
                existingRemindersSection
            }
            newReminderSection(for: vehicle)
            if let error = viewModel.error {
                ErrorBanner(error: error)
                    .accessibilityIdentifier("reminder.error")
            }
        }
        .task(id: vehicle.id) {
            sweepAbandonedCalendarFiles()
            await viewModel.load(vehicleId: vehicle.id)
        }
        .onDisappear { discardCalendarArtifact() }
        // Review finding: this view/VM instance is reused across vehicle switches (the .task
        // above just reloads `reminders` for the new vehicle), so a stale "Reminder saved"/
        // notifications-off hint from the PREVIOUS vehicle stayed visible after switching.
        // An in-progress edit belongs to the PREVIOUS vehicle's reminder; carrying it across a
        // switch would let Save write that other vehicle's document from this screen.
        .onChange(of: vehicle.id) { _, _ in
            didSave = false
            viewModel.cancelEdit()
            // The pending .ics belongs to the PREVIOUS vehicle's reminder; leaving it live would
            // offer the wrong car's event under a row of this one's.
            discardCalendarArtifact()
        }
#if DEBUG
        .task(id: demoStore.revision) { await viewModel.load(vehicleId: vehicle.id) }
#endif
    }

    private var existingRemindersSection: some View {
        Section("Your Reminders") {
            ForEach(viewModel.reminders) { reminder in
                editableRow(reminder)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            discardCalendarArtifact()
                            Task { await viewModel.delete(reminder) }
                        }
                        .accessibilityIdentifier("reminder.delete.\(reminder.id)")
                        // Tapping the row edits too; the swipe action exists because a
                        // tappable row in a settings list is not self-advertising.
                        Button("Edit") { beginEditing(reminder) }
                            .tint(Theme.Colors.primary)
                            .accessibilityIdentifier("reminder.edit.\(reminder.id)")
                        calendarButton(for: reminder)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if reminder.completedAt == nil {
                            Button("Mark Done") {
                                discardCalendarArtifact()
                                Task {
                                    await viewModel.markCompleted(reminder)
                                    // markCompleted returns Void and reports through `error`,
                                    // which it clears on success — so that IS the success signal.
                                    if viewModel.error == nil { FeedbackCenter.shared.fire(.success) }
                                }
                            }
                            .tint(Theme.Colors.success)
                            .accessibilityIdentifier("reminder.complete.\(reminder.id)")
                        }
                    }
                calendarShareRow(for: reminder)
            }
        }
    }

    /// Tap-to-edit. `.plain` keeps the row looking like a list row rather than tinted button
    /// text, and the button (not an `onTapGesture`) is what gives VoiceOver an activatable
    /// element with a button trait.
    private func editableRow(_ reminder: Reminder) -> some View {
        Button {
            beginEditing(reminder)
        } label: {
            ReminderConfigRow(reminder: reminder)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reminder.row.edit.\(reminder.id)")
        .accessibilityHint("Edits this reminder")
    }

    private func beginEditing(_ reminder: Reminder) {
        isEditingField = false
        // A "Reminder saved" line left over from a previous create would otherwise read as if
        // this edit had already been saved.
        didSave = false
        // Any reminder mutation retires the pending .ics: an edit that moves the due date would
        // otherwise leave a share row handing off the OLD event (cross-check finding). Cheap to
        // rebuild, impossible to hand off stale.
        discardCalendarArtifact()
        viewModel.beginEditing(reminder)
    }

    /// "Due mileage" is the form's first field and the date toggle defaults OFF, so the natural
    /// path through this form produces a mileage-only reminder — and
    /// `ReminderNotificationCoordinator.plan` returns nil without a `dueDate`, so nothing is ever
    /// scheduled. The form still said "Reminder saved", meaning a user setting "Oil change at
    /// 95,000 mi" was silently promised an alert that could never arrive.
    ///
    /// A local notification genuinely cannot fire on an odometer reading — the phone has no idea
    /// when the mileage is reached — so the honest fix is to say so rather than fake it.
    @ViewBuilder
    private var dueDateRow: some View {
        if viewModel.hasDueDate {
            DatePicker(
                "Due date", selection: $viewModel.dueDate, in: Date.now..., displayedComponents: .date
            )
                .datePickerStyle(.compact)
                .accessibilityIdentifier("reminder.form.dueDate")
        } else {
            Text(
                """
                Mileage reminders appear in this list but can't send an alert — \
                your phone has no way to know when you reach the mileage. \
                Add a date to get a notification.
                """
            )
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .accessibilityIdentifier("reminder.form.mileageOnlyHint")
        }
    }

    /// One-tap due dates, sitting between the toggle and the picker they fill in so the tap and its
    /// effect stay adjacent. `.bordered` is load-bearing, not cosmetic: several default-style
    /// buttons in a single Form row make the WHOLE row tappable, and one tap then fires every one.
    @ViewBuilder
    private var dueDatePresetRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(ReminderDueDatePreset.allCases) { preset in
                Button(preset.label) {
                    // The same three retirements beginEditing/save do: the numberpad would cover
                    // the picker this reveals, a leftover "Reminder saved" would read as covering
                    // this change, and the pending .ics carries the due date this tap just moved.
                    isEditingField = false
                    didSave = false
                    discardCalendarArtifact()
                    viewModel.applyDueDatePreset(preset)
                }
                .buttonStyle(.bordered)
                .tint(Theme.Colors.primary)
                .accessibilityIdentifier("reminder.form.preset.months.\(preset.months)")
                .accessibilityLabel("Remind me \(preset.label.lowercased())")
            }
        }
    }

    private func newReminderSection(for vehicle: Vehicle) -> some View {
        Section(viewModel.isEditing ? "Edit Reminder" : "New Reminder") {
            TextField("Reminder title", text: $viewModel.title)
                .accessibilityIdentifier("reminder.form.title")
                .focused($isEditingField)
            TextField("Due mileage", text: $viewModel.dueMileage)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("reminder.form.mileage")
                .focused($isEditingField)
            TextField("Repeat every X months", text: $viewModel.dueMonths)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("reminder.form.months")
                .focused($isEditingField)
            Toggle("Remind me on a date", isOn: $viewModel.hasDueDate)
                .accessibilityIdentifier("reminder.form.hasDueDate")
            dueDatePresetRow
            dueDateRow
            saveRow(for: vehicle)
            if didSave {
                Text("Reminder saved")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.success)
                    .accessibilityIdentifier("reminder.form.saved")
            }
            if didSave && viewModel.hasDueDate && viewModel.isNotificationAuthorizationDenied {
                Text("Notifications are off, so this reminder won't send an alert. Enable them in Settings.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("reminder.form.notificationsHint")
            }
        }
    }

    /// Save keeps its identifier in both modes — it is the same commit action, and the edit
    /// path routes through the same `viewModel.save` (an id-keyed upsert, so an edit updates
    /// the existing document rather than adding one).
    @ViewBuilder
    private func saveRow(for vehicle: Vehicle) -> some View {
        Button(viewModel.isEditing ? "Save Changes" : "Save Reminder") {
            isEditingField = false
            // Covers the artifact built WHILE editing (entering edit already discards): a save
            // that moves the due date must not leave a share row offering the old event.
            discardCalendarArtifact()
            Task {
                didSave = await viewModel.save(
                    vehicleId: vehicle.id, vehicleName: vehicle.displayName, currentOdometer: vehicle.currentOdometer
                )
                if didSave { FeedbackCenter.shared.fire(.success) }
            }
        }
        .accessibilityIdentifier("reminder.form.save")
        if viewModel.isEditing {
            Button("Cancel", role: .cancel) {
                isEditingField = false
                didSave = false
                viewModel.cancelEdit()
            }
            .accessibilityIdentifier("reminder.form.cancelEdit")
        }
    }
}
