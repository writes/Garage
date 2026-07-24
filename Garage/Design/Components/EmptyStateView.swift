import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.title)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .garageCard()
        .accessibilityElement(children: .combine)
    }
}
