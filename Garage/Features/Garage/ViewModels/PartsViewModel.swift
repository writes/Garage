import Observation

@MainActor
@Observable
final class PartsViewModel {
    private let partsService: PartsService

    private(set) var parts: [SparePart] = []
    private(set) var error: AppError?

    init(partsService: PartsService = .shared) {
        self.partsService = partsService
    }

    func load(vehicleId: String) async {
        do {
            parts = try await partsService.fetchParts(vehicleId: vehicleId)
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }
}
