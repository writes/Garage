import SwiftUI

struct DetailingFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var serviceType: DetailingType = .paintCorrection
    @State private var provider = ""
    @State private var notes = ""
    @State private var error: AppError?
    @State private var isSaving = false
    private let service = DetailingService.shared

    var body: some View {
        BottomSheet(title: "Add Detailing Record") {
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            Picker("Type", selection: $serviceType) {
                ForEach(DetailingType.allCases, id: \.self) { type in Text(type.displayName).tag(type) }
            }
            TextField("Shop or DIY note", text: $provider).textFieldStyle(.roundedBorder)
            TextEditor(text: $notes).frame(minHeight: 120).garageCard()
            if let error {
                ErrorBanner(error: error)
                    .accessibilityIdentifier("detailing.form.error")
            }
            PrimaryButton(title: isSaving ? "Saving..." : "Save Record") {
                Task { await save() }
            }
            .disabled(isSaving)
        }
    }

    private func save() async {
        guard !isSaving, let vehicleId = appState.currentVehicle?.id else { return }
        let record = DetailingRecord(
            id: UUID().uuidString,
            vehicleId: vehicleId,
            serviceDate: .now,
            serviceType: serviceType,
            title: title,
            providerName: provider.isEmpty ? nil : provider,
            productName: nil,
            correctionType: nil,
            coverageArea: nil,
            layers: nil,
            warrantyExpiration: nil,
            maintenanceScheduleNotes: nil,
            cost: nil,
            notes: notes.isEmpty ? nil : notes,
            attachmentPaths: []
        )
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.save(record)
            dismiss()
        } catch {
            self.error = AppError(from: error)
        }
    }
}
