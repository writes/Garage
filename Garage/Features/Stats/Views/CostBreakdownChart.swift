import Charts
import SwiftUI

struct CostBreakdownChart: View {
    let entries: [FirestoreEntry]

    var body: some View {
        // Same blank-card problem as MPGTrendChart: a Chart with no bars renders empty white space.
        if groups.isEmpty {
            EmptyStateView(
                title: "No costs recorded yet",
                message: "Add a cost to a service or fuel entry to see where the money goes.",
                systemImage: "chart.bar"
            )
        } else {
            Chart(groups, id: \.type) { item in
                BarMark(x: .value("Type", item.type), y: .value("Cost", item.value))
                    .accessibilityLabel(item.type)
                    .accessibilityValue(item.value.currencyText)
            }
            .frame(height: 220)
            .accessibilityLabel("Cost breakdown by category")
            .garageCard()
        }
    }

    private var groups: [(type: String, value: Double)] { Self.costGroups(from: entries) }

    /// A category whose entries all have nil cost sums to zero and plots as a zero-height bar —
    /// indistinguishable from an empty chart, and it widens the axis for no information. Dropped.
    /// Sorted so the same data always renders in the same order.
    static func costGroups(from entries: [FirestoreEntry]) -> [(type: String, value: Double)] {
        Dictionary(grouping: entries, by: { $0.entryType.displayName })
            .map { key, value in (type: key, value: value.reduce(0) { $0 + ($1.cost ?? 0) }) }
            .filter { $0.value > 0 }
            .sorted { $0.type < $1.type }
    }
}
