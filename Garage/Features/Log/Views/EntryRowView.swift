import SwiftUI

struct EntryRowView: View {
    let entry: FirestoreEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Label(entry.entryType.displayName, systemImage: entry.entryType.icon)
                    .font(Theme.Typography.headline)
                Spacer()
                Text(entry.entryDate.shortDisplay)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Text("\(entry.odometerReading.formatted()) mi")
                .font(Theme.Typography.caption)
                .accessibilityIdentifier("entry.row.odometer.\(entry.odometerReading)")
            if let notes = entry.notes, notes.isNotEmpty {
                Text(notes)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .garageCard()
    }
}
