import SwiftUI

struct WearHistoryChart: View {
    let wearItems: [WearItem]

    var body: some View {
        // With no items this rendered a card containing nothing but the heading — a title floating
        // over blank space, which reads as a failed load rather than "nothing here yet".
        if wearItems.isEmpty {
            EmptyStateView(
                title: "No wear data yet",
                message: "Brake, tire, and clutch health appears after the first relevant service entry.",
                systemImage: "gauge.medium"
            )
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Current wear overview")
                    .font(Theme.Typography.headline)
                ForEach(wearItems) { item in
                    WearItemBar(
                        label: item.type.label,
                        percentage: item.percentage,
                        rawValue: item.rawValue
                    )
                }
            }
            .garageCard()
        }
    }
}
