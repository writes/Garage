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
            // Offerings load automatically below (.task); this button is now a manual
            // retry for when that load fails or the connection drops, not the primary trigger.
            PrimaryButton(title: "Refresh Plans") { Task { await model.refreshTapped() } }
                .disabled(model.isBusy)
                .accessibilityIdentifier("subscription.refresh")
            Button("Restore Purchases") { Task { await model.restoreTapped() } }
                .disabled(model.isBusy)
                .frame(minHeight: 44)
                .accessibilityIdentifier("subscription.restore")
            policyLinks
            Text("Review the current plan and price before purchasing.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            if model.isBusy {
                ProgressView().accessibilityIdentifier("subscription.activity")
            }
            presentationOutput
            if let plans = model.plans {
                ForEach(Array(plans.packages.enumerated()), id: \.element.handle) { offset, dto in
                    packageView(dto, offset: offset)
                }
            }
        }
        .onChange(of: model.accountRevision, initial: true) { _, revision in
            model.accountRevisionChanged(to: revision)
        }
        .task { await model.refreshTapped() }
    }

    @ViewBuilder
    private func packageView(_ dto: PackageDTO, offset: Int) -> some View {
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
        Button("Choose \(dto.title)") { Task { await model.choosePackageTapped(dto) } }
            .disabled(
                model.isBusy || model.hasPendingReconciliation || dto.period?.isSupportedRenewal != true
            )
            .frame(minHeight: 44)
            .accessibilityIdentifier("subscription.package.\(offset)")
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
