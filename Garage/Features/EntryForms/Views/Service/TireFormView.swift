import SwiftUI

struct TireFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var actionType: TireActionType = .newInstall
    @State private var brand = ""
    @State private var model = ""
    @State private var position: TirePosition = .allFour
    @State private var frontSize = ""
    @State private var rearSize = ""

    var body: some View {
        EntryFormScaffold(title: "Tire Service", viewModel: form, onSave: save, onEditEntry: seed) {
            Picker("Action", selection: $actionType) {
                ForEach(TireActionType.allCases, id: \.self) { action in Text(action.displayName).tag(action) }
            }
            TextField("Tire brand", text: $brand).textFieldStyle(.roundedBorder)
            TextField("Tire model", text: $model).textFieldStyle(.roundedBorder)
            Picker("Position", selection: $position) {
                ForEach(TirePosition.allCases, id: \.self) { position in Text(position.displayName).tag(position) }
            }
            TextField("Front size", text: $frontSize).textFieldStyle(.roundedBorder)
            TextField("Rear size", text: $rearSize).textFieldStyle(.roundedBorder)
        }
    }

    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: TireEntry.self) else { return }
        actionType = details.actionType
        brand = details.tireBrand
        model = details.tireModel
        position = details.position
        frontSize = details.tireSizeFront ?? ""
        rearSize = details.tireSizeRear ?? ""
    }

    private func save() async -> Bool {
        guard let vehicle = appState.currentVehicle else { return false }
        let details = TireEntry(
            actionType: actionType,
            tireBrand: brand,
            tireModel: model,
            tireSetId: nil,
            tireSizeFront: frontSize.isEmpty ? nil : frontSize,
            tireSizeRear: rearSize.isEmpty ? nil : rearSize,
            position: position,
            treadDepthFL: nil,
            treadDepthFR: nil,
            treadDepthRL: nil,
            treadDepthRR: nil,
            heatCycles: nil,
            compound: nil,
            treadwearRating: nil
        )
        return await form.save(vehicle: vehicle, entryType: .tire, details: details)
    }
}
