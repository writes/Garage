import SwiftUI

struct FuelFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var gallons = ""
    @State private var pricePerGallon = ""
    @State private var totalCost = ""
    @State private var stationName = ""
    @State private var fuelGrade: FuelType = .premium93

    var body: some View {
        EntryFormScaffold(
            title: "Fuel Fill-up", viewModel: form, onSave: save, onEditEntry: seed,
            onAIPrefill: seedProposal
        ) {
            TextField("Gallons", text: $gallons)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fuel.form.gallons")
            TextField("Price per gallon", text: $pricePerGallon)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fuel.form.price")
            TextField("Total cost", text: $totalCost)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fuel.form.total")
            TextField("Station name", text: $stationName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fuel.form.station")
            Picker("Fuel grade", selection: $fuelGrade) {
                ForEach(FuelType.allCases, id: \.self) { grade in
                    Text(grade.displayName).tag(grade)
                }
            }
        }
    }

    /// Typed-extraction seeding (spec rev 4 §3). Fuel's own numeric trio (gallons, price/gal,
    /// grade) was TRIMMED from the extraction vocabulary — measured bistable/fabrication-prone
    /// (rev 4 final) — so fuel seeds only the mirrors of the common fields, which land via the
    /// view model's shared prefill first: station from shop, total from cost.
    private func seedProposal(_ details: TypedProposalDetails) {
        _ = details
        if stationName.isEmpty, !form.shopName.isEmpty {
            stationName = form.shopName
        }
        if totalCost.isEmpty, !form.cost.isEmpty {
            totalCost = form.cost
        }
    }

    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: FuelEntry.self) else { return }
        gallons = details.gallons > 0 ? EntryFormViewModel.costString(details.gallons) : ""
        pricePerGallon = details.pricePerGallon > 0 ? EntryFormViewModel.costString(details.pricePerGallon) : ""
        totalCost = details.totalCost > 0 ? EntryFormViewModel.costString(details.totalCost) : ""
        stationName = details.stationName ?? ""
        fuelGrade = details.fuelGrade
        // calculatedMPG is intentionally not seeded — save() always recomputes it fresh below.
    }

    private func save() async -> Bool {
        guard let vehicle = appState.currentVehicle else { return false }
        let gallonsValue = Double(gallons) ?? 0
        let currentOdometer = Int(form.odometerReading) ?? 0
        let mpg = await Self.mpg(
            vehicleId: vehicle.id, currentOdometer: currentOdometer, gallons: gallonsValue,
            before: form.entryDate, excludingEntryID: form.editingEntryID
        )
        let details = FuelEntry(
            gallons: gallonsValue,
            pricePerGallon: Double(pricePerGallon) ?? 0,
            totalCost: Double(totalCost) ?? 0,
            stationName: stationName.isEmpty ? nil : stationName,
            fuelGrade: fuelGrade,
            calculatedMPG: mpg
        )
        return await form.save(vehicle: vehicle, entryType: .fuel, details: details)
    }

    /// The previous fill-up is the newest fuel entry strictly BEFORE this entry's own (current
    /// form) date — not just "the newest OTHER fuel entry" (review MAJOR): that unbounded lookup
    /// could pick a chronologically LATER entry as "previous" when editing any non-latest fill-up,
    /// corrupting MPG. `excludingEntryID` additionally keeps an unmoved edit from finding itself.
    /// Nil on a first-ever fill-up (nothing before it) or a fetch failure — MPG is best-effort.
    private static func mpg(
        vehicleId: String, currentOdometer: Int, gallons: Double, before: Date, excludingEntryID: String?
    ) async -> Double? {
        guard let previous = try? await EntryService.shared.lastFuelEntry(
            vehicleId: vehicleId, before: before, excludingEntryID: excludingEntryID
        ) else { return nil }
        return FuelEntry.calculatedMPG(
            currentOdometer: currentOdometer, previousOdometer: previous.odometerReading, gallons: gallons
        )
    }
}
