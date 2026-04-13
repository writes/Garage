import SwiftUI

struct WearHistoryChart: View {
    let wearItems: [WearItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Current wear overview")
                .font(Theme.Typography.headline)
            ForEach(wearItems) { item in
                WearItemBar(label: item.type.label, percentage: item.percentage, rawValue: item.rawValue)
            }
        }
        .garageCard()
    }
}
