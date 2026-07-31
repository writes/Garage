import SwiftUI

struct UpgradeFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var title = ""
    @State private var brand = ""
    @State private var category: UpgradeCategory = .engine

    var body: some View {
        EntryFormScaffold(
            title: "Upgrade", viewModel: form, onSave: save, onEditEntry: seed,
            onAIPrefill: seedProposal
        ) {
            TextField("Upgrade name", text: $title).textFieldStyle(.roundedBorder)
            TextField("Brand", text: $brand).textFieldStyle(.roundedBorder)
            Picker("Category", selection: $category) {
                ForEach(UpgradeCategory.allCases, id: \.self) { category in Text(category.displayName).tag(category) }
            }
        }
    }

    /// Typed-extraction seeding (spec rev 3 §3). `upgradeCategory` converts through
    /// `UpgradeCategory.init(rawValue:)` — an unknown future category fails soft to the picker
    /// default rather than throw the whole payload away.
    private func seedProposal(_ details: TypedProposalDetails) {
        if title.isEmpty, let workItem = details.workItem {
            title = workItem
        }
        if let value = details.brand, !value.isEmpty {
            brand = value
        }
        if let matched = details.upgradeCategory.flatMap(UpgradeCategory.init(rawValue:)) {
            category = matched
        }
    }

    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: UpgradeEntry.self) else { return }
        title = details.title
        brand = details.brand ?? ""
        category = details.category
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
