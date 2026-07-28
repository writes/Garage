import SwiftUI

/// Add-forms for the Warranty & Recalls screen.
///
/// `WarrantyService.saveWarranty` and `saveRecall` shipped with ZERO callers, so this Pro screen
/// was read-only: it showed "No warranty records yet" forever and could never hold anything. Real
/// data appeared only in demo mode, where the service returns `SeedData` instead of reading
/// Firestore — which is why the gap survived every manual walkthrough and screenshot pass.
///
/// Both forms deliberately collect a SUBSET of their model's fields. `Warranty` declares 20+
/// properties; asking for all of them to record "bumper-to-bumper until March" would be a worse
/// experience than not having the feature. The omitted fields stay nil and remain available to a
/// later editor.
struct WarrantyFormView: View {
    let vehicleId: String
    let onSave: (Warranty) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var warrantyType: WarrantyType = .factory
    @State private var providerName = ""
    @State private var planName = ""
    @State private var coverageStart = Date.now
    @State private var hasCoverageEnd = true
    @State private var coverageEnd = Calendar.current.date(byAdding: .year, value: 3, to: .now) ?? .now
    @State private var mileageLimit = ""
    @State private var contractNumber = ""
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Coverage") {
                    Picker("Type", selection: $warrantyType) {
                        Text("Factory").tag(WarrantyType.factory)
                        Text("Extended").tag(WarrantyType.extended)
                    }
                    .accessibilityIdentifier("warranty.form.type")
                    DatePicker("Starts", selection: $coverageStart, displayedComponents: .date)
                    Toggle("Has an end date", isOn: $hasCoverageEnd)
                        .accessibilityIdentifier("warranty.form.hasEnd")
                    if hasCoverageEnd {
                        DatePicker("Ends", selection: $coverageEnd, displayedComponents: .date)
                            .accessibilityIdentifier("warranty.form.end")
                    }
                    TextField("Mileage limit", text: $mileageLimit)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("warranty.form.mileage")
                }
                Section("Provider") {
                    TextField("Provider", text: $providerName)
                    TextField("Plan name", text: $planName)
                    TextField("Contract number", text: $contractNumber)
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("Add Warranty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                        .accessibilityIdentifier("warranty.form.save")
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let warranty = Warranty(
            id: UUID().uuidString,
            vehicleId: vehicleId,
            warrantyType: warrantyType,
            basicTermMonths: nil, basicTermMiles: nil,
            powertrainTermMonths: nil, powertrainTermMiles: nil,
            corrosionTermMonths: nil, roadsideTermMonths: nil,
            // The list sorts on expirationDate first, then coverageEnd — set both from the one
            // date the user actually gave so a saved record cannot sort as "no expiration".
            expirationDate: hasCoverageEnd ? coverageEnd : nil,
            providerName: providerName.isEmpty ? nil : providerName,
            planName: planName.isEmpty ? nil : planName,
            coverageStart: coverageStart,
            coverageEnd: hasCoverageEnd ? coverageEnd : nil,
            mileageLimit: Int(mileageLimit),
            deductible: nil,
            contractNumber: contractNumber.isEmpty ? nil : contractNumber,
            providerPhone: nil, coverageDescription: nil, exclusions: nil, documentPath: nil,
            startDate: coverageStart,
            notes: notes.isEmpty ? nil : notes,
            createdAt: Date.now
        )
        if await onSave(warranty) { dismiss() }
    }
}

struct RecallFormView: View {
    let vehicleId: String
    let onSave: (Recall) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var campaignNumber = ""
    @State private var component = ""
    @State private var status: RecallStatus = .outstanding
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Recall") {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("recall.form.title")
                    TextField("Campaign number", text: $campaignNumber)
                    TextField("Component affected", text: $component)
                    Picker("Status", selection: $status) {
                        Text("Outstanding").tag(RecallStatus.outstanding)
                        Text("Completed").tag(RecallStatus.completed)
                        Text("Not applicable").tag(RecallStatus.notApplicable)
                    }
                    .accessibilityIdentifier("recall.form.status")
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("Add Recall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // A recall with no title renders as a blank row, so it is the one required field.
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("recall.form.save")
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let recall = Recall(
            id: UUID().uuidString,
            vehicleId: vehicleId,
            campaignNumber: campaignNumber.isEmpty ? nil : campaignNumber,
            title: title.trimmingCharacters(in: .whitespaces),
            description: nil,
            componentAffected: component.isEmpty ? nil : component,
            dateAnnounced: nil,
            status: status,
            completedDate: status == .completed ? Date.now : nil,
            completedShop: nil, completedOdometer: nil, completedReceiptPath: nil,
            // Entered by hand here; the nhtsaApi source is reserved for a future lookup.
            recallSource: .manual,
            notes: notes.isEmpty ? nil : notes,
            createdAt: Date.now
        )
        if await onSave(recall) { dismiss() }
    }
}
