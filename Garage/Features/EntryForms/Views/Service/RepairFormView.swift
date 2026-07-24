import SwiftUI

struct RepairFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var title = ""
    @State private var status: ServiceStatus = .resolved

    var body: some View {
        EntryFormScaffold(title: "Repair", viewModel: form, onSave: save, onEditEntry: seed) {
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            Picker("Status", selection: $status) {
                ForEach(ServiceStatus.allCases, id: \.self) { status in Text(status.displayName).tag(status) }
            }
        }
    }

    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: RepairEntry.self) else { return }
        title = details.title
        status = details.status
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
