import SwiftUI

struct OilAnalysisFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var labName = "Blackstone"
    @State private var viscosity = ""
    @State private var milesOnOil = ""
    @State private var iron = ""
    @State private var aluminum = ""
    @State private var recommendation = ""

    var body: some View {
        EntryFormScaffold(title: "Oil Analysis", viewModel: form, onSave: save) {
            TextField("Lab name", text: $labName).textFieldStyle(.roundedBorder)
            TextField("Viscosity", text: $viscosity).textFieldStyle(.roundedBorder)
            TextField("Miles on oil", text: $milesOnOil).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            TextField("Iron (ppm)", text: $iron).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            TextField("Aluminum (ppm)", text: $aluminum).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            TextField("Lab recommendation", text: $recommendation).textFieldStyle(.roundedBorder)
        }
        .task { await prepare() }
    }

    private func prepare() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await form.prepare(vehicleId: vehicleId)
    }

    private func save() async -> Bool {
        guard let vehicle = appState.currentVehicle else { return false }
        let details = OilAnalysisEntry(
            labName: labName,
            pdfPath: nil,
            aluminum: Double(aluminum),
            chromium: nil,
            iron: Double(iron),
            copper: nil,
            lead: nil,
            tin: nil,
            molybdenum: nil,
            nickel: nil,
            manganese: nil,
            silver: nil,
            titanium: nil,
            silicon: nil,
            sodium: nil,
            potassium: nil,
            viscosity: viscosity.isEmpty ? nil : viscosity,
            insolubles: nil,
            milesOnOil: Int(milesOnOil),
            labRecommendation: recommendation.isEmpty ? nil : recommendation
        )
        return await form.save(vehicle: vehicle, entryType: .oilAnalysis, details: details)
    }
}
