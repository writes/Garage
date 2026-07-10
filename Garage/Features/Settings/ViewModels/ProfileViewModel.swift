import FirebaseFirestore
import Observation

@MainActor
protocol ProfileStore {
    func loadProfile(uid: String) async throws -> [String: String]?
    func saveProfile(_ fields: [String: String], uid: String) async throws
}

@MainActor
final class FirestoreProfileStore: ProfileStore {
    private let firestore: FirestoreService

    init(firestore: FirestoreService = .shared) {
        self.firestore = firestore
    }

    func loadProfile(uid: String) async throws -> [String: String]? {
        let snapshot = try await firestore.db.collection(FirestorePaths.users).document(uid).getDocument()
        guard let values = snapshot.data()?["profile"] as? [String: Any] else { return nil }
        return values.reduce(into: [:]) { fields, value in
            if let text = value.value as? String {
                fields[value.key] = text
            }
        }
    }

    func saveProfile(_ fields: [String: String], uid: String) async throws {
        try await firestore.db.collection(FirestorePaths.users).document(uid).setData(
            ["profile": fields],
            merge: true
        )
    }
}

@MainActor
@Observable
final class ProfileViewModel {
    private let store: (any ProfileStore)?
    private let userID: () -> String?
#if DEBUG
    private let isDemoMode: Bool
    private let demoStore: DemoSessionStore
#endif

    var name = ""
    var address = ""
    var phone = ""
    var insuranceCompany = ""
    var policyNumber = ""
    private(set) var error: AppError?

#if DEBUG
    init(
        store: (any ProfileStore)? = nil,
        userID: @escaping () -> String? = { AuthService.shared.uid },
        isDemoMode: Bool = AppRuntime.isLocalDemoMode,
        demoStore: DemoSessionStore = .shared
    ) {
        self.userID = userID
        self.isDemoMode = isDemoMode
        self.demoStore = demoStore
        if isDemoMode {
            self.store = store
        } else {
            self.store = store ?? FirestoreProfileStore()
        }
        Task { [weak self] in
            await self?.load()
        }
    }
#else
    init(
        store: (any ProfileStore)? = nil,
        userID: @escaping () -> String? = { AuthService.shared.uid }
    ) {
        self.userID = userID
        self.store = store ?? FirestoreProfileStore()
        Task { [weak self] in
            await self?.load()
        }
    }
#endif

    func load() async {
#if DEBUG
        if isDemoMode {
            apply(demoStore.profile())
            return
        }
#endif
        guard let uid = userID() else {
            error = .auth("Not authenticated")
            return
        }
        guard let store else {
            error = .database("Profile storage unavailable")
            return
        }

        do {
            apply(try await store.loadProfile(uid: uid) ?? [:])
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }

    @discardableResult
    func save() async -> Bool {
#if DEBUG
        if isDemoMode {
            demoStore.saveProfile(fields)
            error = nil
            return true
        }
#endif
        guard let uid = userID() else {
            error = .auth("Not authenticated")
            return false
        }
        guard let store else {
            error = .database("Profile storage unavailable")
            return false
        }

        do {
            try await store.saveProfile(fields, uid: uid)
            error = nil
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }

    private var fields: [String: String] {
        [
            "name": name,
            "address": address,
            "phone": phone,
            "insuranceCompany": insuranceCompany,
            "policyNumber": policyNumber
        ]
    }

    private func apply(_ fields: [String: String]) {
        name = fields["name"] ?? ""
        address = fields["address"] ?? ""
        phone = fields["phone"] ?? ""
        insuranceCompany = fields["insuranceCompany"] ?? ""
        policyNumber = fields["policyNumber"] ?? ""
    }

}
