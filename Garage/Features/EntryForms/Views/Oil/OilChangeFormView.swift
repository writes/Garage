import SwiftUI

struct OilChangeFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var oilBrand = ""
    @State private var oilGrade = ""
    @State private var quantityQuarts = ""
    @State private var filterBrand = ""

    var body: some View {
        EntryFormScaffold(
            title: "Oil Change", viewModel: form, onSave: save, onEditEntry: seed,
            onAIPrefill: seedProposal
        ) {
            TextField("Oil brand", text: $oilBrand).textFieldStyle(.roundedBorder)
            TextField("Oil grade", text: $oilGrade).textFieldStyle(.roundedBorder)
            TextField("Quantity (quarts)", text: $quantityQuarts)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField("Filter brand", text: $filterBrand).textFieldStyle(.roundedBorder)
        }
    }

    /// Typed-extraction seeding (spec rev 3 §3). Plain strings land only when the proposal has a
    /// non-empty value; quantity mirrors `seed(from:)`'s own costString formatting below.
    private func seedProposal(_ details: TypedProposalDetails) {
        if let value = details.brand, !value.isEmpty {
            oilBrand = value
        }
        if let value = details.oilGrade, !value.isEmpty {
            oilGrade = value
        }
        if let quarts = details.quantityQuarts, quarts > 0 {
            quantityQuarts = EntryFormViewModel.costString(quarts)
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
