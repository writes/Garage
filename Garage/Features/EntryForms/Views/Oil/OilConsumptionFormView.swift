import SwiftUI

struct OilConsumptionFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var amountAdded = ""
    @State private var oilBrand = ""
    @State private var oilGrade = ""

    var body: some View {
        EntryFormScaffold(
            title: "Oil Consumption", viewModel: form, onSave: save, onEditEntry: seed,
            onAIPrefill: seedProposal
        ) {
            TextField("Quarts added", text: $amountAdded).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            TextField("Oil brand", text: $oilBrand).textFieldStyle(.roundedBorder)
            TextField("Oil grade", text: $oilGrade).textFieldStyle(.roundedBorder)
        }
    }

    /// Typed-extraction seeding (spec rev 3 §3). `quantityQuarts` maps onto this form's own
    /// amount-added field, formatted the same way `seed(from:)` formats it below.
    private func seedProposal(_ details: TypedProposalDetails) {
        if let quarts = details.quantityQuarts, quarts > 0 {
            amountAdded = EntryFormViewModel.costString(quarts)
        }
        if let value = details.brand, !value.isEmpty {
            oilBrand = value
        }
        if let value = details.oilGrade, !value.isEmpty {
            oilGrade = value
        }
    }

    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: OilConsumptionEntry.self) else { return }
        amountAdded = details.amountAddedQuarts > 0
            ? EntryFormViewModel.costString(details.amountAddedQuarts) : ""
        oilBrand = details.oilBrand ?? ""
        oilGrade = details.oilGrade ?? ""
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
