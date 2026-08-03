import Observation

@MainActor
@Observable
final class PartsViewModel {
    private let partsService: PartsService
    /// See `DetailingViewModel.recordsLoader`: `PartsService` is a `private init` singleton, so the
    /// success AND failure paths of `load` are only testable through a closure seam.
    private let partsLoader: ((String) async throws -> [SparePart])?

    private(set) var parts: [SparePart] = []
    private(set) var error: AppError?
    private(set) var isLoading = false
    /// True once a load has RESOLVED (either way) — see `DetailingViewModel.hasCompletedFirstLoad`.
    private(set) var hasCompletedFirstLoad = false
    private var reloadToken = 0

    init(
        partsService: PartsService = .shared,
        partsLoader: ((String) async throws -> [SparePart])? = nil
    ) {
        self.partsService = partsService
        self.partsLoader = partsLoader
    }

    func load(vehicleId: String) async {
        reloadToken &+= 1
        let token = reloadToken
        isLoading = true
        defer {
            if token == reloadToken {
                isLoading = false
                hasCompletedFirstLoad = true
            }
        }
        do {
            let fetched: [SparePart]
            if let partsLoader {
                fetched = try await partsLoader(vehicleId)
            } else {
                fetched = try await partsService.fetchParts(vehicleId: vehicleId)
            }
            guard token == reloadToken else { return }
            parts = fetched.sorted { ($0.purchaseDate ?? .distantPast) > ($1.purchaseDate ?? .distantPast) }
            error = nil
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
        }
    }
}
