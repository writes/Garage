import SwiftUI
import RevenueCat

enum SubscriptionDisclosure {
    static func renewalTerms(localizedPrice: String, period: SubscriptionPeriod?) -> String {
        guard let period else {
            return "\(localizedPrice), not an auto-renewing subscription."
        }

        let unit: String
        switch period.unit {
        case .day:
            unit = "day"
        case .week:
            unit = "week"
        case .month:
            unit = "month"
        case .year:
            unit = "year"
        @unknown default:
            unit = "period"
        }

        let duration = period.value == 1 ? unit : "\(period.value) \(unit)s"
        return "\(localizedPrice)/\(duration), auto-renews until cancelled."
    }
}

struct SubscriptionView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        BottomSheet(title: "Garage Pro") {
            Text(
                "Unlimited vehicles, reminders, exports, attachments, gallery, "
                    + "parts, detailing, warranty, recalls, AI oil analysis, "
                    + "and full stats."
            )
                .font(Theme.Typography.body)
            PrimaryButton(title: "Refresh Plans") {
                Task { await appState.purchaseService.fetchOfferings() }
            }
            .accessibilityIdentifier("subscription.refresh")
            Button("Restore Purchases") {
                Task { try? await appState.purchaseService.restorePurchases() }
            }
            .accessibilityIdentifier("subscription.restore")
            if let packages = appState.purchaseService.offerings?.current?.availablePackages {
                ForEach(Swift.Array(packages.enumerated()), id: \.element.identifier) { package in
                    let product = package.element.storeProduct
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(product.localizedTitle)
                            .font(Theme.Typography.headline)
                        Text(product.localizedPriceString)
                            .font(Theme.Typography.body)
                            .accessibilityIdentifier("subscription.price")
                        Text(
                            SubscriptionDisclosure.renewalTerms(
                                localizedPrice: product.localizedPriceString,
                                period: product.subscriptionPeriod
                            )
                        )
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("subscription.renewalTerms")
                    }
                    Button("Choose \(product.localizedTitle)") {
                        Task { try? await appState.purchaseService.purchase(package.element) }
                    }
                    .accessibilityIdentifier("subscription.package.\(package.offset)")
                }
            } else {
                Text("Annual should be preselected in the final paywall presentation.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            policyLinks
        }
    }

    @ViewBuilder
    private var policyLinks: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let termsURL = URL(string: Constants.termsOfUseURLString) {
                Link("Terms of Use (EULA)", destination: termsURL)
                    .accessibilityIdentifier("subscription.terms")
            }
            if let privacyURL = URL(string: Constants.privacyPolicyURLString) {
                Link("Privacy Policy", destination: privacyURL)
                    .accessibilityIdentifier("subscription.privacy")
            }
        }
        .font(Theme.Typography.caption)
    }
}
