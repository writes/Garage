import Charts
import SwiftUI

struct MPGTrendChart: View {
    let entries: [FirestoreEntry]

    var body: some View {
        Chart(fuelPoints, id: \.date) { point in
            LineMark(x: .value("Date", point.date), y: .value("MPG", point.value))
                .accessibilityLabel(Formatters.shortDate.string(from: point.date))
                .accessibilityValue(point.value.mpgText)
        }
        .frame(height: 220)
        .accessibilityLabel("Fuel economy trend")
        .garageCard()
    }

    private var fuelPoints: [(date: Date, value: Double)] {
        entries.compactMap { entry in
            guard entry.entryType == .fuel,
                  let mpg = entry.details["calculatedMPG"]?.value.doubleValue else { return nil }
            return (entry.entryDate, mpg)
        }
    }
}
