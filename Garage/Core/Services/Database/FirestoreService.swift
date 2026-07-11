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

@MainActor
protocol ProfileStore {
    func loadProfile(uid: String) async throws -> ProfileFields?
    func saveProfile(_ fields: ProfileFields, uid: String) async throws
    func saveProfileFields(_ fields: ProfileFields, uid: String) async throws
}

extension ProfileStore {
    func saveProfileFields(_ fields: ProfileFields, uid: String) async throws {
        try await saveProfile(fields, uid: uid)
    }
}

/// The small document seam keeps Firestore's `setData` payload semantics testable.
@MainActor
protocol ProfileDocument {
    func getData() async throws -> [String: Any]?
    func setData(_ data: [String: Any], merge: Bool) async throws
}

@MainActor
private final class FirebaseProfileDocument: ProfileDocument {
    private let document: DocumentReference

    init(document: DocumentReference) {
        self.document = document
    }

    func getData() async throws -> [String: Any]? {
        try await document.getDocument().data()
    }

    func setData(_ data: [String: Any], merge: Bool) async throws {
        try await document.setData(data, merge: merge)
    }
}

@MainActor
final class FirestoreProfileStore: ProfileStore {
    private let documentForUser: (String) -> any ProfileDocument

    init(firestore: FirestoreService = .shared) {
        documentForUser = { uid in
            FirebaseProfileDocument(
                document: firestore.db.collection(FirestorePaths.users).document(uid)
            )
        }
    }

    init(documentForUser: @escaping (String) -> any ProfileDocument) {
        self.documentForUser = documentForUser
    }

    func loadProfile(uid: String) async throws -> ProfileFields? {
        guard let values = try await documentForUser(uid).getData()?["profile"] as? [String: Any] else { return nil }
        return values.reduce(into: [:]) { fields, value in
            if let profileValue = ProfileFieldValue(firestoreValue: value.value) {
                fields[value.key] = profileValue
            }
        }
    }

    func saveProfile(_ fields: ProfileFields, uid: String) async throws {
        try await saveProfileFields(fields, uid: uid)
    }

    func saveProfileFields(_ fields: ProfileFields, uid: String) async throws {
        // `setData(merge: true)` deep-merges this map, preserving unknown keys
        // added by a newer app version. Dotted keys would be literal top-level
        // fields here; only Firestore's `updateData` interprets dot paths.
        let values = fields.mapValues(\.firestoreValue)
        try await documentForUser(uid).setData(["profile": values], merge: true)
    }
}

private extension ProfileFieldValue {
    init?(firestoreValue: Any) {
        if let value = firestoreValue as? Bool {
            self = .boolean(value)
        } else if let value = firestoreValue as? String {
            self = .string(value)
        } else {
            return nil
        }
    }

    var firestoreValue: Any {
        switch self {
        case .string(let value): value
        case .boolean(let value): value
        }
    }
}

@MainActor
enum ProfileStoreFactory {
    static func makeDefault() -> any ProfileStore {
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return DemoProfileStore()
        }
#endif
        return FirestoreProfileStore()
    }
}

#if DEBUG
@MainActor
final class DemoProfileStore: ProfileStore {
    private let demoStore: DemoSessionStore

    init(demoStore: DemoSessionStore = .shared) {
        self.demoStore = demoStore
    }

    func loadProfile(uid _: String) async throws -> ProfileFields? {
        demoStore.profile()
    }

    func saveProfile(_ fields: ProfileFields, uid _: String) async throws {
        demoStore.saveProfile(fields)
    }

    func saveProfileFields(_ fields: ProfileFields, uid _: String) async throws {
        demoStore.saveProfileFields(fields)
    }
}
#endif
