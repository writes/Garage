import SwiftUI

struct ReminderConfigView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ReminderConfigViewModel()
    @State private var didSave = false
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
        .task(id: vehicle.id) { await viewModel.load(vehicleId: vehicle.id) }
        // Review finding: this view/VM instance is reused across vehicle switches (the .task
        // above just reloads `reminders` for the new vehicle), so a stale "Reminder saved"/
        // notifications-off hint from the PREVIOUS vehicle stayed visible after switching.
        .onChange(of: vehicle.id) { _, _ in didSave = false }
#if DEBUG
        .task(id: demoStore.revision) { await viewModel.load(vehicleId: vehicle.id) }
#endif
    }

    private var existingRemindersSection: some View {
        Section("Your Reminders") {
            ForEach(viewModel.reminders) { reminder in
                ReminderConfigRow(reminder: reminder)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.delete(reminder) }
                        }
                        .accessibilityIdentifier("reminder.delete.\(reminder.id)")
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if reminder.completedAt == nil {
                            Button("Mark Done") {
                                Task { await viewModel.markCompleted(reminder) }
                            }
                            .tint(Theme.Colors.success)
                            .accessibilityIdentifier("reminder.complete.\(reminder.id)")
                        }
                    }
            }
        }
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

    private func newReminderSection(for vehicle: Vehicle) -> some View {
        Section("New Reminder") {
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
            dueDateRow
            Button("Save Reminder") {
                isEditingField = false
                Task { didSave = await viewModel.save(vehicleId: vehicle.id, vehicleName: vehicle.displayName) }
            }
            .accessibilityIdentifier("reminder.form.save")
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
}

private struct ReminderConfigRow: View {
    let reminder: Reminder

    private var statusText: String {
        var parts: [String] = [reminder.completedAt != nil ? "Done" : "Due"]
        if let dueMileage = reminder.dueMileage {
            parts.append("at \(dueMileage.formatted()) mi")
        }
        if let dueDate = reminder.dueDate {
            parts.append(dueDate.shortDisplay)
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(reminder.title)
                    .font(Theme.Typography.headline)
                    .strikethrough(reminder.completedAt != nil)
                if reminder.completedAt != nil {
                    Text("Done")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.success)
                }
            }
            if let dueMileage = reminder.dueMileage {
                Text("Due at \(dueMileage.formatted()) mi")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if let dueDate = reminder.dueDate {
                Text(dueDate.shortDisplay)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reminder.title)
        .accessibilityValue(statusText)
        .accessibilityIdentifier("reminder.row.\(reminder.id)")
    }
}
