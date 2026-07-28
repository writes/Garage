import SwiftUI

/// Says what the car needs, rather than what the owner already told the app.
///
/// Renders nothing when nothing needs attention. A card reading "everything is fine" is noise on a
/// screen whose job is to surface what does not — and an owner who sees it four times in a row
/// stops reading the section at all.
struct MaintenanceDueCard: View {
    let items: [MaintenanceDue]
    /// How far back the entry history behind `items` reaches. Shown so "no record" cannot be
    /// mistaken for "never done": the app can only speak for what it has seen.
    let historyDepth: Int

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Needs attention")
                    .font(Theme.Typography.title)
                ForEach(items) { due in
                    row(due)
                }
                // Generic intervals are useful, and pretending they are authoritative for a
                // specific engine and duty cycle would not be. Say which one wins.
                Text("Based on common service intervals — your owner's manual takes precedence.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .garageCard()
            .accessibilityIdentifier("dashboard.maintenanceDue")
        }
    }

    private func row(_ due: MaintenanceDue) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Circle()
                .fill(colour(for: due.status))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(due.item.label)
                    .font(Theme.Typography.body)
                Text(detail(for: due))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.maintenance.\(due.item.rawValue)")
    }

    private func colour(for status: MaintenanceStatus) -> Color {
        switch status {
        case .overdue: return Theme.Colors.error
        case .dueSoon: return Theme.Colors.warning
        // Grey, not amber: "we have no record" is an absence of information, not a warning. An
        // owner who genuinely serviced the car before installing the app is not behind on anything.
        case .neverLogged, .upToDate: return Theme.Colors.textSecondary
        }
    }

    private func detail(for due: MaintenanceDue) -> String {
        switch due.status {
        case .overdue:
            if let miles = due.milesPastDue, miles > 0 {
                return "Overdue by \(miles.formatted()) mi"
            }
            return "Past the \(due.item.intervalMonths)-month interval"
        case .dueSoon:
            if let miles = due.milesPastDue, miles < 0 {
                return "Due in about \(abs(miles).formatted()) mi"
            }
            return "Coming up"
        case .neverLogged:
            return "No record in your last \(historyDepth) entries"
        case .upToDate:
            return "Up to date"
        }
    }
}
