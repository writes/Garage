import SwiftUI

struct FuelFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var gallons = ""
    @State private var pricePerGallon = ""
    @State private var totalCost = ""
    @State private var stationName = ""
    @State private var fuelGrade: FuelType = .premium93

    var body: some View {
        EntryFormScaffold(title: "Fuel Fill-up", viewModel: form, onSave: save) {
            TextField("Gallons", text: $gallons)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fuel.form.gallons")
            TextField("Price per gallon", text: $pricePerGallon)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fuel.form.price")
            TextField("Total cost", text: $totalCost)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fuel.form.total")
            TextField("Station name", text: $stationName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fuel.form.station")
            Picker("Fuel grade", selection: $fuelGrade) {
                ForEach(FuelType.allCases, id: \.self) { grade in
                    Text(grade.rawValue.replacingOccurrences(of: "_", with: " ")).tag(grade)
                }
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await form.prepare(vehicleId: vehicleId)
    }

    private func save() async -> Bool {
        guard let vehicle = appState.currentVehicle else { return false }
        let details = FuelEntry(
            gallons: Double(gallons) ?? 0,
            pricePerGallon: Double(pricePerGallon) ?? 0,
            totalCost: Double(totalCost) ?? 0,
            stationName: stationName.isEmpty ? nil : stationName,
            fuelGrade: fuelGrade,
            calculatedMPG: nil
        )
        return await form.save(vehicle: vehicle, entryType: .fuel, details: details)
    }
}
