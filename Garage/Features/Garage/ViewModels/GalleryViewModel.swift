import Observation

@MainActor
@Observable
final class GalleryViewModel {
    private let galleryService: GalleryService

    private(set) var photos: [GalleryPhoto] = []
    private(set) var error: AppError?
    private var reloadToken = 0

    init(galleryService: GalleryService = .shared) {
        self.galleryService = galleryService
    }

    func load(vehicleId: String) async {
        reloadToken &+= 1
        let token = reloadToken
        do {
            let fetched = try await galleryService.fetchPhotos(vehicleId: vehicleId)
            guard token == reloadToken else { return }
            photos = fetched
            error = nil
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
        }
    }
}
