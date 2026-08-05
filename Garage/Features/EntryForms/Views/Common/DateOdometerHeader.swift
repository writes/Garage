import SwiftUI

struct DateOdometerHeader: View {
    @Binding var entryDate: Date
    @Binding var odometerReading: String
    /// Create: the vehicle's highest recorded odometer, shown as context. It is NOT a minimum —
    /// a backdated entry below it is legal, so the label must not read like a limit. Edit: the
    /// caller passes the enforced floor instead — `isEditing` switches the label to match.
    var lastKnownOdometer: Int?
    var isEditing = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            DatePicker("Date", selection: $entryDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .accessibilityIdentifier("entry.form.date")

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Odometer Reading")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                TextField("Current mileage", text: $odometerReading)
                    .keyboardType(.numberPad)
                    .font(Theme.Typography.title)
                    .accessibilityIdentifier("entry.form.odometer")

                if let lastKnownOdometer {
                    Text(isEditing
                        ? "Minimum allowed: \(lastKnownOdometer.formatted()) mi"
                        : "Highest recorded: \(lastKnownOdometer.formatted()) mi")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .garageCard()
    }
}
