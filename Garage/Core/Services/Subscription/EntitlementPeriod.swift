import Foundation

/// Which pricing phase an active entitlement is in. Mirrors RevenueCat's `PeriodType`, kept as a
/// local enum so this file stays free of the SDK (the mapping lives in `RevenueCatClienting`).
///
/// Exists so a free-trial start can be told apart from a paid purchase. Without it both look
/// identical to the client, which makes trial-start rate unmeasurable and inflates
/// `purchase_completed` with trials that may never convert.
enum EntitlementPeriod: String, Equatable, Sendable {
    case normal
    case trial
    case intro
    /// The SDK reported a phase this app does not model, or there is no active entitlement.
    /// Deliberately distinct from `normal` so an unmapped future case is never silently counted
    /// as a paid purchase.
    case unknown
}

extension EntitlementSnapshot {
    /// Which event a completed purchase should report. A purchase that opens a free trial reports
    /// `trial_started` and NEVER `purchase_completed`: emitting both would leave the paid count
    /// inflated by trials that may never convert, which is the defect this distinction removes.
    /// Lives here rather than in the relay so the rule sits next to the phase it depends on.
    func purchaseAnalytics(for productID: AnalyticsProductID) -> AnalyticsEvent {
        period == .trial
            ? .trialStarted(productID: productID)
            : .purchaseCompleted(productID: productID)
    }
}
