import SwiftUI

struct CostField: View {
    @Binding var cost: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Cost")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField("0.00", text: $cost)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("entry.form.cost")
        }
        .garageCard()
    }
}
