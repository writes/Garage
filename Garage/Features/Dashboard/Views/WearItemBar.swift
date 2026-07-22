import SwiftUI

struct WearItemBar: View {
    let label: String
    let percentage: Double
    let rawValue: String?

    private var color: Color {
        if percentage > 60 { return Theme.Colors.wearGood }
        if percentage > 30 { return Theme.Colors.wearFair }
        return Theme.Colors.wearLow
    }

    /// Non-color signal for the wear health, also used as the VoiceOver value (WCAG 1.4.1).
    private var statusText: String {
        if percentage > 60 { return "Good" }
        if percentage > 30 { return "Fair" }
        return "Replace soon"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(label)
                    .font(Theme.Typography.caption)
                Spacer(minLength: Theme.Spacing.sm)
                if let rawValue {
                    Text(rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Text("\(Int(percentage))%")
                    .foregroundStyle(color)
                    .font(Theme.Typography.caption.weight(.semibold))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.secondary.opacity(0.18))
                    Capsule().fill(color)
                        .frame(width: geometry.size.width * min(max(percentage / 100, 0), 1))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(percentage)) percent, \(statusText)\(rawValue.map { ", \($0)" } ?? "")")
    }
}
