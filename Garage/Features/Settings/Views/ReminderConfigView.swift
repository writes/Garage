import SwiftUI

struct ReminderConfigView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ReminderConfigViewModel()

    var body: some View {
        Form {
            if !appState.isPro {
                ProGateView(
                    title: "Reminders are part of Pro",
                    message: "Mileage and time-based reminders help keep maintenance on schedule."
                ) {
                    router.present(.subscription)
                }
            } else {
                TextField("Reminder title", text: $viewModel.title)
                TextField("Due mileage", text: $viewModel.dueMileage)
                    .keyboardType(.numberPad)
                TextField("Repeat every X months", text: $viewModel.dueMonths)
                    .keyboardType(.numberPad)
                Button("Save Reminder") {
                    guard let vehicleId = appState.currentVehicle?.id else { return }
                    Task { _ = await viewModel.save(vehicleId: vehicleId) }
                }
            }
        }
        .navigationTitle("Reminders")
    }
}
