@preconcurrency import FirebaseStorage
import Foundation
import Observation

@MainActor
@Observable
final class StorageService {
    static let shared = StorageService()

    private let storage = Storage.storage().reference()

    private init() {}

    func upload(data: Data, path: String, contentType: String) async throws -> String {
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        let reference = storage.child(path)

        _ = try await reference.putDataAsync(data, metadata: metadata)
        let url = try await reference.downloadURL()
        return url.absoluteString
    }
}
