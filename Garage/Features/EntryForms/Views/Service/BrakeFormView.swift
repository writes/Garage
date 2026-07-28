import SwiftUI

struct BrakeFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var action: BrakeServiceAction = .padsReplaced
    @State private var position: BrakeServicePosition = .all
    @State private var padBrand = ""
    @State private var padCompound = ""
    // These four were hardcoded to nil at the save site, so WearService had nothing to store and
    // the Dashboard's wear section was permanently empty for every real user — it rendered only in
    // demo mode, where the service returns SeedData instead of reading Firestore.
    @State private var frontPad = ""
    @State private var rearPad = ""
    @State private var frontRotor = ""
    @State private var rearRotor = ""

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
            Text("Life remaining — optional, feeds the dashboard wear bars")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            percentField("Front pads %", text: $frontPad, identifier: "brake.form.frontPad")
            percentField("Rear pads %", text: $rearPad, identifier: "brake.form.rearPad")
            percentField("Front rotors %", text: $frontRotor, identifier: "brake.form.frontRotor")
            percentField("Rear rotors %", text: $rearRotor, identifier: "brake.form.rearRotor")
        }
    }

    private func percentField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        TextField(title, text: text)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier(identifier)
    }

    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: BrakeEntry.self) else { return }
        action = details.action
        position = details.position
        padBrand = details.padBrand ?? ""
        padCompound = details.padCompound ?? ""
        frontPad = Self.percentText(details.frontPadPct)
        rearPad = Self.percentText(details.rearPadPct)
        frontRotor = Self.percentText(details.frontRotorPct)
        rearRotor = Self.percentText(details.rearRotorPct)
    }

    /// `Int(_:)` traps on a non-finite or out-of-Int64 Double. New values are clamped to 0...100
    /// on write, but a document written by an older build or corrupted in transit is not, and this
    /// runs on every edit — so the guard belongs here rather than resting on the writer.
    private static func percentText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(Int(min(100, max(0, value)).rounded()))
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
            frontPadPct: Double(frontPad),
            rearPadPct: Double(rearPad),
            frontRotorPct: Double(frontRotor),
            rearRotorPct: Double(rearRotor),
            fluidFlushed: action == .fluidFlush
        )
        // Runs inside save()'s isSaving window so the Save button cannot be tapped again while
        // the wear write is in flight, and fail-soft inside recordWear: the entry is the user's
        // record, and losing a dashboard bar must not turn a good save into a bad one.
        return await form.save(vehicle: vehicle, entryType: .brake, details: details) { entryID in
            await form.recordWear(
                WearSnapshotFactory.write(
                    from: details,
                    vehicleId: vehicle.id,
                    entryId: entryID,
                    odometerReading: Int(form.odometerReading) ?? 0,
                    recordedAt: form.entryDate
                ),
                vehicleId: vehicle.id
            )
        }
    }
}
