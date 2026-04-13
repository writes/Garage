import SwiftUI

struct MaintenanceFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var item: MaintenanceItemKind = .airFilter
    @State private var status: ServiceStatus = .resolved
    @State private var dueMileage = ""

    var body: some View {
        EntryFormScaffold(title: "Maintenance", viewModel: form, onSave: save) {
            Picker("Item", selection: $item) {
                ForEach(MaintenanceItemKind.allCases, id: \.self) { item in Text(item.rawValue).tag(item) }
            }
            Picker("Status", selection: $status) {
                ForEach(ServiceStatus.allCases, id: \.self) { status in Text(status.rawValue).tag(status) }
            }
            TextField("Next due mileage", text: $dueMileage)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
        .task { await prepare() }
    }

    private func prepare() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await form.prepare(vehicleId: vehicleId)
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
