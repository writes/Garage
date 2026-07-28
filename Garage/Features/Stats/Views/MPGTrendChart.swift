import Charts
import SwiftUI

struct MPGTrendChart: View {
    let entries: [FirestoreEntry]

    var body: some View {
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
            Chart(points, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("MPG", point.value))
                    .accessibilityLabel(Formatters.shortDate.string(from: point.date))
                    .accessibilityValue(point.value.mpgText)
            }
            .frame(height: 220)
            .accessibilityLabel("Fuel economy trend")
            .garageCard()
        }
    }

    private var points: [(date: Date, value: Double)] { Self.fuelPoints(from: entries) }

    /// Extracted so the empty/non-empty decision is unit testable without rendering a Chart.
    static func fuelPoints(from entries: [FirestoreEntry]) -> [(date: Date, value: Double)] {
        entries.compactMap { entry in
            guard entry.entryType == .fuel,
                  let mpg = entry.details["calculatedMPG"]?.value.doubleValue else { return nil }
            return (entry.entryDate, mpg)
        }
    }
}
