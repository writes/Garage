import SwiftUI

struct UpgradeFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var title = ""
    @State private var brand = ""
    @State private var category: UpgradeCategory = .engine

    var body: some View {
        EntryFormScaffold(title: "Upgrade", viewModel: form, onSave: save) {
            TextField("Upgrade name", text: $title).textFieldStyle(.roundedBorder)
            TextField("Brand", text: $brand).textFieldStyle(.roundedBorder)
            Picker("Category", selection: $category) {
                ForEach(UpgradeCategory.allCases, id: \.self) { category in Text(category.rawValue).tag(category) }
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
        let details = UpgradeEntry(
            title: title,
            brand: brand.isEmpty ? nil : brand,
            partNumber: nil,
            category: category
        )
        return await form.save(vehicle: vehicle, entryType: .upgrade, details: details)
    }
}
