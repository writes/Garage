import SwiftUI

struct DateOdometerHeader: View {
    @Binding var entryDate: Date
    @Binding var odometerReading: String
    var lastKnownOdometer: Int?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            DatePicker("Date", selection: $entryDate, displayedComponents: .date)
                .datePickerStyle(.compact)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Odometer Reading")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                TextField("Current mileage", text: $odometerReading)
                    .keyboardType(.numberPad)
                    .font(Theme.Typography.title)

                if let lastKnownOdometer {
                    Text("Last recorded: \(lastKnownOdometer.formatted()) mi")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .garageCard()
    }
}
