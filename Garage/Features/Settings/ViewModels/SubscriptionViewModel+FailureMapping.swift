import Foundation

// Outcome->message and outcome->analytics mapping, split from SubscriptionViewModel.swift for
// the file-length cap. Pure functions of the outcome — no view-model state.
extension SubscriptionViewModel {
    enum FailureOperation { case status, offerings, purchase, restore }

    func map(_ error: SubscriptionError, operation: FailureOperation) -> AppError {
        if case .identityMismatch = error {
            return .unknown("Subscription account changed. Sign in again.")
        }
        switch operation {
        case .status: return .unknown("Your subscription status couldn't be refreshed. Try again.")
        case .offerings:
            return .unknown("Plans couldn't be loaded. Check your connection, then tap Refresh Plans.")
        case .purchase:
            return .unknown(
                "The purchase couldn't be completed. No entitlement was granted. " +
                    "If you believe you were charged, use Restore Purchases."
            )
        case .restore: return .unknown("Restore couldn't be completed. Try again.")
        }
    }

    /// Closes the purchase funnel opened by `purchase_attempted`. Success is deliberately nil —
    /// `purchase_completed`/`trial_started` already fire from the commit relay, and `busy` never
    /// reached the store (it is a double-tap, not an outcome of an attempt).
    static func purchaseFailureReason(_ outcome: PurchaseOutcome) -> PurchaseFailureReason? {
        switch outcome {
        case .activePro, .busy: return nil
        case .cancelled: return .cancelled
        case .pending: return .pending
        case .selectionInvalidated: return .selectionInvalidated
        case .reconciliationRequired: return .reconciliationRequired
        case .noEntitlement, .notReady, .failed: return .error
        }
    }
}
