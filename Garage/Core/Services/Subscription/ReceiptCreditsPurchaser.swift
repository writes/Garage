import Foundation
import RevenueCat

/// Outcome of one credits-pack purchase attempt. `cancelled`/`pending` are EXPECTED outcomes,
/// never failures; only `completed` may start the grant poll.
enum ReceiptCreditsPurchaseOutcome: Equatable, Sendable {
    case completed(transactionID: String)
    case cancelled
    /// Ask-to-Buy/SCA deferral — surfaces later via a status refresh, never polled now.
    case pending
    /// RC identity was anonymous or diverged from the Firebase uid at the PRE-purchase check —
    /// no money moved.
    case identityMismatch
    /// Money may have moved, then identity diverged at the POST-purchase check. The marker was
    /// already persisted against the PRE-purchase uid, so the grant is recoverable there —
    /// never prompt a repurchase for this (Sol-r4-9).
    case identityChangedAfterPurchase
    case failed(ReceiptCreditsPurchaseFailureReason)
}

/// The fetched consumable's display facts — the SEAM's type, not StoreKit's, so the price the
/// button renders is ALWAYS the store's localized price (a hardcoded "$0.99" shows the wrong
/// price in most storefronts — App Review 3.1.1) and the whole money path is fakeable.
struct ReceiptCreditsProductFacts: Equatable, Sendable {
    let localizedPrice: String
}

/// What one StoreKit round actually produced. RevenueCat's async `purchase(product:)` reports
/// user cancellation as a RETURNED `userCancelled` flag, not a thrown error — a seam that only
/// returns a transaction id would log Cancel as success (tri-review blocking finding).
enum ReceiptCreditsStorePurchase: Equatable, Sendable {
    case purchased(transactionID: String?)
    case cancelled
}

/// Thin seam over the RevenueCat SDK for the ONE consumable. Direct product path on purpose:
/// the offerings pipeline structurally drops period-less products at three separate gates,
/// and widening it for a consumable would weaken the subscription machinery it protects.
@MainActor
protocol ReceiptCreditsStoreClient: AnyObject {
    var appUserID: String { get }
    var isAnonymous: Bool { get }
    /// nil = product not fetchable (ASC mismatch/offline) — the offer hides, never errors.
    func fetchCreditsProduct() async -> ReceiptCreditsProductFacts?
    /// Throws only for real store errors and Ask-to-Buy (mapped by the purchaser).
    func purchaseCredits() async throws -> ReceiptCreditsStorePurchase
}

@MainActor
final class LiveReceiptCreditsStoreClient: ReceiptCreditsStoreClient {
    var appUserID: String { Purchases.shared.appUserID }
    var isAnonymous: Bool { Purchases.shared.isAnonymous }

    func fetchCreditsProduct() async -> ReceiptCreditsProductFacts? {
        guard let product = await Purchases.shared.products([Constants.receiptCreditsPackIdentifier]).first
        else { return nil }
        return ReceiptCreditsProductFacts(localizedPrice: product.localizedPriceString)
    }

    func purchaseCredits() async throws -> ReceiptCreditsStorePurchase {
        guard let product = await Purchases.shared.products([Constants.receiptCreditsPackIdentifier]).first
        else { throw AppError.unknown("Credits product is unavailable.") }
        let result = try await Purchases.shared.purchase(product: product)
        if result.userCancelled { return .cancelled }
        return .purchased(transactionID: result.transaction?.transactionIdentifier)
    }
}

/// Identity-gated purchaser for the receipt-credits consumable. The identity contract mirrors
/// the subscription gateway's lease discipline without entering its ticket machinery: the
/// Firebase uid must equal the RC appUserID immediately BEFORE the StoreKit call (else no
/// purchase happens at all) and is re-checked immediately AFTER (divergence → the persisted
/// marker keeps the grant recoverable under the pre-purchase uid). One purchase in flight at a
/// time — a second tap while StoreKit is up is dropped, not queued.
@MainActor
final class ReceiptCreditsPurchaser {
    private let store: any ReceiptCreditsStoreClient
    private let markers: ReceiptCreditsMarkerStore
    private let currentUID: () -> String?
    private let now: () -> Date
    private var isPurchasing = false

    init(
        store: any ReceiptCreditsStoreClient,
        markers: ReceiptCreditsMarkerStore,
        currentUID: @escaping () -> String?,
        now: @escaping () -> Date = { .now }
    ) {
        self.store = store
        self.markers = markers
        self.currentUID = currentUID
        self.now = now
    }

    /// Offer precondition: the product must be fetchable. Silent-hide on failure is deliberate —
    /// the ASC-mismatch class produces an empty result, never an error worth showing.
    func fetchProductFacts() async -> ReceiptCreditsProductFacts? {
        await store.fetchCreditsProduct()
    }

    func purchase() async -> ReceiptCreditsPurchaseOutcome {
        guard !isPurchasing else { return .cancelled }
        isPurchasing = true
        defer { isPurchasing = false }

        guard let uid = currentUID(), !store.isAnonymous, store.appUserID == uid else {
            return .identityMismatch
        }
        guard await store.fetchCreditsProduct() != nil else {
            return .failed(.productUnavailable)
        }
        // The product fetch suspended; BOTH identities may have changed underneath it (the
        // Firebase user via sign-out/switch, the RC identity via the gateway). Re-check both
        // IMMEDIATELY before money can move (Gemini client-check #1 + tri-review codex).
        guard currentUID() == uid, !store.isAnonymous, store.appUserID == uid else {
            return .identityMismatch
        }

        do {
            let purchase = try await store.purchaseCredits()
            guard case .purchased(let transactionID) = purchase else { return .cancelled }
            if let transactionID {
                // Persist BEFORE the post-check: if identity diverged mid-purchase the marker
                // still binds the grant to the uid that paid.
                markers.add(transactionID: transactionID, uid: uid, now: now())
            }
            let identityHeld = currentUID() == uid && store.appUserID == uid
            if let transactionID {
                return identityHeld
                    ? .completed(transactionID: transactionID)
                    // The marker under the paying uid keeps the grant recoverable.
                    : .identityChangedAfterPurchase
            }
            // No SDK transaction id: nothing to mark, poll, or reconcile — the balance-bearing
            // refresh is the only signal. That refresh runs under the CURRENT user, so it is
            // only safe while identity held; on divergence the delayed path stands and the
            // paying account self-heals via its own next admission decision (tri-review r2,
            // both dissenters).
            return identityHeld ? .completed(transactionID: "") : .identityChangedAfterPurchase
        } catch {
            if RevenueCatValueMapper.isCancellation(error) { return .cancelled }
            if RevenueCatValueMapper.isPaymentPending(error) { return .pending }
            return .failed(.storeError)
        }
    }
}

/// Demo/UI-test double: never touches `Purchases.shared` (RevenueCat is not configured in
/// those bootstraps — the preconfigure launch-crash class). Reports no identity and no
/// product, so the offer simply never renders there.
@MainActor
final class InertReceiptCreditsStoreClient: ReceiptCreditsStoreClient {
    var appUserID: String { "" }
    var isAnonymous: Bool { true }
    func fetchCreditsProduct() async -> ReceiptCreditsProductFacts? { nil }
    func purchaseCredits() async throws -> ReceiptCreditsStorePurchase { .cancelled }
}

/// Same swap idiom as AnalyticsService/NotificationSchedulerFactory.
@MainActor
enum ReceiptCreditsStoreClientFactory {
    static func make() -> any ReceiptCreditsStoreClient {
#if DEBUG
        if AppRuntime.isLocalDemoMode || AppRuntime.isUITestMode {
            return InertReceiptCreditsStoreClient()
        }
#endif
        return LiveReceiptCreditsStoreClient()
    }
}
