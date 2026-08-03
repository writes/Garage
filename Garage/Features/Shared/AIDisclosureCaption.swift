import SwiftUI

/// The persistent AI disclosure: one secondary line plus a Learn More link into the published
/// privacy policy. It is deliberately non-blocking — the tri-vote design pairs a single first-use
/// consent gate with a disclosure that stays visible wherever AI touched the entry, instead of
/// re-asking on every use.
///
/// The link resolves the same `Constants.privacyPolicyURLString` SubscriptionView's policy links
/// use, so there is one published policy URL for the whole app.
struct AIDisclosureCaption: View {
    var message = "Extracted by Claude AI (Anthropic)."
    var alignment: HorizontalAlignment = .leading
    var identifier = "ai.disclosure"

    var body: some View {
        VStack(alignment: alignment, spacing: Theme.Spacing.xs / 2) {
            Text(message)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
            if let privacyURL = URL(string: Constants.privacyPolicyURLString) {
                Link("Learn More", destination: privacyURL)
                    .accessibilityIdentifier(identifier + ".learnMore")
            }
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Colors.textSecondary)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .accessibilityIdentifier(identifier)
    }
}
