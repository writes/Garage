import SwiftUI

/// The track season, counted.
///
/// Renders nothing at all for an owner with no track days — not an empty state, not a "start
/// logging track days" prompt. Most people who buy a service tracker never take the car to a
/// circuit, and a permanent card explaining a section they will never fill is the kind of noise
/// that makes a screen feel like it belongs to someone else's car.
struct TrackDaySummaryCard: View {
    let entries: [FirestoreEntry]

    var body: some View {
        if let totals = TrackDaySummary.totals(for: entries) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Track days")
                    .font(Theme.Typography.title)
                HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                    figure("Days", value: totals.days.formatted())
                    // Suppressed rather than shown as zero: an entry whose venue was left blank
                    // still happened, and "0 venues" beside "1 day" reads as a bug.
                    if totals.venues > 0 {
                        figure("Venues", value: totals.venues.formatted())
                    }
                }
                Text(mostRecent(totals))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .garageCard()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("stats.trackDays")
        }
    }

    private func figure(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Typography.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Names the venue when the entry recorded one and simply omits it when it did not — the date
    /// is the part the app can always stand behind.
    private func mostRecent(_ totals: TrackDaySummary.Totals) -> String {
        let date = Formatters.shortDate.string(from: totals.mostRecentDate)
        guard let venue = totals.mostRecentVenue else { return "Most recent: \(date)." }
        return "Most recent: \(venue), \(date)."
    }
}
