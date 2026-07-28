import SwiftUI

struct RecentEntryFeed: View {
    let entries: [FirestoreEntry]

    var body: some View {
        // With no entries this rendered the "Recent activity" heading over nothing, while the two
        // sections directly above it (wear, reminders) showed proper empty states — so the very
        // first dashboard a new user sees ended in what reads as a failed load. Same defect class
        // as the Stats charts and WearHistoryChart.
        if entries.isEmpty {
            EmptyStateView(
                title: "No activity yet",
                message: "Log a fill-up or a service and it shows up here, newest first.",
                systemImage: "clock.arrow.circlepath"
            )
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Recent activity")
                    .font(Theme.Typography.title)
                ForEach(entries) { entry in
                    EntryRowView(entry: entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
