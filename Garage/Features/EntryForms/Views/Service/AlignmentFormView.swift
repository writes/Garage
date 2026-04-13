import SwiftUI

struct AlignmentFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var shopNotes = ""

    var body: some View {
        EntryFormScaffold(title: "Alignment", viewModel: form, onSave: save) {
            TextField("Alignment notes", text: $shopNotes).textFieldStyle(.roundedBorder)
        }
        .task { await prepare() }
    }

    private func prepare() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await form.prepare(vehicleId: vehicleId)
    }

    private func save() async -> Bool {
        guard let vehicle = appState.currentVehicle else { return false }
        let emptySpecs = AlignmentSpecs()
        let details = AlignmentEntry(
            shopNotes: shopNotes.isEmpty ? nil : shopNotes,
            frontCaster: nil,
            alignmentSheetPath: nil,
            beforeSpecs: emptySpecs,
            afterSpecs: emptySpecs
        )
        return await form.save(vehicle: vehicle, entryType: .alignment, details: details)
    }
}
