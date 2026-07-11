import Testing
@testable import Garage

@MainActor
struct ProfileViewModelTests {
    @Test func saveThenLoad_roundTripsProfileThroughStoreSeam() async {
        let store = InMemoryProfileStore()
        let first = ProfileViewModel(
            store: store,
            userID: { "user" },
            isDemoMode: false,
            automaticallyLoad: false
        )
        await first.load()
        first.name = "Ada Driver"
        first.address = "1 Garage Way"
        first.phone = "555-1212"
        first.insuranceCompany = "Roadworthy"
        first.policyNumber = "POL-42"

        let didSave = await first.save()
        #expect(didSave)

        let second = ProfileViewModel(
            store: store,
            userID: { "user" },
            isDemoMode: false,
            automaticallyLoad: false
        )
        await second.load()

        #expect(second.name == "Ada Driver")
        #expect(second.address == "1 Garage Way")
        #expect(second.phone == "555-1212")
        #expect(second.insuranceCompany == "Roadworthy")
        #expect(second.policyNumber == "POL-42")
        #expect(second.analyticsOptOut)
        #expect(store.savedUIDs == ["user"])
        #expect(Set(store.savedPayloads[0].keys) == Set([
            "name", "address", "phone", "insuranceCompany", "policyNumber", "analyticsOptOut"
        ]))
    }

    @Test func demoMode_loadsAndSavesThroughTheSessionStore() async {
        let store = InMemoryProfileStore()
        let demoStore = DemoSessionStore()
        let viewModel = ProfileViewModel(
            store: store,
            userID: { "user" },
            isDemoMode: true,
            demoStore: demoStore,
            automaticallyLoad: false
        )
        await viewModel.load()
        viewModel.name = "Changed locally"

        let didSave = await viewModel.save()
        #expect(didSave)

        #expect(demoStore.profile()["name"] == .string("Changed locally"))
        #expect(viewModel.address == "123 Service Lane")
        #expect(store.savedUIDs.isEmpty)
    }

    @Test func save_preservesAnUnknownExistingProfileKey() async {
        let store = InMemoryProfileStore(profiles: ["user": ["futureProfileKey": .string("preserve me")]])
        let viewModel = ProfileViewModel(
            store: store,
            userID: { "user" },
            isDemoMode: false,
            automaticallyLoad: false
        )
        await viewModel.load()
        viewModel.name = "Ada Driver"

        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(store.profile(uid: "user")?["futureProfileKey"] == .string("preserve me"))
        #expect(store.profile(uid: "user")?["name"] == .string("Ada Driver"))
    }

    @Test func firestoreStore_writesTargetedProfileFieldsAsANestedMap() async throws {
        let document = LiteralKeyFirestoreProfileDocument(data: [
            "profile": ["futureProfileKey": "preserve me"]
        ])
        let store = FirestoreProfileStore(documentForUser: { _ in document })

        try await store.saveProfileFields(["analyticsOptOut": .boolean(false)], uid: "user")

        let payload = try #require(document.lastSetData)
        #expect(payload.keys.sorted() == ["profile"])
        let profile = try #require(payload["profile"] as? [String: Any])
        #expect(profile.keys.sorted() == ["analyticsOptOut"])
        #expect(profile["analyticsOptOut"] as? Bool == false)
        #expect(!document.sawDottedTopLevelKey)
        #expect(document.profile?["futureProfileKey"] as? String == "preserve me")
    }

    @Test func missingPreference_defaultsToOptOutAndDisablesCollection() async {
        let analytics = AnalyticsSpy()
        let viewModel = ProfileViewModel(
            store: InMemoryProfileStore(),
            userID: { "user" },
            analytics: analytics,
            isDemoMode: false,
            automaticallyLoad: false
        )

        await viewModel.load()

        #expect(viewModel.analyticsOptOut)
        #expect(analytics.enabledValues.last == false)
    }

    @Test func optIn_persistsBooleanPreferenceAndEnablesCollectionAfterSave() async {
        let store = InMemoryProfileStore()
        let analytics = AnalyticsSpy()
        let viewModel = ProfileViewModel(
            store: store,
            userID: { "user" },
            analytics: analytics,
            isDemoMode: false,
            automaticallyLoad: false
        )
        await viewModel.load()

        let didSave = await viewModel.setAnalyticsSharingEnabled(true)

        #expect(didSave)
        #expect(!viewModel.analyticsOptOut)
        #expect(store.profile(uid: "user")?["analyticsOptOut"] == .boolean(false))
        #expect(store.savedPayloads == [["analyticsOptOut": .boolean(false)]])
        #expect(analytics.enabledValues.last == true)
    }
}

@MainActor
private final class InMemoryProfileStore: ProfileStore {
    private var profiles: [String: ProfileFields]
    private(set) var savedUIDs: [String] = []
    private(set) var savedPayloads: [ProfileFields] = []

    init(profiles: [String: ProfileFields] = [:]) {
        self.profiles = profiles
    }

    func loadProfile(uid: String) async throws -> ProfileFields? {
        profiles[uid]
    }

    func saveProfile(_ fields: ProfileFields, uid: String) async throws {
        profiles[uid, default: [:]].merge(fields) { _, replacement in replacement }
        savedUIDs.append(uid)
        savedPayloads.append(fields)
    }

    func profile(uid: String) -> ProfileFields? {
        profiles[uid]
    }
}

@MainActor
final class ConsentProfileStore: ProfileStore {
    private var fields: ProfileFields
    private let loadError: Error?
    private let saveError: Error?
    private(set) var savePayloads: [ProfileFields] = []

    init(
        fields: ProfileFields = [:],
        loadError: Error? = nil,
        saveError: Error? = nil
    ) {
        self.fields = fields
        self.loadError = loadError
        self.saveError = saveError
    }

    var profile: ProfileFields? {
        fields
    }

    func loadProfile(uid _: String) async throws -> ProfileFields? {
        if let loadError {
            throw loadError
        }
        return fields
    }

    func saveProfile(_ fields: ProfileFields, uid _: String) async throws {
        savePayloads.append(fields)
        if let saveError {
            throw saveError
        }
        self.fields.merge(fields) { _, replacement in replacement }
    }
}

enum ConsentProfileStoreError: Error {
    case load
    case save
}

@MainActor
private final class LiteralKeyFirestoreProfileDocument: ProfileDocument {
    private(set) var lastSetData: [String: Any]?
    private(set) var sawDottedTopLevelKey = false
    private var data: [String: Any]

    init(data: [String: Any]) {
        self.data = data
    }

    var profile: [String: Any]? {
        data["profile"] as? [String: Any]
    }

    func getData() async throws -> [String: Any]? {
        data
    }

    func setData(_ updates: [String: Any], merge: Bool) async throws {
        lastSetData = updates
        sawDottedTopLevelKey = updates.keys.contains { $0.contains(".") }
        guard !sawDottedTopLevelKey else {
            throw LiteralKeyFirestoreError.dottedTopLevelKey
        }

        guard merge, let incomingProfile = updates["profile"] as? [String: Any] else {
            data = updates
            return
        }

        var mergedProfile = profile ?? [:]
        mergedProfile.merge(incomingProfile) { _, replacement in replacement }
        data["profile"] = mergedProfile
    }
}

private enum LiteralKeyFirestoreError: Error {
    case dottedTopLevelKey
}
