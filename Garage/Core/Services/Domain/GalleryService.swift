import FirebaseFirestore
import Observation

@MainActor
@Observable
final class GalleryService {
    static let shared = GalleryService()

    private var firestore: FirestoreService { .shared }

    private init() {}

    func save(_ photo: GalleryPhoto) async throws {
        guard !AppRuntime.isLocalDemoMode else { return }

        let reference = firestore.db.collection(FirestorePaths.vehicleGallery(vehicleId: photo.vehicleId))
            .document(photo.id)
        try await reference.setData(firestore.encode(photo), merge: true)
    }

    func fetchPhotos(vehicleId: String) async throws -> [GalleryPhoto] {
        if AppRuntime.isLocalDemoMode {
            return SeedData.galleryPhotos(for: vehicleId)
        }

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleGallery(vehicleId: vehicleId))
            .order(by: "displayOrder")
            .limit(to: 100)
            .getDocuments()

        return try snapshot.documents.map { try firestore.decode(GalleryPhoto.self, from: $0.data()) }
    }
}
