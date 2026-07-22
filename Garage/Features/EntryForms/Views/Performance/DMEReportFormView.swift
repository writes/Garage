import SwiftUI

struct DMEReportFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var provider = ""
    @State private var reportType: DMEReportType = .overRevs
    @State private var summary = ""

    var body: some View {
        EntryFormScaffold(title: "DME Report", viewModel: form, onSave: save) {
            TextField("Provider", text: $provider).textFieldStyle(.roundedBorder)
            Picker("Report type", selection: $reportType) {
                ForEach(DMEReportType.allCases, id: \.self) { type in Text(type.displayName).tag(type) }
            }
            TextField("Summary", text: $summary).textFieldStyle(.roundedBorder)
        }
        .task { await prepare() }
    }

    private func prepare() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await form.prepare(vehicleId: vehicleId)
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
