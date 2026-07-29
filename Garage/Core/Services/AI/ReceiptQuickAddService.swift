import FirebaseFunctions
import Foundation
import Observation

/// A prefill proposal produced by the receiptQuickAdd Cloud Function from a photographed/imported
/// receipt. It is a SUGGESTION only — the UI presents it in the entry form for the user to
/// confirm/edit/save (Trust Pledge). Exactly `VoiceEntryProposal`'s shape plus `lineItems`, which
/// is joined into notes client-side (EntryFormViewModel+ReceiptPrefill.swift).
struct ReceiptEntryProposal: Codable, Equatable, Sendable {
    let entryType: EntryType
    let odometerReading: Int?
    let cost: Double?
    let shopName: String?
    let isDiy: Bool?
    /// ISO 8601 string, or nil meaning "today".
    let entryDate: String?
    let notes: String?
    let lineItems: [String]?
}

/// The parsed proposal plus the raw bytes for every kept page, carried from the capture sheet to
/// the entry form it opens (mirrors `pendingVoicePrefill`'s one-shot handoff, kept separate).
/// Attachment staging/Pro-gating decisions are made later, in EntryFormViewModel+ReceiptPrefill —
/// this package only carries data, never a policy decision.
struct ReceiptPrefillAttachment: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case image, pdf }
    let kind: Kind
    let data: Data
    let displayName: String
}

struct ReceiptPrefillPackage: Equatable, Sendable {
    let proposal: ReceiptEntryProposal
    let attachments: [ReceiptPrefillAttachment]
}

enum ReceiptCallableError: Error, Equatable, Sendable {
    /// The document was not a vehicle service receipt or invoice (G1's typed kill-switch).
    case notAReceipt
    /// The free-lifetime receipt-scan teaser is used up; the UI upsells to Pro.
    case freeLifetimeExhausted
    /// The Pro daily receipt quota is exhausted; resets at `resetAt`.
    case dailyExhausted(resetAt: Date)
}

@MainActor
protocol ReceiptQuickAddCalling {
    func proposeEntry(
        images: [String]?, pdfBase64: String?, vehicle: Vehicle?, now: Date
    ) async throws -> ReceiptEntryProposal
}

@MainActor
@Observable
final class ReceiptQuickAddService: ReceiptQuickAddCalling {
    static let shared = ReceiptQuickAddService()

    private let functions = Functions.functions(region: Secrets.anthroProxyRegion)

    private init() {}

    func proposeEntry(
        images: [String]?, pdfBase64: String?, vehicle: Vehicle?, now: Date
    ) async throws -> ReceiptEntryProposal {
        let callable = functions.httpsCallable("receiptQuickAdd")
        var payload: [String: Any] = [:]
        if let images { payload["images"] = images }
        if let pdfBase64 { payload["pdfBase64"] = pdfBase64 }
        if let vehicle {
            payload["vehicle"] = [
                "year": vehicle.year,
                "make": vehicle.make,
                "model": vehicle.model,
                "currentOdometer": vehicle.currentOdometer
            ]
        }

        let result: HTTPSCallableResult
        do {
            result = try await callable.call(payload)
        } catch {
            if let receiptError = Self.classifyReceiptError(error, now: now) {
                throw receiptError
            }
            throw error
        }

        guard let data = result.data as? [String: Any] else {
            throw AppError.unknown("Receipt response was not a dictionary.")
        }
        let json = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(ReceiptEntryProposal.self, from: json)
    }

    /// Deliberately narrow (mirrors VoiceQuickAddService/ClaudeService): maps exactly the three
    /// documented callable-error shapes to product routing. Anything else falls through to
    /// generic handling — an unrecognized `permission-denied pro_required` (this model has none)
    /// or a malformed details payload never masquerades as a known outcome.
    nonisolated static func classifyReceiptError(_ error: Error, now: Date) -> ReceiptCallableError? {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any],
              let reason = details["reason"] as? String else {
            return nil
        }

        switch (nsError.code, reason) {
        case (FunctionsErrorCode.failedPrecondition.rawValue, "not_a_receipt"):
            return .notAReceipt
        case (FunctionsErrorCode.resourceExhausted.rawValue, "receipt_free_exhausted"):
            return .freeLifetimeExhausted
        case (FunctionsErrorCode.resourceExhausted.rawValue, "receipt_daily_exhausted"):
            guard let resetAtString = details["resetAt"] as? String,
                  let resetAt = ClaudeService.parseQuotaResetAt(resetAtString, now: now) else {
                return nil
            }
            return .dailyExhausted(resetAt: resetAt)
        default:
            return nil
        }
    }
}

extension ReceiptEntryProposal {
    /// The parsed entry date, or `now`'s day when the model gave no date.
    func resolvedDate(default fallback: Date) -> Date {
        guard let entryDate else { return fallback }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: entryDate)
            ?? ISO8601DateFormatter().date(from: entryDate)
            ?? fallback
    }
}
