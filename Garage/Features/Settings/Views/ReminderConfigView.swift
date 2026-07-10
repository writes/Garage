import SwiftUI

struct ReminderConfigView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ReminderConfigViewModel()
    @State private var didSave = false
    @FocusState private var isEditingField: Bool

    var body: some View {
        Form {
            if !appState.isPro {
                ProGateView(
                    title: "Reminders are part of Pro",
                    message: "Mileage and time-based reminders help keep maintenance on schedule.",
                    actionIdentifier: "reminder.gate.cta"
                ) {
                    router.present(.subscription)
                }
            } else {
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
                    guard let vehicleId = appState.currentVehicle?.id else { return }
                    Task { didSave = await viewModel.save(vehicleId: vehicleId) }
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
        .navigationTitle("Reminders")
    }
}
