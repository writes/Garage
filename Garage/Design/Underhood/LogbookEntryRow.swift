import SwiftUI

/// Logbook row styling — mono mileage right-aligned, ledger framing (arm manifest §2.6).
struct LogbookEntryRow: View {
    let entry: FirestoreEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.entryType.displayName)
                    .font(Theme.Typography.headline)
                Spacer(minLength: Theme.Spacing.sm)
                Text("\(entry.odometerReading.formatted()) mi")
                    .font(Theme.Typography.mono)
                    .fontDesign(.monospaced)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityIdentifier("entry.row.odometer.\(entry.odometerReading)")
            }
            // Date only, like control's row: §2.6 restyles the SAME information — surfacing cost
            // here would make the Logbook an information delta, not a presentation one.
            Text(entry.entryDate.shortDisplay)
                .font(Theme.Typography.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(Theme.Colors.textSecondary)
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
