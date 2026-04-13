import SwiftUI

struct SubscriptionView: View {
    @State private var purchaseService = PurchaseService.shared

    var body: some View {
        BottomSheet(title: "Garage Pro") {
            Text(
                "Unlimited vehicles, reminders, exports, attachments, gallery, "
                    + "parts, detailing, warranty, recalls, AI oil analysis, "
                    + "and full stats."
            )
                .font(Theme.Typography.body)
            PrimaryButton(title: "Refresh Plans") {
                Task { await purchaseService.fetchOfferings() }
            }
            if let offerings = purchaseService.offerings {
                ForEach(offerings.current?.availablePackages ?? [], id: \.identifier) { package in
                    Button(package.storeProduct.localizedTitle) {
                        Task { try? await purchaseService.purchase(package) }
                    }
                }
            } else {
                Text("Annual should be preselected in the final paywall presentation.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}
