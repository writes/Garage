import SwiftUI

struct SparePartFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category: PartCategory = .engine
    @State private var quantity = "1"
    @State private var condition: PartCondition = .new
    @State private var storageLocation = ""
    @State private var error: AppError?
    @State private var isSaving = false
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
            if let error {
                ErrorBanner(error: error)
                    .accessibilityIdentifier("parts.form.error")
            }
            PrimaryButton(title: isSaving ? "Saving..." : "Save Part") {
                Task { await save() }
            }
            .disabled(isSaving)
            .accessibilityIdentifier("parts.form.save")
        }
    }

    private func save() async {
        guard !isSaving, let vehicleId = appState.currentVehicle?.id else { return }
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
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.save(part)
            dismiss()
        } catch {
            self.error = AppError(from: error)
        }
    }
}
