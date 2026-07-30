import Foundation

// Closed enums for the receipt-capture funnel (docs/developer/ANALYTICS_CONTRACT.md §5.2). Split
// out of AnalyticsTypes.swift purely for file length — same precedent as that file's own split
// from AnalyticsService.swift.

/// Where a receipt scan was started from — the three capture sources `ReceiptCaptureViewModel`
/// offers (camera, photo library, PDF import).
enum ReceiptCaptureSource: String, CaseIterable, Equatable, Sendable {
    case camera
    case library
    case pdf
}

/// Why a receipt capture produced no saved proposal. Quota denials keep their own richer event
/// (`receipt_quota_denied`, the oil-analysis convention) rather than folding in here; user-cancel
/// (backing out of a picker) is deliberately absent — never reported as a failure.
enum ReceiptFailureReason: String, CaseIterable, Equatable, Sendable {
    case preflight
    case notAReceipt = "not_a_receipt"
    case serviceError = "service_error"
}

/// Why a receipt-scan quota request was denied — the dual-bucket model (free-lifetime teaser +
/// Pro monthly cap) from the receipt quota refactor.
enum ReceiptQuotaDeniedReason: String, CaseIterable, Equatable, Sendable {
    case freeLifetimeExhausted = "free_lifetime_exhausted"
    case proMonthExhausted = "pro_month_exhausted"
}

/// The only field identifiers receipt quality analytics may emit. This deliberately excludes
/// customer-provided values, parsed text, receipt line items, and every free-form form field.
enum ReceiptPrefillField: String, CaseIterable, Equatable, Hashable, Sendable {
    case date
    case odometer
    case cost
    case shop
    case diy
    case notes

    var caption: String {
        self == .diy ? "DIY" : rawValue
    }
}
