import SwiftUI

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
            if let packages = appState.purchaseService.offerings?.current?.availablePackages {
                ForEach(Array(packages.enumerated()), id: \.element.identifier) { package in
                    Button(package.element.storeProduct.localizedTitle) {
                        Task { try? await appState.purchaseService.purchase(package.element) }
                    }
                    .accessibilityIdentifier("subscription.package.\(package.offset)")
                }
            } else {
                Text("Annual should be preselected in the final paywall presentation.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}
