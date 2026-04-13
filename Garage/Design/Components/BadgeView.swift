import SwiftUI

struct BadgeView: View {
    let title: String
    var color: Color = Theme.Colors.accent

    var body: some View {
        Text(title)
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
