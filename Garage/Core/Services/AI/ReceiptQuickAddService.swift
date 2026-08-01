import FirebaseFunctions
import Foundation
import Observation

/// The server-authoritative receipt quota state. `resetAt` deliberately stays an ISO-8601 string
/// to mirror the callable wire contract exactly; UI-only date formatting happens at the boundary
/// that renders a specific outcome.
struct ReceiptQuotaSnapshot: Codable, Equatable, Sendable {
    enum Entitlement: String, Codable, Equatable, Sendable {
        case free
        case pro
    }

    /// The server ledger's verdict for a polled transaction (status-only, additive).
    enum TransactionState: String, Codable, Equatable, Sendable {
        case granted
        case refunded
        case unknown
    }

    let entitlement: Entitlement
    let scanRemaining: Int
    let scanCeiling: Int
    let confirmedRemaining: Int
    let confirmedAllowance: Int
    let resetAt: String?
    // Additive credit fields (2026-07-31). `var` + nil defaults on purpose: a `let` with a
    // default is EXCLUDED from both the memberwise init and Codable synthesis (the
    // let-default-kills-memberwise-init defect class) — `var` keeps old construction sites
    // compiling AND decodes old servers as nil.
    var creditsRemaining: Int?
    var creditsScanRemaining: Int?
    var creditsGranted: Int?
    var creditsDeficit: Int?
    var creditsPurchasingEnabled: Bool?
    var sweepIncomplete: Bool?
    var transactionState: TransactionState?
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
    let token: String?
    let quota: ReceiptQuotaSnapshot?
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
    /// `transactionID` non-nil = also resolve that purchase's ledger state (post-purchase poll).
    func quotaStatus(transactionID: String?) async throws -> ReceiptQuotaSnapshot
    /// Server-side repair for a purchase whose webhook never arrived. The returned snapshot
    /// carries `transactionState` from the POST-FOLD ledger.
    func reconcileCreditPurchase(transactionID: String) async throws -> ReceiptQuotaSnapshot
}

extension ReceiptQuickAddCalling {
    func quotaStatus() async throws -> ReceiptQuotaSnapshot {
        try await quotaStatus(transactionID: nil)
    }
}

@MainActor
@Observable
final class ReceiptQuickAddService: ReceiptQuickAddCalling {
    static let shared = ReceiptQuickAddService()

    // MUST stay lazy (@ObservationIgnored because lazy in @Observable): this singleton is a
    // default argument on EntryFormViewModel's init, which SwiftUI evaluates while building the
    // form view — in demo/UI-test bootstrap Firebase is never configured, and an eager
    // Functions.functions() here crashes every entry form. 4th instance of this crash class in
    // this repo (see the firebase-preconfigure-crash memory).
    @ObservationIgnored private lazy var functions = Functions.functions(region: Secrets.anthroProxyRegion)

    private init() {}

    func proposeEntry(
        images: [String]?, pdfBase64: String?, vehicle: Vehicle?, now: Date
    ) async throws -> ReceiptProposalResult {
        let callable = functions.httpsCallable("receiptQuickAdd")
        // schemaVersion 2 opts into typed detail extraction; a v1 server ignores the key and
        // the typed fields simply decode nil (the version-gated contract, spec rev 3).
        var payload: [String: Any] = ["schemaVersion": 2]
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

    func quotaStatus(transactionID: String?) async throws -> ReceiptQuotaSnapshot {
        // [String: String] (Sendable) rather than [String: Any]: the async call is a region
        // boundary under strict concurrency.
        let payload: [String: String] = transactionID.map { ["transactionId": $0] } ?? [:]
        let result = try await functions.httpsCallable("receiptQuotaStatus").call(payload)
        return try Self.decodeQuotaSnapshot(from: result)
    }

    func reconcileCreditPurchase(transactionID: String) async throws -> ReceiptQuotaSnapshot {
        let result = try await functions.httpsCallable("reconcileReceiptCreditPurchase")
            .call(["transactionId": transactionID])
        // The wire shape is {transactionState, quota:{...}} — fold the top-level state into the
        // snapshot so polling and reconcile route through ONE terminal transition client-side.
        let json = try Self.callableJSON(from: result)
        let response = try JSONDecoder().decode(ReconcileResponse.self, from: json)
        var snapshot = response.quota
        snapshot.transactionState = response.transactionState
        return snapshot
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

private struct ReconcileResponse: Codable {
    let transactionState: ReceiptQuotaSnapshot.TransactionState
    let quota: ReceiptQuotaSnapshot
}

extension ReceiptEntryProposal {
    /// The parsed entry date, or `now`'s day when the model gave no date. Shared with the voice
    /// proposal, which carries the same field (QuickAddProposalDate).
    func resolvedDate(default fallback: Date) -> Date {
        QuickAddProposalDate.resolve(entryDate, default: fallback)
    }
}
