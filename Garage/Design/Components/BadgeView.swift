import SwiftUI

struct BadgeView: View {
    let title: String
    /// nil = the pack's `accent` role. It resolves in `body` rather than as a stored default
    /// because tokens are main-actor computed now: a default read at each call site's init would
    /// neither compile off the main actor nor stay reactive to a live pack change.
    var color: Color?

    var body: some View {
        let color = color ?? Theme.Colors.accent
        Text(title)
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
