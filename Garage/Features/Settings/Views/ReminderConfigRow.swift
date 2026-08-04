import SwiftUI

/// Split out of ReminderConfigView.swift when the calendar-export affordance pushed that file
/// against the 250-line cap. `internal` rather than the original `private` purely as a
/// consequence of the move — the only call site is still ReminderConfigView.
struct ReminderConfigRow: View {
    let reminder: Reminder

    private var statusText: String {
        var parts: [String] = [reminder.completedAt != nil ? "Done" : "Due"]
        if let dueMileage = reminder.dueMileage {
            parts.append("at \(dueMileage.formatted()) mi")
        }
        if let dueDate = reminder.dueDate {
            parts.append(dueDate.shortDisplay)
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(reminder.title)
                    .font(Theme.Typography.headline)
                    .strikethrough(reminder.completedAt != nil)
                if reminder.completedAt != nil {
                    Text("Done")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.success)
                }
            }
            if let dueMileage = reminder.dueMileage {
                Text("Due at \(dueMileage.formatted()) mi")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if let dueDate = reminder.dueDate {
                Text(dueDate.shortDisplay)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reminder.title)
        .accessibilityValue(statusText)
        .accessibilityIdentifier("reminder.row.\(reminder.id)")
    }
}
