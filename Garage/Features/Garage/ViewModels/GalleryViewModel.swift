import Observation

@MainActor
@Observable
final class GalleryViewModel {
    private let galleryService: GalleryService
    /// `GalleryService(testPhotos:)` covers the happy path but can only ever succeed, so the failed
    /// load — the case that used to leave the empty state on screen forever — needs this closure
    /// seam. Mirrors `StatsViewModel.contentLoader`.
    private let photosLoader: ((String) async throws -> [GalleryPhoto])?

    private(set) var photos: [GalleryPhoto] = []
    private(set) var error: AppError?
    private(set) var isLoading = false
    /// True once a load has RESOLVED (either way) — see `DetailingViewModel.hasCompletedFirstLoad`.
    private(set) var hasCompletedFirstLoad = false
    private var reloadToken = 0

    init(
        galleryService: GalleryService = .shared,
        photosLoader: ((String) async throws -> [GalleryPhoto])? = nil
    ) {
        self.galleryService = galleryService
        self.photosLoader = photosLoader
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
            let fetched: [GalleryPhoto]
            if let photosLoader {
                fetched = try await photosLoader(vehicleId)
            } else {
                fetched = try await galleryService.fetchPhotos(vehicleId: vehicleId)
            }
            guard token == reloadToken else { return }
            photos = fetched
            error = nil
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
        }
    }
}
