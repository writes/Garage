import SwiftUI

struct SparePartFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category: PartCategory = .engine
    @State private var quantity = "1"
    @State private var condition: PartCondition = .new
    @State private var storageLocation = ""
    private let service = PartsService.shared

    var body: some View {
        BottomSheet(title: "Add Spare Part") {
            TextField("Part name", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("parts.form.name")
            Picker("Category", selection: $category) {
                ForEach(PartCategory.allCases, id: \.self) { category in Text(category.displayName).tag(category) }
            }
            TextField("Quantity", text: $quantity)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("parts.form.quantity")
            Picker("Condition", selection: $condition) {
                ForEach(PartCondition.allCases, id: \.self) { condition in Text(condition.displayName).tag(condition) }
            }
            TextField("Storage location", text: $storageLocation)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("parts.form.location")
            PrimaryButton(title: "Save Part") {
                Task { await save() }
            }
            .accessibilityIdentifier("parts.form.save")
        }
    }

    private func save() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        let part = SparePart(
            id: UUID().uuidString,
            vehicleId: vehicleId,
            name: name,
            category: category,
            brand: nil,
            partNumber: nil,
            quantity: Int(quantity) ?? 1,
            unitCost: nil,
            wherePurchased: nil,
            purchaseDate: nil,
            storageLocation: storageLocation.isEmpty ? nil : storageLocation,
            condition: condition,
            photoStoragePath: nil,
            receiptStoragePath: nil,
            isConsumed: false,
            consumedAtEntryId: nil,
            notes: nil
        )
        try? await service.save(part)
        dismiss()
    }
}
