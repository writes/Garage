import Charts
import SwiftUI

struct MPGTrendChart: View {
    let entries: [FirestoreEntry]

    /// One point per qualifying fuel entry, carrying that entry's id. Two fill-ups on the same
    /// calendar date are ordinary (a top-up on the way home from a road trip), and keying the
    /// chart by date collapsed them into one mark — silently dropping real data from the only
    /// chart that shows per-tank variance.
    struct FuelPoint: Identifiable, Equatable {
        let id: String
        let date: Date
        let value: Double
    }

    var body: some View {
        // Evaluated ONCE per body pass: as a computed property this ran the full compactMap over
        // the whole entry history twice — once for the emptiness test, once for the Chart.
        let points = Self.fuelPoints(from: entries)
        // A Chart with no marks draws a blank 220pt card: no axes, no message, just white space
        // that reads as broken or still-loading. Every other section of the app explains itself
        // when empty (Dashboard wear, reminders), so this does too.
        if points.isEmpty {
            EmptyStateView(
                title: "No fuel economy yet",
                message: "Log fuel fill-ups with odometer readings and your MPG trend appears here.",
                systemImage: "fuelpump"
            )
        } else {
            // No explicit `id:` — FuelPoint is Identifiable on the entry id, so same-date fill-ups
            // stay distinct marks. Deliberately un-binned and uncapped: per-tank variance IS the
            // diagnostic signal here, so downsampling would destroy what the chart is for.
            Chart(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("MPG", point.value))
                    .accessibilityLabel(Formatters.shortDate.string(from: point.date))
                    .accessibilityValue(point.value.mpgText)
            }
            .frame(height: 220)
            .accessibilityLabel("Fuel economy trend")
            .garageCard()
        }
    }

    /// Extracted so the empty/non-empty decision is unit testable without rendering a Chart.
    static func fuelPoints(from entries: [FirestoreEntry]) -> [FuelPoint] {
        entries.compactMap { entry in
            guard entry.entryType == .fuel,
                  let mpg = entry.details["calculatedMPG"]?.value.doubleValue else { return nil }
            return FuelPoint(id: entry.id, date: entry.entryDate, value: mpg)
        }
    }
}
