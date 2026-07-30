import SwiftUI

struct ProGateView: View {
    let title: String
    let message: String
    let actionIdentifier: String
    /// The paywall source this gate feeds. Renders `upsell_exposure` on appear — this one
    /// chokepoint gives every ProGateView surface an impressions denominator, so per-source
    /// conversion is exposure->view->purchase, not view->purchase with unknown reach.
    let source: PaywallSource
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
        .onAppear { AnalyticsService.shared.track(.upsellExposure(source: source)) }
    }
}
