import SwiftUI

struct VehicleFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = VehicleFormViewModel()

    var body: some View {
        BottomSheet(title: "Add Vehicle") {
            TextField("Nickname", text: $viewModel.nickname)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("vehicle.form.nickname")
            TextField("Make", text: $viewModel.make)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("vehicle.form.make")
            TextField("Model", text: $viewModel.model)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("vehicle.form.model")
            TextField("Year", text: $viewModel.year)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("vehicle.form.year")
            TextField("Current odometer", text: $viewModel.currentOdometer)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("vehicle.form.odometer")
            Picker("Fuel type", selection: $viewModel.fuelType) {
                ForEach(FuelType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            if let error = viewModel.error {
                ErrorBanner(error: error)
                    .accessibilityIdentifier("vehicle.form.error")
            }
            PrimaryButton(title: "Save Vehicle") {
                Task {
                    if await viewModel.save() {
                        await appState.refreshVehicles()
                        // Fired right before dismiss(), AFTER the refresh await: buzzing while
                        // the sheet visibly sits waiting on the network desyncs touch from
                        // sight (cross-check). The counter lives on FeedbackCenter, which
                        // outlives this sheet, so teardown cannot eat it.
                        FeedbackCenter.shared.fire(.success)
                        dismiss()
                    }
                }
            }
            .disabled(viewModel.isSaving)
            .accessibilityIdentifier("vehicle.form.save")
        }
    }
}
