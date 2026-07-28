import SwiftUI

/// The first figure in the app derived from the data rather than played back to the user.
///
/// Cost, odometer and date have all been stored since v1 and nothing was computed from any of
/// them, so Stats showed only what had been typed in. Cost per mile is the number an owner
/// actually wants, and it is also the number a resale buyer respects — so it earns its place on
/// the screen the export is built from.
struct OwnershipCostCard: View {
    let entries: [FirestoreEntry]
    var now: Date = .now

    var body: some View {
        // Nil rather than zeros: a single entry cannot establish a distance or a duration, and
        // "$0.00/mi" would be a confident-looking lie about a history that has not accrued yet.
        if let summary = OwnershipCostCalculator.summary(for: entries, now: now) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Cost of ownership")
                    .font(Theme.Typography.title)
                HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                    figure("Per mile", value: summary.costPerMile?.currencyPerMileText)
                    figure("Per month", value: summary.costPerMonth?.currencyText)
                    figure("Total", value: summary.totalCost.currencyText)
                }
                Text(caption(for: summary))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .garageCard()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("stats.ownershipCost")
        } else {
            EmptyStateView(
                title: "No ownership costs yet",
                message: "Add a cost to a service or fuel entry and Garage works out what this car costs to run.",
                systemImage: "dollarsign.circle"
            )
        }
    }

    private func figure(_ label: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            // An em dash rather than a zero: "not enough history to say" and "it cost nothing"
            // are different claims, and only one of them is true here.
            Text(value ?? "—")
                .font(Theme.Typography.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// States the basis of the figures. A per-mile cost drawn from 200 miles is a very different
    /// claim from one drawn from 40,000, and the user cannot judge it without the denominator.
    private func caption(for summary: OwnershipCostCalculator.Summary) -> String {
        guard summary.milesCovered > 0 else {
            return "Based on logged costs. Add odometer readings to get a per-mile figure."
        }
        return "Across \(summary.milesCovered.formatted()) logged miles."
    }
}
