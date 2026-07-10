import SwiftUI

struct ProGateView: View {
    let title: String
    let message: String
    let actionIdentifier: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            BadgeView(title: "Pro")
            Text(title)
                .font(Theme.Typography.title)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            PrimaryButton(title: "See Pro Options", systemImage: "sparkles", action: action)
                .accessibilityIdentifier(actionIdentifier)
        }
        .garageCard()
    }
}
