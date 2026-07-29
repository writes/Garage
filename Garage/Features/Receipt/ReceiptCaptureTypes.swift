import Foundation

// Split out of ReceiptCaptureViewModel.swift to stay under the file-length cap: the phase/page/
// failure types it operates on, plus the ReceiptCaptureFailure -> analytics-reason mapping.

enum ReceiptCapturePhase: Equatable {
    case idle
    case preflighting
    case ready
    case parsing
    case failed(ReceiptCaptureFailure)
}

enum ReceiptCaptureFailure: Equatable {
    case preflight(AppError)
    case notAReceipt
    case freeLifetimeExhausted
    case dailyExhausted(resetAt: Date)
    case generic(String)
}

struct ReceiptImagePage: Identifiable, Equatable {
    let id = UUID()
    let preflight: ReceiptPagePreflight
}

struct ReceiptPDFPage: Identifiable, Equatable {
    let id = UUID()
    let base64: String
    let displayName: String
}

extension ReceiptCaptureFailure {
    /// Lives next to `ReceiptCaptureFailure` so a new case is a compile error until it maps —
    /// exactly one of this and `quotaDeniedReason` is non-nil for every case.
    var proposalFailureReason: ReceiptFailureReason? {
        switch self {
        case .preflight: return .preflight
        case .notAReceipt: return .notAReceipt
        case .generic: return .serviceError
        case .freeLifetimeExhausted, .dailyExhausted: return nil
        }
    }

    var quotaDeniedReason: ReceiptQuotaDeniedReason? {
        switch self {
        case .freeLifetimeExhausted: return .freeLifetimeExhausted
        case .dailyExhausted: return .proDailyExhausted
        case .preflight, .notAReceipt, .generic: return nil
        }
    }
}
