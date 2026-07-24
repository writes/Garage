import SwiftUI

struct AlignmentFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var shopNotes = ""

    var body: some View {
        EntryFormScaffold(title: "Alignment", viewModel: form, onSave: save, onEditEntry: seed) {
            TextField("Alignment notes", text: $shopNotes).textFieldStyle(.roundedBorder)
        }
    }

    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: AlignmentEntry.self) else { return }
        shopNotes = details.shopNotes ?? ""
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
