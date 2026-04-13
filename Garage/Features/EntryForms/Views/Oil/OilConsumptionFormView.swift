import SwiftUI

struct OilConsumptionFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var amountAdded = ""
    @State private var oilBrand = ""
    @State private var oilGrade = ""

    var body: some View {
        EntryFormScaffold(title: "Oil Consumption", viewModel: form, onSave: save) {
            TextField("Quarts added", text: $amountAdded).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            TextField("Oil brand", text: $oilBrand).textFieldStyle(.roundedBorder)
            TextField("Oil grade", text: $oilGrade).textFieldStyle(.roundedBorder)
        }
        .task { await prepare() }
    }

    private func prepare() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await form.prepare(vehicleId: vehicleId)
    }

    private func save() async -> Bool {
        guard let vehicle = appState.currentVehicle else { return false }
        let details = OilConsumptionEntry(
            amountAddedQuarts: Double(amountAdded) ?? 0,
            runningTotalSinceLastChange: nil,
            oilBrand: oilBrand.isEmpty ? nil : oilBrand,
            oilGrade: oilGrade.isEmpty ? nil : oilGrade
        )
        return await form.save(vehicle: vehicle, entryType: .oilConsumption, details: details)
    }
}
