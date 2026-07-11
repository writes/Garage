extension SeedData {
    static func warranties(for vehicleId: String) -> [Warranty] {
        warranties.filter { $0.vehicleId == vehicleId }
    }

    static func recalls(for vehicleId: String) -> [Recall] {
        recalls.filter { $0.vehicleId == vehicleId }
    }

    static func galleryPhotos(for vehicleId: String) -> [GalleryPhoto] {
        galleryPhotos.filter { $0.vehicleId == vehicleId }
    }

    private static let warranties: [Warranty] = []
    private static let recalls: [Recall] = []
    private static let galleryPhotos: [GalleryPhoto] = []
}
