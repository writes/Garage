import Foundation
import Observation

/// Drives the credits top-up offer and the purchase→grant lifecycle for one receipt sheet.
/// Owned by the VIEW (not folded into ReceiptCaptureViewModel) so the capture state machine
/// stays untouched; the only coupling is the `applyCreditsRecovery` latch-clearing hook.
@MainActor
@Observable
final class ReceiptCreditsController {
    // Internal (not private) ONLY for the +Types/+Grant sibling files — immutable lets, no
    // setter or mutation surface is exposed by the widening.
    let purchaser: ReceiptCreditsPurchaser
    let markers: ReceiptCreditsMarkerStore
    let analytics: any AnalyticsTracking
    let currentUID: () -> String?
    let service: any ReceiptQuickAddCalling
    let now: () -> Date
    /// Injectable so tests drive the poll schedule with a fake clock.
    let sleeper: (Duration) async throws -> Void

    /// Written ONLY by this file and +Grant (the file-length split forces the internal
    /// setter); everything else treats it as read-only.
    var purchaseState: PurchaseState = .idle
    /// Setter internal for tests; production writes only via `refreshProductAvailability`.
    var isProductAvailable = false
    /// The store's LOCALIZED price for the buy button — never hardcode a currency amount
    /// (wrong price in most storefronts; App Review 3.1.1). Setter internal for tests.
    var localizedPrice: String?
    /// Offer-shown dedup, mutated only from the +Types offer extension.
    var reportedOfferScopes: Set<ReceiptCreditsOfferScope> = []
    /// The in-flight purchase→grant work, view-lifetime-bound via `cancelActiveWork`.
    private var activeWork: Task<Void, Never>?

    init(
        purchaser: ReceiptCreditsPurchaser,
        markers: ReceiptCreditsMarkerStore = .shared,
        service: any ReceiptQuickAddCalling = ReceiptQuickAddService.shared,
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        currentUID: @escaping () -> String?,
        now: @escaping () -> Date = { .now },
        sleeper: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.purchaser = purchaser
        self.markers = markers
        self.service = service
        self.analytics = analytics
        self.currentUID = currentUID
        self.now = now
        self.sleeper = sleeper
    }

    // MARK: - Purchase → grant

    /// View entry point: a HELD task so sheet dismissal cancels the grant poll instead of
    /// orphaning it (tri-review advisory). StoreKit itself cannot be cancelled — cancellation
    /// lands at the next poll sleep and takes the persisted-marker resume path.
    func beginPurchase(recoveringInto viewModel: ReceiptCaptureViewModel) {
        // The state guard alone prevents concurrency — a pre-cancel here would flag a task
        // that has not started yet and abort its grant poll mid-flight later.
        guard purchaseState != .purchasing, purchaseState != .waitingForGrant else { return }
        activeWork = Task { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            await self.purchase(recoveringInto: viewModel)
        }
    }

    func cancelActiveWork() {
        activeWork?.cancel()
        activeWork = nil
    }

    func purchase(recoveringInto viewModel: ReceiptCaptureViewModel) async {
        guard purchaseState != .purchasing, purchaseState != .waitingForGrant else { return }
        purchaseState = .purchasing
        analytics.track(.receiptCreditsPurchaseStarted)

        switch await purchaser.purchase() {
        case .completed(let transactionID):
            analytics.track(.receiptCreditsPurchaseSucceeded)
            await awaitGrant(transactionID: transactionID, viewModel: viewModel)
        case .cancelled:
            purchaseState = .idle
        case .pending:
            // Ask-to-Buy: approval may land days later; the next status refresh surfaces it.
            analytics.track(.receiptCreditsPurchasePending)
            purchaseState = .idle
        case .identityMismatch:
            analytics.track(.receiptCreditsPurchaseFailed(reason: .identityMismatch))
            purchaseState = .idle
        case .identityChangedAfterPurchase:
            // Money may have moved; the marker is bound to the paying uid. Never re-prompt.
            analytics.track(.receiptCreditsGrantDelayed)
            purchaseState = .delayed
        case .failed(let reason):
            analytics.track(.receiptCreditsPurchaseFailed(reason: reason))
            purchaseState = .idle
        }
    }

}
