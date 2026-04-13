import SwiftUI

struct EntryDetailView: View {
    let entry: FirestoreEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                EntryRowView(entry: entry)
                ForEach(entry.details.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        Text(String(describing: entry.details[key]?.value ?? .null))
                            .font(Theme.Typography.body)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .navigationTitle(entry.entryType.displayName)
    }
}
