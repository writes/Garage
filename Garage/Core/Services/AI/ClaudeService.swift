import FirebaseFunctions
import Foundation
import Observation

@MainActor
@Observable
final class ClaudeService {
    static let shared = ClaudeService()

    private let functions = Functions.functions(region: Secrets.anthroProxyRegion)

    private init() {}

    func parseOilAnalysis(pdfBase64: String) async throws -> OilAnalysisEntry {
        let callable = functions.httpsCallable("parseOilAnalysis")
        let payload = try await callable.call(["pdfBase64": pdfBase64])

        guard let data = payload.data as? [String: Any] else {
            throw AppError.unknown("Claude response was not a dictionary.")
        }

        let json = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(OilAnalysisEntry.self, from: json)
    }
}
