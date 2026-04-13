import Charts
import SwiftUI

struct CostBreakdownChart: View {
    let entries: [FirestoreEntry]

    var body: some View {
        Chart(costGroups, id: \.type) { item in
            BarMark(x: .value("Type", item.type), y: .value("Cost", item.value))
        }
        .frame(height: 220)
        .garageCard()
    }

    private var costGroups: [(type: String, value: Double)] {
        Dictionary(grouping: entries, by: { $0.entryType.displayName }).map { key, value in
            (key, value.reduce(0) { $0 + ($1.cost ?? 0) })
        }
    }
}
