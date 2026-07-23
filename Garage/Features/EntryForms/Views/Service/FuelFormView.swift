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
                    Text(grade.displayName).tag(grade)
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
        let gallonsValue = Double(gallons) ?? 0
        let currentOdometer = Int(form.odometerReading) ?? 0
        let mpg = await Self.mpg(vehicleId: vehicle.id, currentOdometer: currentOdometer, gallons: gallonsValue)
        let details = FuelEntry(
            gallons: gallonsValue,
            pricePerGallon: Double(pricePerGallon) ?? 0,
            totalCost: Double(totalCost) ?? 0,
            stationName: stationName.isEmpty ? nil : stationName,
            fuelGrade: fuelGrade,
            calculatedMPG: mpg
        )
        return await form.save(vehicle: vehicle, entryType: .fuel, details: details)
    }

    /// The newest existing fuel entry is the previous fill-up by construction: odometer readings
    /// are validated non-decreasing across every entry type (Validators.odometer), so whatever
    /// EntryService.lastFuelEntry returns already has a lower odometer than the one being saved.
    /// Nil on a first-ever fill-up (no prior fuel entry) or a fetch failure — MPG is best-effort.
    private static func mpg(vehicleId: String, currentOdometer: Int, gallons: Double) async -> Double? {
        guard let previous = try? await EntryService.shared.lastFuelEntry(vehicleId: vehicleId) else { return nil }
        return FuelEntry.calculatedMPG(
            currentOdometer: currentOdometer, previousOdometer: previous.odometerReading, gallons: gallons
        )
    }
}
