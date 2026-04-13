import FirebaseFirestore
import Foundation

@MainActor
final class FirestoreService {
    static let shared = FirestoreService()

    let db = Firestore.firestore()
    private let encoder = Firestore.Encoder()
    private let decoder = Firestore.Decoder()

    private init() {}

    func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        try encoder.encode(value)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: [String: Any]) throws -> T {
        try decoder.decode(type, from: data)
    }
}
