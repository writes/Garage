import SwiftUI

// The credits top-up UI, split from ReceiptCaptureView.swift for the file/type length caps.

extension ReceiptCaptureView {
    /// The credits top-up affordance (Q3-C). Renders only when the controller's offer context
    /// resolves: server capability on, product fetchable, and — for free users — at least one
    /// prior receipt-scan paywall dismissal. Deficit copy is the Apple 3.1.1 disclosure: a
    /// purchase that first restores refunded credits must say so BEFORE the buy.
    @ViewBuilder
    func creditsOffer(for failure: ReceiptCaptureFailure) -> some View {
        if let credits,
           let context = credits.offerContext(snapshot: viewModel.quotaSnapshot, failure: failure) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                switch credits.purchaseState {
                case .purchasing:
                    ProgressView("Purchasing…")
                case .waitingForGrant:
                    ProgressView("Adding your credits…")
                case .granted:
                    Text("Credits added — you're ready to scan.")
                        .font(Theme.Typography.caption)
                        .accessibilityIdentifier("receipt.credits.granted")
                case .refunded:
                    Text("This purchase was refunded, so its credits were removed.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                case .delayed:
                    Text("Purchase received — credits will appear shortly.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("receipt.credits.delayed")
                case .idle:
                    idleOfferBody(credits: credits, context: context)
                }
            }
            .onAppear { credits.reportOfferShownOnce(context) }
        }
    }

    @ViewBuilder
    private func idleOfferBody(
        credits: ReceiptCreditsController, context: ReceiptCreditsController.OfferContext
    ) -> some View {
        Group {
                    if credits.hasExpiredUnresolvedPurchase {
                        Text("A previous purchase didn't complete. Pull to refresh, or contact "
                            + "support with your App Store receipt.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .accessibilityIdentifier("receipt.credits.support")
                    }
                    if context.deficit > 0 {
                        Text("A previous refund left \(context.deficit) credits owed; this pack restores those first.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    // The price is ALWAYS the store's localized string — a hardcoded amount is
                    // wrong in most storefronts (App Review 3.1.1, tri-review blocking x3).
                    SecondaryButton(title: "Add 10 receipt saves — \(credits.localizedPrice ?? "…")") {
                        // Controller-held task, NOT a fire-and-forget `Task {}` — dismissal
                        // cancels the grant poll instead of orphaning it (tri-review advisory).
                        credits.beginPurchase(recoveringInto: viewModel)
                    }
                    .disabled(credits.localizedPrice == nil)
                    .accessibilityIdentifier("receipt.credits.buy")
        }
    }

    @ViewBuilder
    func failureView(_ failure: ReceiptCaptureFailure) -> some View {
        switch failure {
        case .preflight(let error):
            // retry returns to .ready/.idle WITHOUT clearing any surviving page; a resubmit is a
            // fresh confirmAndParse call, so it goes back through the reentrancy guard normally.
            ErrorBanner(error: error, retry: { viewModel.retryAfterFailure() })
                .accessibilityIdentifier("receipt.capture.error")
        case .notAReceipt:
            failureText("That doesn't look like a service receipt or invoice. Try another photo or file.")
        case .freeLifetimeExhausted:
            upsell
            creditsOffer(for: failure)
        case .proMonthExhausted(let resetAt):
            ErrorBanner(error: .unknown(Self.proMonthExhaustedMessage(resetAt)))
                .accessibilityIdentifier("receipt.capture.error")
            creditsOffer(for: failure)
        case .generic(let message):
            ErrorBanner(error: .unknown(message), retry: { viewModel.retryAfterFailure() })
                .accessibilityIdentifier("receipt.capture.error")
        }
    }

    func failureText(_ message: String) -> some View {
        Text(message)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("receipt.capture.error")
    }

    var upsell: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("You've used your free receipt saves")
                .font(Theme.Typography.headline)
            Text("Upgrade to Garage Pro for 20 receipt saves each month.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            PrimaryButton(title: "Upgrade to Pro") {
                router.present(.subscription(.receiptScan))
            }
            .accessibilityIdentifier("receipt.capture.upgrade")
        }
    }
}
