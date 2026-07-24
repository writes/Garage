import SwiftUI

struct ReminderCard: View {
    let reminder: Reminder

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(reminder.title)
                .font(Theme.Typography.headline)
            if let dueMileage = reminder.dueMileage {
                Text("Due at \(dueMileage.formatted()) mi")
                    .font(Theme.Typography.body)
            }
            if let dueDate = reminder.dueDate {
                Text(dueDate.shortDisplay)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .garageCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.reminder.\(reminder.title)")
    }
}
