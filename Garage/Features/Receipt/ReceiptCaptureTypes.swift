import Foundation

// Split out of ReceiptCaptureViewModel.swift to stay under the file-length cap: receipt state,
// failure policy, and task result wrappers stay here so capture behavior remains reviewable.

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

    /// Quota is account state rather than document state, so page changes cannot make another
    /// request meaningful; `notAReceipt` needs a changed document before another model verdict.
    var blocksResubmission: Bool {
        switch self {
        case .notAReceipt, .freeLifetimeExhausted, .dailyExhausted: return true
        case .preflight, .generic: return false
        }
    }

    var isQuotaDenial: Bool {
        switch self {
        case .freeLifetimeExhausted, .dailyExhausted: return true
        case .preflight, .notAReceipt, .generic: return false
        }
    }

    var allowsRetry: Bool { !blocksResubmission }

    static func map(_ error: ReceiptCallableError) -> ReceiptCaptureFailure {
        switch error {
        case .notAReceipt: return .notAReceipt
        case .freeLifetimeExhausted: return .freeLifetimeExhausted
        case .dailyExhausted(let resetAt): return .dailyExhausted(resetAt: resetAt)
        }
    }
}

@MainActor
enum ReceiptCaptureTaskRunner {
    static func parse(
        service: any ReceiptQuickAddCalling, images: [String]?, pdfBase64: String?,
        vehicle: Vehicle?, now: Date
    ) async -> Result<ReceiptEntryProposal, Error> {
        do {
            return .success(
                try await service.proposeEntry(images: images, pdfBase64: pdfBase64, vehicle: vehicle, now: now)
            )
        } catch {
            return .failure(error)
        }
    }

    static func preflightPDF(
        preflighter: any ReceiptPreflighting, url: URL
    ) async -> Result<String, Error> {
        do {
            return .success(try await preflighter.preflightPDF(url: url))
        } catch {
            return .failure(error)
        }
    }
}
