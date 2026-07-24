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
            Button("Save Reminder") {
                isEditingField = false
                Task { didSave = await viewModel.save(vehicleId: vehicle.id) }
            }
            .accessibilityIdentifier("reminder.form.save")
            if didSave {
                Text("Reminder saved")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.success)
                    .accessibilityIdentifier("reminder.form.saved")
            }
        }
    }
}

private struct ReminderConfigRow: View {
    let reminder: Reminder

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
        .accessibilityIdentifier("reminder.row.\(reminder.id)")
    }
}
