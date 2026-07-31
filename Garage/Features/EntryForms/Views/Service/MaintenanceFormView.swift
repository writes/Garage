import SwiftUI

struct MaintenanceFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var item: MaintenanceItemKind = .airFilter
    @State private var status: ServiceStatus = .resolved
    @State private var dueMileage = ""

    var body: some View {
        EntryFormScaffold(
            title: "Maintenance", viewModel: form, onSave: save, onEditEntry: seed,
            onAIPrefill: seedProposal
        ) {
            Picker("Item", selection: $item) {
                ForEach(MaintenanceItemKind.allCases, id: \.self) { item in Text(item.displayName).tag(item) }
            }
            Picker("Status", selection: $status) {
                ForEach(ServiceStatus.allCases, id: \.self) { status in Text(status.displayName).tag(status) }
            }
            TextField("Next due mileage", text: $dueMileage)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// Typed-extraction seeding (spec rev 3 §3). `workItem` matches through
    /// `MaintenanceItemMatcher`'s keyword table — a miss leaves the picker at its default rather
    /// than risk filing the entry under the wrong service.
    private func seedProposal(_ details: TypedProposalDetails) {
        if let workItem = details.workItem, let matched = MaintenanceItemMatcher.match(workItem) {
            item = matched
        }
        if let due = details.nextDueOdometer, due > 0 {
            dueMileage = String(due)
        }
    }

    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: MaintenanceEntry.self) else { return }
        item = details.item
        status = details.status
        dueMileage = details.nextDueMileage.map(String.init) ?? ""
    }

    private func save() async -> Bool {
        guard let vehicle = appState.currentVehicle else { return false }
        let details = MaintenanceEntry(
            item: item,
            otherLabel: nil,
            nextDueMileage: Int(dueMileage),
            nextDueDate: nil,
            symptomDescription: nil,
            resolutionDescription: nil,
            status: status
        )
        return await form.save(vehicle: vehicle, entryType: .maintenance, details: details)
    }
}
