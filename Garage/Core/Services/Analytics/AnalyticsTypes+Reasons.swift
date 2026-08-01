import Foundation

// Failure-reason enums for the analytics contract, split from AnalyticsTypes.swift for the
// file-length policy cap (same precedent as AnalyticsTypes+Receipt.swift).

/// Why a voice capture produced no saved proposal. Mirrors `VoiceFailure` minus payloads; the
/// mapping lives next to `VoiceFailure` so the two enums cannot silently drift apart.
enum VoiceFailureReason: String, CaseIterable, Equatable, Sendable {
    case permissionDenied = "permission_denied"
    case proRequired = "pro_required"
    case dailyExhausted = "daily_exhausted"
    case recognizerUnavailable = "recognizer_unavailable"
    case audioInputUnavailable = "audio_input_unavailable"
    case emptyTranscript = "empty_transcript"
    case serviceError = "service_error"
}

/// Why a purchase attempt produced no entitlement. `cancelled` is the expected majority and is
/// not a defect — same convention as `SignInFailureReason`. `pending` is Ask-to-Buy/deferred
/// approval, which may still convert later.
enum PurchaseFailureReason: String, CaseIterable, Equatable, Sendable {
    case cancelled
    case pending
    case selectionInvalidated = "selection_invalidated"
    case reconciliationRequired = "reconciliation_required"
    case error
}

/// Why an oil-analysis import ended without a parsed report. Quota denials keep their own
/// richer event (`oil_analysis_quota_denied`); cancellation is deliberately absent — the
/// cancel path also runs on view teardown and deinit, so it would count lifecycle noise, and
/// abandonment is derivable as requested − (succeeded + failed + quota_denied).
enum OilAnalysisFailureReason: String, CaseIterable, Equatable, Sendable {
    case preflight
    case service
}

/// Why a recall lookup returned nothing. `vin_missing`/`vin_not_recognised` are user-data
/// states; `service_error` is ours.
enum RecallLookupFailureReason: String, CaseIterable, Equatable, Sendable {
    case vinMissing = "vin_missing"
    case vinNotRecognised = "vin_not_recognised"
    case serviceError = "service_error"
}

/// Which quota scope the credits top-up offer rendered for (Q3-C: pro sees it directly at the
/// monthly cap; free only after at least one Pro-paywall dismissal).
enum ReceiptCreditsOfferScope: String, CaseIterable, Equatable, Sendable {
    case freeLifetime = "free_lifetime"
    case proMonth = "pro_month"
}

/// Why a credits purchase produced no completed transaction. `cancelled`/`pending` have their
/// own events (expected outcomes, not failures — the purchase-funnel convention).
enum ReceiptCreditsPurchaseFailureReason: String, CaseIterable, Equatable, Sendable {
    /// RC identity was anonymous or diverged from the Firebase uid at the purchase checks.
    case identityMismatch = "identity_mismatch"
    case storeError = "store_error"
    case productUnavailable = "product_unavailable"
}
