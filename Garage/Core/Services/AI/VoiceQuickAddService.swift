import FirebaseFunctions
import Foundation
import Observation

/// A prefill proposal produced by the voiceQuickAdd Cloud Function from a spoken sentence. It is a
/// SUGGESTION only — the UI presents it in the entry form for the user to confirm/edit/save
/// (Trust Pledge). `entryType` is always one of the 12 valid types (the function clamps it).
struct VoiceEntryProposal: Codable, Equatable, Sendable {
    let entryType: EntryType
    let odometerReading: Int?
    let cost: Double?
    let shopName: String?
    let isDiy: Bool?
    /// ISO 8601 string, or nil meaning "today".
    let entryDate: String?
    let notes: String?
    /// schemaVersion-2 typed fields; all-nil against a v1 server. Decoded from the SAME flat
    /// object (the wire has no nesting), hence the custom Codable below.
    let typed: TypedProposalDetails

    init(
        entryType: EntryType,
        odometerReading: Int? = nil,
        cost: Double? = nil,
        shopName: String? = nil,
        isDiy: Bool? = nil,
        entryDate: String? = nil,
        notes: String? = nil,
        typed: TypedProposalDetails = .empty
    ) {
        self.entryType = entryType
        self.odometerReading = odometerReading
        self.cost = cost
        self.shopName = shopName
        self.isDiy = isDiy
        self.entryDate = entryDate
        self.notes = notes
        self.typed = typed
    }

    private enum CodingKeys: String, CodingKey {
        case entryType, odometerReading, cost, shopName, isDiy, entryDate, notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryType = try container.decode(EntryType.self, forKey: .entryType)
        odometerReading = try container.decodeIfPresent(Int.self, forKey: .odometerReading)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        shopName = try container.decodeIfPresent(String.self, forKey: .shopName)
        isDiy = try container.decodeIfPresent(Bool.self, forKey: .isDiy)
        entryDate = try container.decodeIfPresent(String.self, forKey: .entryDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        // Same-level decode: TypedProposalDetails' own keys are all optional, so this succeeds
        // (all-nil) on any v1 payload. `try?` guards only genuinely malformed typed values —
        // a bad typed field must degrade to "not extracted", never sink the whole proposal.
        typed = (try? TypedProposalDetails(from: decoder)) ?? .empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entryType, forKey: .entryType)
        try container.encodeIfPresent(odometerReading, forKey: .odometerReading)
        try container.encodeIfPresent(cost, forKey: .cost)
        try container.encodeIfPresent(shopName, forKey: .shopName)
        try container.encodeIfPresent(isDiy, forKey: .isDiy)
        try container.encodeIfPresent(entryDate, forKey: .entryDate)
        try container.encodeIfPresent(notes, forKey: .notes)
        try typed.encode(to: encoder)
    }
}

enum VoiceCallableError: Error, Equatable {
    /// Voice quick-add is a Pro feature; a free user hit the entitlement fence — the UI upsells.
    case proRequired
    /// The Pro daily voice quota is exhausted; resets at `resetAt`.
    case dailyExhausted(resetAt: Date)
}

@MainActor
protocol VoiceQuickAddCalling {
    func proposeEntry(transcript: String, vehicle: Vehicle?, now: Date) async throws -> VoiceEntryProposal
}

@MainActor
@Observable
final class VoiceQuickAddService: VoiceQuickAddCalling {
    static let shared = VoiceQuickAddService()

    private let functions = Functions.functions(region: Secrets.anthroProxyRegion)

    private init() {}

    func proposeEntry(transcript: String, vehicle: Vehicle?, now: Date) async throws -> VoiceEntryProposal {
        let callable = functions.httpsCallable("voiceQuickAdd")
        // schemaVersion 2 opts into typed detail extraction; a v1 server ignores the key and
        // the typed fields simply decode nil (the version-gated contract, spec rev 3).
        var payload: [String: Any] = ["transcript": transcript, "schemaVersion": 2]
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
            if let voiceError = Self.classifyVoiceError(error, now: now) {
                throw voiceError
            }
            throw error
        }

        guard let data = result.data as? [String: Any] else {
            throw AppError.unknown("Voice response was not a dictionary.")
        }
        let json = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(VoiceEntryProposal.self, from: json)
    }

    /// Maps only the two documented callable error shapes to product routing; anything else falls
    /// through to generic handling. Mirrors ClaudeService's deliberately-narrow classification.
    nonisolated static func classifyVoiceError(_ error: Error, now: Date) -> VoiceCallableError? {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any],
              let reason = details["reason"] as? String else {
            return nil
        }

        switch (nsError.code, reason) {
        case (FunctionsErrorCode.permissionDenied.rawValue, "pro_required"):
            return .proRequired
        case (FunctionsErrorCode.resourceExhausted.rawValue, "voice_daily_exhausted"):
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

extension VoiceEntryProposal {
    /// The parsed entry date, or `now`'s day when the model gave no date. Shared with the receipt
    /// proposal, which carries the same field (QuickAddProposalDate).
    func resolvedDate(default fallback: Date) -> Date {
        QuickAddProposalDate.resolve(entryDate, default: fallback)
    }
}
