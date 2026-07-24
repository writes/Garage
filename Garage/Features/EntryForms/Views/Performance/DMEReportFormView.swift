import SwiftUI

struct DMEReportFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var provider = ""
    @State private var reportType: DMEReportType = .overRevs
    @State private var summary = ""

    var body: some View {
        EntryFormScaffold(title: "DME Report", viewModel: form, onSave: save, onEditEntry: seed) {
            TextField("Provider", text: $provider).textFieldStyle(.roundedBorder)
            Picker("Report type", selection: $reportType) {
                ForEach(DMEReportType.allCases, id: \.self) { type in Text(type.displayName).tag(type) }
            }
            TextField("Summary", text: $summary).textFieldStyle(.roundedBorder)
        }
    }

    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: DMEReportEntry.self) else { return }
        provider = details.providerName
        reportType = details.reportType
        summary = details.summary ?? ""
    }

    private func save() async -> Bool {
        guard let vehicle = appState.currentVehicle else { return false }
        let details = DMEReportEntry(
            providerName: provider,
            reportPath: nil,
            reportType: reportType,
            summary: summary.isEmpty ? nil : summary
        )
        return await form.save(vehicle: vehicle, entryType: .dmeReport, details: details)
    }
}
