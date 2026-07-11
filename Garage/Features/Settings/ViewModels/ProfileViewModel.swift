import FirebaseFirestore
import Observation
@MainActor
protocol ProfileStore {
    func loadProfile(uid: String) async throws -> ProfileFields?
    func saveProfile(_ fields: ProfileFields, uid: String) async throws
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
private final class DemoProfileStore: ProfileStore {
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
}
#endif
@MainActor
@Observable
final class ProfileViewModel {
    private let store: any ProfileStore
    private let userID: () -> String?
    private let analytics: any AnalyticsTracking
#if DEBUG
    private let isDemoMode: Bool
#endif
    var name = ""
    var address = ""
    var phone = ""
    var insuranceCompany = ""
    var policyNumber = ""
    var analyticsOptOut = true
    private(set) var userProfile: UserProfile?
    private(set) var error: AppError?
#if DEBUG
    init(
        store: (any ProfileStore)? = nil,
        userID: @escaping () -> String? = { AuthService.shared.uid },
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        isDemoMode: Bool = AppRuntime.isLocalDemoMode,
        demoStore: DemoSessionStore = .shared,
        automaticallyLoad: Bool = true
    ) {
        self.userID = userID
        self.analytics = analytics
        self.isDemoMode = isDemoMode
        self.store = isDemoMode ? DemoProfileStore(demoStore: demoStore) : (store ?? FirestoreProfileStore())
        if automaticallyLoad {
            Task { [weak self] in
                await self?.load()
            }
        }
    }
#else
    init(
        store: (any ProfileStore)? = nil,
        userID: @escaping () -> String? = { AuthService.shared.uid },
        analytics: any AnalyticsTracking = AnalyticsService.shared
    ) {
        self.userID = userID
        self.analytics = analytics
        self.store = store ?? ProfileStoreFactory.makeDefault()
        Task { [weak self] in
            await self?.load()
        }
    }
#endif
    func load() async {
        guard let uid = resolvedUserID() else {
            error = .auth("Not authenticated")
            userProfile = nil
            analytics.setEnabled(false)
            return
        }
        do {
            let profile = try await Self.loadProfile(uid: uid, store: store)
            guard resolvedUserID() == uid else {
                userProfile = nil
                analytics.setEnabled(false)
                return
            }
            apply(profile)
            userProfile = profile
            analytics.setEnabled(!profile.analyticsOptOut)
            error = nil
        } catch {
            analytics.setEnabled(false)
            self.error = AppError(from: error)
        }
    }
    @discardableResult
    func save() async -> Bool {
        guard let uid = resolvedUserID() else {
            error = .auth("Not authenticated")
            return false
        }
        do {
            let profile = makeProfile(uid: uid)
            try await store.saveProfile(profile.profileFields, uid: uid)
            guard resolvedUserID() == uid else {
                userProfile = nil
                analytics.setEnabled(false)
                return false
            }
            userProfile = profile
            error = nil
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }
    /// Persists consent before enabling collection; a failed opt-in remains disabled.
    @discardableResult
    func setAnalyticsSharingEnabled(_ enabled: Bool) async -> Bool {
        let expectedUserID = resolvedUserID()
        let previousOptOut = analyticsOptOut
        analyticsOptOut = !enabled
        if !enabled {
            analytics.setEnabled(false)
        }
        let didSave = await save()
        guard let expectedUserID, resolvedUserID() == expectedUserID else {
            analyticsOptOut = previousOptOut
            userProfile = nil
            analytics.setEnabled(false)
            return false
        }
        if didSave {
            analytics.setEnabled(enabled)
            return true
        }
        if enabled {
            analyticsOptOut = previousOptOut
        }
        if let uid = resolvedUserID() {
            userProfile = makeProfile(uid: uid)
        }
        analytics.setEnabled(false)
        return false
    }
    static func loadProfile(uid: String, store: any ProfileStore) async throws -> UserProfile {
        let fields = try await store.loadProfile(uid: uid) ?? [:]
        return UserProfile(id: uid, profileFields: fields)
    }
    private func makeProfile(uid: String) -> UserProfile {
        UserProfile(
            id: uid, email: nil, name: name, address: address, phone: phone,
            insuranceCompany: insuranceCompany, policyNumber: policyNumber,
            analyticsOptOut: analyticsOptOut, createdAt: nil, updatedAt: nil
        )
    }
    private func apply(_ profile: UserProfile) {
        name = profile.name ?? ""
        address = profile.address ?? ""
        phone = profile.phone ?? ""
        insuranceCompany = profile.insuranceCompany ?? ""
        policyNumber = profile.policyNumber ?? ""
        analyticsOptOut = profile.analyticsOptOut
    }
    private func resolvedUserID() -> String? {
#if DEBUG
        if isDemoMode {
            return AppRuntime.demoUserId
        }
#endif
        return userID()
    }
}
