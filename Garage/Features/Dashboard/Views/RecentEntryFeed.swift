import SwiftUI

struct RecentEntryFeed: View {
    let entries: [FirestoreEntry]

    var body: some View {
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
