import Observation

@MainActor
@Observable
final class GalleryViewModel {
    private let galleryService: GalleryService

    private(set) var photos: [GalleryPhoto] = []
    private(set) var error: AppError?

    init(galleryService: GalleryService = .shared) {
        self.galleryService = galleryService
    }

    func load(vehicleId: String) async {
        do {
            photos = try await galleryService.fetchPhotos(vehicleId: vehicleId)
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }
}
