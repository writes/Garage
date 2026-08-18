import SwiftUI

/// The wear section, rendered identically by BOTH arm bodies. Split from DashboardView.swift by
/// the file-length cap; everything here reads only the shared view model.
extension DashboardView {
    var wearSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Wear items")
                .font(Theme.Typography.title)
            if viewModel.wearItems.isEmpty {
                EmptyStateView(
                    title: "No wear data yet",
                    message: "Brake, tire, and clutch health will show up after the first relevant service entry.",
                    systemImage: "gauge.medium"
                )
            } else {
                ForEach(viewModel.wearItems) { item in
                    WearItemBar(
                        label: item.type.label,
                        percentage: item.percentage,
                        rawValue: item.rawValue,
                        notes: notes(for: item)
                    )
                }
                .garageCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The two lines a wear bar cannot carry itself. Both are absent far more often than present.
    ///
    /// The age note goes on BOTH tire rows rather than one. There is a single install date and no
    /// reliable per-axle scoping for it, so putting it only on the front row would leave "Rear
    /// Tires 61%" reading as unqualified good news about rubber the app believes is six years old.
    func notes(for item: WearItem) -> [WearItemNote] {
        var notes: [WearItemNote] = []
        if let miles = item.milesToReplacement {
            notes.append(.projection(milesToReplacement: miles))
        }
        if item.type.isTire, let years = viewModel.tireAgeYears {
            notes.append(.tireAge(years: years))
        }
        return notes
    }
}
