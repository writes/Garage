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

/// The server-authoritative receipt quota state. `resetAt` deliberately stays an ISO-8601 string
/// to mirror the callable wire contract exactly; UI-only date formatting happens at the boundary
/// that renders a specific outcome.
struct ReceiptQuotaSnapshot: Codable, Equatable, Sendable {
    enum Entitlement: String, Codable, Equatable, Sendable {
        case free
        case pro
    }

    let entitlement: Entitlement
    let scanRemaining: Int
    let scanCeiling: Int
    let confirmedRemaining: Int
    let confirmedAllowance: Int
    let resetAt: String?
}

/// The additive receipt proposal response. This preserves the server's existing top-level proposal
/// fields while carrying the optional confirmation token and quota snapshot for current clients.
struct ReceiptProposalResult: Equatable, Sendable {
    let proposal: ReceiptEntryProposal
    let token: String?
    let quota: ReceiptQuotaSnapshot?
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
    /// Nil only when an older server response omitted the additive confirmation fields.
    let token: String? = nil
    let quota: ReceiptQuotaSnapshot? = nil
}

enum ReceiptCallableError: Error, Equatable, Sendable {
    /// The document was not a vehicle service receipt or invoice (G1's typed kill-switch).
    case notAReceipt
    /// The free-lifetime receipt-scan teaser is used up; the UI upsells to Pro.
    case freeLifetimeExhausted
    /// The Pro monthly receipt quota is exhausted; a missing/invalid optional reset stays nil.
    case proMonthExhausted(resetAt: Date?)
}

@MainActor
protocol ReceiptQuickAddCalling {
    func proposeEntry(
        images: [String]?, pdfBase64: String?, vehicle: Vehicle?, now: Date
    ) async throws -> ReceiptProposalResult
    func confirmScan(token: String) async throws -> ReceiptQuotaSnapshot
    func quotaStatus() async throws -> ReceiptQuotaSnapshot
}

@MainActor
@Observable
final class ReceiptQuickAddService: ReceiptQuickAddCalling {
    static let shared = ReceiptQuickAddService()

    private let functions = Functions.functions(region: Secrets.anthroProxyRegion)

    private init() {}

    func proposeEntry(
        images: [String]?, pdfBase64: String?, vehicle: Vehicle?, now: Date
    ) async throws -> ReceiptProposalResult {
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

        let json = try Self.callableJSON(from: result)
        let proposal = try JSONDecoder().decode(ReceiptEntryProposal.self, from: json)
        let metadata = try JSONDecoder().decode(ReceiptQuickAddMetadata.self, from: json)
        return ReceiptProposalResult(proposal: proposal, token: metadata.token, quota: metadata.quota)
    }

    func confirmScan(token: String) async throws -> ReceiptQuotaSnapshot {
        let result = try await functions.httpsCallable("confirmReceiptScan").call(["token": token])
        return try Self.decodeQuotaSnapshot(from: result)
    }

    func quotaStatus() async throws -> ReceiptQuotaSnapshot {
        let result = try await functions.httpsCallable("receiptQuotaStatus").call()
        return try Self.decodeQuotaSnapshot(from: result)
    }

    /// Deliberately narrow (mirrors VoiceQuickAddService/ClaudeService): maps exactly the current
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
        case (FunctionsErrorCode.resourceExhausted.rawValue, "receipt_scan_exhausted"),
             (FunctionsErrorCode.resourceExhausted.rawValue, "receipt_confirmed_exhausted"):
            return receiptQuotaError(scope: details["scope"] as? String, details: details, now: now)
        default:
            return nil
        }
    }

    private static func callableJSON(from result: HTTPSCallableResult) throws -> Data {
        guard let data = result.data as? [String: Any] else {
            throw AppError.unknown("Receipt response was not a dictionary.")
        }
        return try JSONSerialization.data(withJSONObject: data)
    }

    private static func decodeQuotaSnapshot(from result: HTTPSCallableResult) throws -> ReceiptQuotaSnapshot {
        try JSONDecoder().decode(ReceiptQuotaSnapshot.self, from: callableJSON(from: result))
    }

    nonisolated private static func receiptQuotaError(
        scope: String?, details: [String: Any], now: Date
    ) -> ReceiptCallableError? {
        switch scope {
        case "free_lifetime":
            return .freeLifetimeExhausted
        case "pro_month":
            let resetAt = (details["resetAt"] as? String)
                .flatMap { ClaudeService.parseQuotaResetAt($0, now: now) }
            return .proMonthExhausted(resetAt: resetAt)
        default:
            return nil
        }
    }
}

private struct ReceiptQuickAddMetadata: Codable {
    let token: String?
    let quota: ReceiptQuotaSnapshot?
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
