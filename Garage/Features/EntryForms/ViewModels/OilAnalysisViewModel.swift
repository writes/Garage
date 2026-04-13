import Observation

@MainActor
@Observable
final class OilAnalysisViewModel {
    private let claudeService: ClaudeService

    private(set) var isParsing = false
    private(set) var error: AppError?

    init(claudeService: ClaudeService = .shared) {
        self.claudeService = claudeService
    }

    func parse(pdfBase64: String) async -> OilAnalysisEntry? {
        isParsing = true
        defer { isParsing = false }

        do {
            error = nil
            return try await claudeService.parseOilAnalysis(pdfBase64: pdfBase64)
        } catch {
            self.error = AppError(from: error)
            return nil
        }
    }
}
