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
    // `treadDepthReading` was already an offered action type, yet the four depth fields it exists
    // to capture were hardcoded to nil — so choosing it recorded nothing measurable.
    @State private var treadFrontLeft = ""
    @State private var treadFrontRight = ""
    @State private var treadRearLeft = ""
    @State private var treadRearRight = ""

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
            Text("Tread depth in 32nds — optional, feeds the dashboard wear bars")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            treadField("Front left", text: $treadFrontLeft, identifier: "tire.form.treadFrontLeft")
            treadField("Front right", text: $treadFrontRight, identifier: "tire.form.treadFrontRight")
            treadField("Rear left", text: $treadRearLeft, identifier: "tire.form.treadRearLeft")
            treadField("Rear right", text: $treadRearRight, identifier: "tire.form.treadRearRight")
        }
    }

    private func treadField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier(identifier)
    }

    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: TireEntry.self) else { return }
        actionType = details.actionType
        brand = details.tireBrand
        model = details.tireModel
        position = details.position
        frontSize = details.tireSizeFront ?? ""
        rearSize = details.tireSizeRear ?? ""
        treadFrontLeft = details.treadDepthFL ?? ""
        treadFrontRight = details.treadDepthFR ?? ""
        treadRearLeft = details.treadDepthRL ?? ""
        treadRearRight = details.treadDepthRR ?? ""
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
            treadDepthFL: treadFrontLeft.isEmpty ? nil : treadFrontLeft,
            treadDepthFR: treadFrontRight.isEmpty ? nil : treadFrontRight,
            treadDepthRL: treadRearLeft.isEmpty ? nil : treadRearLeft,
            treadDepthRR: treadRearRight.isEmpty ? nil : treadRearRight,
            heatCycles: nil,
            compound: nil,
            treadwearRating: nil
        )
        let didSave = await form.save(vehicle: vehicle, entryType: .tire, details: details)
        // See BrakeFormView: written only after the entry is accepted, and fail-soft.
        guard didSave, let entryID = form.lastSavedEntryID else { return didSave }
        await form.recordWear(
            WearSnapshotFactory.snapshots(
                from: details,
                vehicleId: vehicle.id,
                entryId: entryID,
                odometerReading: Int(form.odometerReading) ?? 0,
                recordedAt: form.entryDate
            ),
            vehicleId: vehicle.id
        )
        return didSave
    }
}
