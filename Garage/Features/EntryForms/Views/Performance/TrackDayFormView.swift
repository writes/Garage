import SwiftUI

struct TrackDayFormView: View {
    @Environment(AppState.self) private var appState
    @State private var form = EntryFormViewModel()
    @State private var venue = ""
    @State private var eventType: TrackEventType = .hpde
    @State private var laps = ""
    @State private var bestLap = ""

    var body: some View {
        EntryFormScaffold(title: "Track Day", viewModel: form, onSave: save) {
            TextField("Venue", text: $venue).textFieldStyle(.roundedBorder)
            Picker("Event Type", selection: $eventType) {
                ForEach(TrackEventType.allCases, id: \.self) { type in Text(type.rawValue).tag(type) }
            }
            TextField("Number of laps", text: $laps).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            TextField("Best lap time", text: $bestLap).textFieldStyle(.roundedBorder)
        }
        .task { await prepare() }
    }

    private func prepare() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await form.prepare(vehicleId: vehicleId)
    }

    private func save() async -> Bool {
        guard let vehicle = appState.currentVehicle else { return false }
        let details = TrackDayEntry(
            venueName: venue,
            eventType: eventType,
            runGroup: nil,
            numberOfLaps: Int(laps),
            bestLapTime: bestLap.isEmpty ? nil : bestLap,
            conditions: .dry,
            tireSetId: nil,
            fuelUsedGallons: nil,
            carObservations: nil,
            driverNotes: nil,
            heatCyclesAdded: 1
        )
        return await form.save(vehicle: vehicle, entryType: .trackDay, details: details)
    }
}
