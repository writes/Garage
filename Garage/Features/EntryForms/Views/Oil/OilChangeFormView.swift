import SwiftUI

struct OilChangeFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var oilBrand = ""
    @State private var oilGrade = ""
    @State private var quantityQuarts = ""
    @State private var filterBrand = ""

    var body: some View {
        EntryFormScaffold(title: "Oil Change", viewModel: form, onSave: save, onEditEntry: seed) {
            TextField("Oil brand", text: $oilBrand).textFieldStyle(.roundedBorder)
            TextField("Oil grade", text: $oilGrade).textFieldStyle(.roundedBorder)
            TextField("Quantity (quarts)", text: $quantityQuarts)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField("Filter brand", text: $filterBrand).textFieldStyle(.roundedBorder)
        }
    }

    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: OilChangeEntry.self) else { return }
        oilBrand = details.oilBrand
        oilGrade = details.oilGrade
        quantityQuarts = details.quantityQuarts > 0 ? EntryFormViewModel.costString(details.quantityQuarts) : ""
        filterBrand = details.filterBrand ?? ""
    }

    private func save() async -> Bool {
        guard let vehicle = appState.currentVehicle else { return false }
        let details = OilChangeEntry(
            oilBrand: oilBrand,
            oilGrade: oilGrade,
            quantityQuarts: Double(quantityQuarts) ?? 0,
            filterBrand: filterBrand.isEmpty ? nil : filterBrand
        )
        return await form.save(vehicle: vehicle, entryType: .oilChange, details: details)
    }
}
