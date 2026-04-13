import SwiftUI

struct VehicleFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = VehicleFormViewModel()

    var body: some View {
        BottomSheet(title: "Add Vehicle") {
            TextField("Nickname", text: $viewModel.nickname).textFieldStyle(.roundedBorder)
            TextField("Make", text: $viewModel.make).textFieldStyle(.roundedBorder)
            TextField("Model", text: $viewModel.model).textFieldStyle(.roundedBorder)
            TextField("Year", text: $viewModel.year).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            TextField("Current odometer", text: $viewModel.currentOdometer)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            Picker("Fuel type", selection: $viewModel.fuelType) {
                ForEach(FuelType.allCases, id: \.self) { type in
                    Text(type.rawValue.replacingOccurrences(of: "_", with: " ")).tag(type)
                }
            }
            if let error = viewModel.error {
                ErrorBanner(error: error)
            }
            PrimaryButton(title: "Save Vehicle") {
                Task {
                    if await viewModel.save() {
                        await appState.refreshVehicles()
                        dismiss()
                    }
                }
            }
        }
    }
}
