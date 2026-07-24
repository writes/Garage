import SwiftUI

struct BrakeFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var action: BrakeServiceAction = .padsReplaced
    @State private var position: BrakeServicePosition = .all
    @State private var padBrand = ""
    @State private var padCompound = ""

    var body: some View {
        EntryFormScaffold(title: "Brake Service", viewModel: form, onSave: save, onEditEntry: seed) {
            Picker("Action", selection: $action) {
                ForEach(BrakeServiceAction.allCases, id: \.self) { action in Text(action.displayName).tag(action) }
            }
            Picker("Position", selection: $position) {
                ForEach(BrakeServicePosition.allCases, id: \.self) { position in
                    Text(position.displayName).tag(position)
                }
            }
            TextField("Pad brand", text: $padBrand).textFieldStyle(.roundedBorder)
            TextField("Pad compound", text: $padCompound).textFieldStyle(.roundedBorder)
        }
    }

    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: BrakeEntry.self) else { return }
        action = details.action
        position = details.position
        padBrand = details.padBrand ?? ""
        padCompound = details.padCompound ?? ""
    }

    private func save() async -> Bool {
        guard let vehicle = appState.currentVehicle else { return false }
        let details = BrakeEntry(
            action: action,
            position: position,
            padBrand: padBrand.isEmpty ? nil : padBrand,
            padCompound: padCompound.isEmpty ? nil : padCompound,
            rotorBrand: nil,
            padThicknessAtInstallMM: nil,
            frontPadPct: nil,
            rearPadPct: nil,
            frontRotorPct: nil,
            rearRotorPct: nil,
            fluidFlushed: action == .fluidFlush
        )
        return await form.save(vehicle: vehicle, entryType: .brake, details: details)
    }
}
