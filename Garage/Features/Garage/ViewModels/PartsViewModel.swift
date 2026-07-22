import Observation

@MainActor
@Observable
final class PartsViewModel {
    private let partsService: PartsService

    private(set) var parts: [SparePart] = []
    private(set) var error: AppError?
    private var reloadToken = 0

    init(partsService: PartsService = .shared) {
        self.partsService = partsService
    }

    func load(vehicleId: String) async {
        reloadToken &+= 1
        let token = reloadToken
        do {
            let fetched = try await partsService.fetchParts(vehicleId: vehicleId)
            guard token == reloadToken else { return }
            parts = fetched.sorted { ($0.purchaseDate ?? .distantPast) > ($1.purchaseDate ?? .distantPast) }
            error = nil
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
        }
    }
}
