import FirebaseCore
import FirebaseFirestore
import Foundation

@MainActor
final class FirestoreService {
    static let shared = FirestoreService()

    /// This is Garage's sole Firestore construction and controlled first use. Keeping it lazy
    /// lets hermetic/local-demo paths exist without resolving Firebase at all.
    private lazy var controlledDatabase: Firestore = {
        let database = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        database.settings = settings
        database.persistentCacheIndexManager?.enableIndexAutoCreation()
        return database
    }()

    var db: Firestore { controlledDatabase }
    private let encoder = Firestore.Encoder()
    private let decoder = Firestore.Decoder()

    private init() {}

    func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        try encoder.encode(value)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: [String: Any]) throws -> T {
        try decoder.decode(type, from: data)
    }

    /// Submits exactly the entry and vehicle merge writes. `WriteBatch.commit` returns after
    /// local acceptance; its callback remains backend acknowledgement/rejection evidence.
    func submitBatch(
        _ writes: [AtomicBatchWrite],
        completion: @escaping @Sendable (String?) -> Void
    ) throws {
        guard writes.count == 2, writes.allSatisfy(\.merge) else {
            throw AppError.database("An entry save requires exactly two atomic writes.")
        }

        let batch = db.batch()
        for write in writes {
            batch.setData(write.data, forDocument: db.document(write.path), merge: write.merge)
        }
        batch.commit { error in
            completion(error?.localizedDescription)
        }
    }

    /// The callback contains only a pre-converted immutable failure message, so callers can
    /// safely route the result back to their main-actor sync reducer.
    func startWriteBarrier(completion: @escaping @Sendable (String?) -> Void) {
        db.waitForPendingWrites { error in
            completion(error?.localizedDescription)
        }
    }
}

@MainActor
struct AtomicBatchWrite {
    let path: String
    let data: [String: Any]
    let merge: Bool

    init(path: String, data: [String: Any], merge: Bool = true) {
        self.path = path
        self.data = data
        self.merge = merge
    }
}

/// Firestore dictionaries and write batches intentionally remain main-actor/non-Sendable.
@MainActor
protocol AtomicBatchSubmitting: AnyObject {
    func submitBatch(
        _ writes: [AtomicBatchWrite],
        completion: @escaping @Sendable (String?) -> Void
    ) throws
}

extension FirestoreService: AtomicBatchSubmitting {}

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
private final class UnconfiguredProfileStore: ProfileStore {
    func loadProfile(uid _: String) async throws -> ProfileFields? {
        throw AppError.database("Firebase is not configured")
    }

    func saveProfile(_: ProfileFields, uid _: String) async throws {
        throw AppError.database("Firebase is not configured")
    }
}

@MainActor
enum ProfileStoreFactory {
    static func makeDefault(
        isLocalDemoMode: Bool = AppRuntime.isLocalDemoMode,
        isFirebaseConfigured: Bool = FirebaseApp.app() != nil
    ) -> any ProfileStore {
#if DEBUG
        if isLocalDemoMode {
            return DemoProfileStore()
        }
#endif

        guard isFirebaseConfigured else {
            return UnconfiguredProfileStore()
        }

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
