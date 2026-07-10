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
    private let store: any ProfileStore
    private let userID: () -> String?
    private let isDemoMode: Bool

    var name = ""
    var address = ""
    var phone = ""
    var insuranceCompany = ""
    var policyNumber = ""
    private(set) var error: AppError?

    init(
        store: any ProfileStore = FirestoreProfileStore(),
        userID: @escaping () -> String? = { AuthService.shared.uid },
        isDemoMode: Bool = AppRuntime.isLocalDemoMode
    ) {
        self.store = store
        self.userID = userID
        self.isDemoMode = isDemoMode
        Task { [weak self] in
            await self?.load()
        }
    }

    func load() async {
        if isDemoMode {
            apply(Self.demoFields)
            return
        }
        guard let uid = userID() else {
            error = .auth("Not authenticated")
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
        guard !isDemoMode else { return true }
        guard let uid = userID() else {
            error = .auth("Not authenticated")
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

    private static let demoFields = [
        "name": "Garage Demo",
        "address": "123 Service Lane",
        "phone": "555-0100",
        "insuranceCompany": "Demo Insurance",
        "policyNumber": "DEMO-0001"
    ]
}
