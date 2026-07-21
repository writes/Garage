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
        var payload: [String: Any] = ["transcript": transcript]
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
