import SwiftUI

enum SubscriptionDisclosure {
    static func renewalTerms(
        localizedPrice: String,
        period: SubscriptionPeriodDTO?
    ) -> String {
        guard let period, period.isSupportedRenewal else {
            return "\(localizedPrice), renewal details unavailable. Purchase is disabled."
        }
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        case .unknown: return "\(localizedPrice), renewal details unavailable. Purchase is disabled."
        }
        let duration = period.value == 1 ? unit : "\(period.value) \(unit)s"
        return "\(localizedPrice)/\(duration), auto-renews until cancelled."
    }
}

struct SubscriptionView: View {
    let source: PaywallSource
    @Environment(AppState.self) private var appState

    var body: some View {
        SubscriptionContentView(service: appState.purchaseService, source: source)
            .onAppear { appState.paywallDidAppear(source: source) }
            .onDisappear { appState.paywallDidDismiss(source: source) }
    }
}

private struct SubscriptionContentView: View {
    let source: PaywallSource
    @State private var model: SubscriptionViewModel

    init(service: any SubscriptionFacading, source: PaywallSource) {
        self.source = source
        _model = State(initialValue: SubscriptionViewModel(service: service))
    }

    var body: some View {
        BottomSheet(title: "Garage Pro") {
            Text("Pro includes up to 5 vehicles, parts, detailing, warranty and recall records, and stats.")
                .font(Theme.Typography.body)

            // Anything blocking a purchase surfaces BEFORE the offer. A user who cannot buy needs
            // to know why without scrolling past plans they cannot use.
            presentationOutput
            if model.isBusy {
                ProgressView().accessibilityIdentifier("subscription.activity")
            }

            // The offer leads. It previously rendered last, below a PrimaryButton("Refresh
            // Plans"), policy links and disclosure copy — so the strongest control on a purchase
            // screen was a maintenance affordance and the actual plans sat below the fold.
            if let plans = model.plans {
                ForEach(Array(SubscriptionPlanOrder.ordered(plans).enumerated()), id: \.element.handle) { offset, dto in
                    packageView(dto, isPreferred: offset == 0)
                }
            }

            // Required disclosure stays immediately under the plans it describes.
            Text("Review the current plan and price before purchasing.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            policyLinks

            Button("Restore Purchases") { Task { await model.restoreTapped() } }
                .disabled(model.isBusy)
                .frame(minHeight: 44)
                .accessibilityIdentifier("subscription.restore")
            // Offerings load automatically via .task; this is a manual retry for a failed load or
            // a dropped connection. Demoted from PrimaryButton — it is recovery, not the CTA —
            // but the identifier is unchanged because UI journeys key the sheet off it.
            Button("Refresh Plans") { Task { await model.refreshTapped() } }
                .disabled(model.isBusy)
                .frame(minHeight: 44)
                .accessibilityIdentifier("subscription.refresh")
        }
        .onChange(of: model.accountRevision, initial: true) { _, revision in
            model.accountRevisionChanged(to: revision)
        }
        .task { await model.refreshTapped() }
    }

    @ViewBuilder
    private func packageView(_ dto: PackageDTO, isPreferred: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(dto.title).font(Theme.Typography.headline)
            Text(dto.localizedPrice)
                .font(Theme.Typography.body)
                .accessibilityIdentifier("subscription.price")
            Text(SubscriptionDisclosure.renewalTerms(localizedPrice: dto.localizedPrice, period: dto.period))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("subscription.renewalTerms")
        }
        // Identifiers are keyed to the product, not the row index — reordering must not silently
        // repoint `subscription.package.0` at a different plan.
        let identifier = "subscription.package.\(dto.analyticsProduct.rawValue)"
        let isDisabled = model.isBusy
            || model.hasPendingReconciliation
            || dto.period?.isSupportedRenewal != true

        // Visual emphasis only — deliberately no savings percentage, because PackageDTO carries
        // localized price STRINGS, not decimals, and a computed discount would be fabricated.
        if isPreferred {
            PrimaryButton(title: "Choose \(dto.title)") {
                Task { await model.choosePackageTapped(dto) }
            }
            .disabled(isDisabled)
            .accessibilityIdentifier(identifier)
        } else {
            Button("Choose \(dto.title)") { Task { await model.choosePackageTapped(dto) } }
                .disabled(isDisabled)
                .frame(minHeight: 44)
                .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private var presentationOutput: some View {
        switch model.presentationOutput {
        case .none: EmptyView()
        case .notice(let notice):
            Text(notice.text).accessibilityIdentifier("subscription.message")
        case .reconciliation(.purchase):
            Text(
                "Your purchase may have completed. Do not purchase again. " +
                    "Return to the account used for the purchase, then use Restore Purchases."
            )
            .accessibilityIdentifier("subscription.result.reconciliation")
        case .reconciliation(.restore):
            Text(
                "Your account changed during restore. Nothing was charged. " +
                    "Sign in with the account that made the purchase, then use Restore Purchases."
            )
            .accessibilityIdentifier("subscription.result.reconciliation")
        case .failure(let error):
            ErrorBanner(error: error, retry: nil)
                .accessibilityIdentifier("subscription.message")
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
