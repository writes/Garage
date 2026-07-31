import SwiftUI

struct RepairFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var title = ""
    @State private var status: ServiceStatus = .resolved

    var body: some View {
        EntryFormScaffold(
            title: "Repair", viewModel: form, onSave: save, onEditEntry: seed,
            onAIPrefill: seedProposal
        ) {
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            Picker("Status", selection: $status) {
                ForEach(ServiceStatus.allCases, id: \.self) { status in Text(status.displayName).tag(status) }
            }
        }
    }

    /// Typed-extraction seeding (spec rev 3 §3). Only fills the title when the user hasn't
    /// already typed one — never overwrites an in-progress edit.
    private func seedProposal(_ details: TypedProposalDetails) {
        if title.isEmpty, let workItem = details.workItem {
            title = workItem
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
