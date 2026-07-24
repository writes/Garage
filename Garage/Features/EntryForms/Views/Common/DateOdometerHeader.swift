import SwiftUI

struct DateOdometerHeader: View {
    @Binding var entryDate: Date
    @Binding var odometerReading: String
    /// Create: the vehicle's actual last-recorded odometer. Edit: the caller passes
    /// viewModel.odometerFloor instead (the validation floor, which can differ from the true
    /// last-recorded value) — `isEditing` switches the label to match what's actually being shown.
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
                        : "Last recorded: \(lastKnownOdometer.formatted()) mi")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .garageCard()
    }
}
