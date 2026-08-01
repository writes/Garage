import Foundation

// The controller's value types + poll schedule, split from ReceiptCreditsController.swift for
// the file-length cap.

extension ReceiptCreditsController {
    enum PurchaseState: Equatable {
        case idle
        case purchasing
        /// StoreKit succeeded; polling the server ledger for the grant.
        case waitingForGrant
        case granted
        case refunded
        /// Poll + reconcile both came back empty — the marker resumes on next appear.
        case delayed
    }

    struct OfferContext: Equatable {
        let scope: ReceiptCreditsOfferScope
        let deficit: Int
    }

    /// 2/4/8/16/30s ≈ RC's documented 5–60s webhook delivery window.
    static let pollDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30)]
}

// MARK: - Offer visibility (Q3-C)

extension ReceiptCreditsController {
    /// Non-nil when the top-up offer should render for the latched quota denial. Requires the
    /// server capability flag, a fetchable product, and — for FREE users — at least one prior
    /// receipt-scan Pro-paywall dismissal (subscription-first funnel).
    func offerContext(
        snapshot: ReceiptQuotaSnapshot?, failure: ReceiptCaptureFailure?
    ) -> OfferContext? {
        guard snapshot?.creditsPurchasingEnabled == true, isProductAvailable else { return nil }
        let deficit = snapshot?.creditsDeficit ?? 0
        switch failure {
        case .proMonthExhausted:
            return OfferContext(scope: .proMonth, deficit: deficit)
        case .freeLifetimeExhausted:
            guard let uid = currentUID(), markers.hasDismissedPaywall(uid: uid) else { return nil }
            return OfferContext(scope: .freeLifetime, deficit: deficit)
        default:
            return nil
        }
    }

    func reportOfferShownOnce(_ context: OfferContext) {
        guard !reportedOfferScopes.contains(context.scope) else { return }
        reportedOfferScopes.insert(context.scope)
        analytics.track(.receiptCreditsOfferShown(scope: context.scope))
    }

    func refreshProductAvailability() async {
        let facts = await purchaser.fetchProductFacts()
        isProductAvailable = facts != nil
        localizedPrice = facts?.localizedPrice
    }

    /// A purchase marker expired unresolved even after its final reconcile: surface the durable
    /// support notice. Persisted per uid in the marker store — an in-memory flag vanished on
    /// sheet reopen, silently re-offering a charged user another pack (tri-review blocker).
    var hasExpiredUnresolvedPurchase: Bool {
        guard let uid = currentUID() else { return false }
        return markers.hasExpiredUnresolvedPurchase(uid: uid)
    }
}
