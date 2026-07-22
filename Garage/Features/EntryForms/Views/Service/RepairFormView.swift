import SwiftUI

struct RepairFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var title = ""
    @State private var status: ServiceStatus = .resolved

    var body: some View {
        EntryFormScaffold(title: "Repair", viewModel: form, onSave: save) {
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            Picker("Status", selection: $status) {
                ForEach(ServiceStatus.allCases, id: \.self) { status in Text(status.displayName).tag(status) }
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await form.prepare(vehicleId: vehicleId)
    }

    private func save() async -> Bool {
        guard let vehicle = appState.currentVehicle else { return false }
        let details = RepairEntry(
            title: title,
            symptomDescription: nil,
            resolutionDescription: nil,
            status: status,
            replacedParts: []
        )
        return await form.save(vehicle: vehicle, entryType: .repair, details: details)
    }
}
