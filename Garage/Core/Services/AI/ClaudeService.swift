import FirebaseFunctions
import Foundation
import Observation

@MainActor
@Observable
final class ClaudeService: OilAnalysisCalling {
    static let shared = ClaudeService()

    private let functions = Functions.functions(region: Secrets.anthroProxyRegion)

    private init() {}

    func parseOilAnalysis(pdfBase64: String, now: Date) async throws -> OilAnalysisEntry {
        let callable = functions.httpsCallable("parseOilAnalysis")
        let payload: HTTPSCallableResult

        do {
            payload = try await callable.call(["pdfBase64": pdfBase64])
        } catch {
            if let quotaError = Self.classifyOilAnalysisQuotaError(error, now: now) {
                throw quotaError
            }
            throw error
        }

        guard let data = payload.data as? [String: Any] else {
            throw AppError.unknown("Claude response was not a dictionary.")
        }

        let json = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(OilAnalysisEntry.self, from: json)
    }

    /// This is deliberately narrower than Firebase's general error handling. Only the two
    /// documented callable shapes are allowed to affect product routing.
    nonisolated static func classifyOilAnalysisQuotaError(
        _ error: Error,
        now: Date
    ) -> OilAnalysisCallableError? {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              nsError.code == FunctionsErrorCode.resourceExhausted.rawValue,
              let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any],
              let reason = details["reason"] as? String,
              let entitlementUsed = details["entitlementUsed"] as? String else {
            return nil
        }

        switch (reason, entitlementUsed) {
        case ("free_lifetime_exhausted", "free"):
            guard details.count == 2 else { return nil }
            return .freeLifetimeExhausted
        case ("pro_daily_exhausted", "pro"):
            guard details.count == 3,
                  let resetAtString = details["resetAt"] as? String,
                  let resetAt = parseQuotaResetAt(resetAtString, now: now) else {
                return nil
            }
            return .proDailyExhausted(resetAt: resetAt)
        default:
            return nil
        }
    }

    nonisolated static func parseQuotaResetAt(_ value: String, now: Date) -> Date? {
        let pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$"
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = parser.date(from: value), date > now else {
            return nil
        }

        let roundTripFormatter = DateFormatter()
        roundTripFormatter.locale = Locale(identifier: "en_US_POSIX")
        roundTripFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        roundTripFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        guard roundTripFormatter.string(from: date) == value else {
            return nil
        }

        return date
    }
}
