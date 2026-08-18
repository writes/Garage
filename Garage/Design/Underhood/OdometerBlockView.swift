import SwiftUI

/// Hood odometer block — mono digits, unit, and source line (arm manifest §2.4).
struct OdometerBlockView: View {
    let miles: Int
    let recordedText: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            UnderhoodEyebrow(text: "Current odometer", accent: true)

            HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.sm) {
                Text(miles.formatted())
                    .font(Theme.Typography.mono)
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy, value: miles)
                Text("mi")
                    .font(Theme.Typography.caption.weight(.semibold))
                    .fontDesign(.monospaced)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(miles.formatted()) miles")

            Text(recordedText)
                .font(Theme.Typography.caption.weight(.semibold))
                .fontDesign(.monospaced)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("hood.odometer.source")
        }
    }
}
