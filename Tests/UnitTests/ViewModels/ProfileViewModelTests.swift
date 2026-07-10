import Testing
@testable import Garage

@MainActor
struct ProfileViewModelTests {
    @Test func saveThenLoad_roundTripsProfileThroughStoreSeam() async {
        let store = InMemoryProfileStore()
        let first = ProfileViewModel(store: store, userID: { "user" }, isDemoMode: false)
        await first.load()
        first.name = "Ada Driver"
        first.address = "1 Garage Way"
        first.phone = "555-1212"
        first.insuranceCompany = "Roadworthy"
        first.policyNumber = "POL-42"

        let didSave = await first.save()
        #expect(didSave)

        let second = ProfileViewModel(store: store, userID: { "user" }, isDemoMode: false)
        await second.load()

        #expect(second.name == "Ada Driver")
        #expect(second.address == "1 Garage Way")
        #expect(second.phone == "555-1212")
        #expect(second.insuranceCompany == "Roadworthy")
        #expect(second.policyNumber == "POL-42")
        #expect(store.savedUIDs == ["user"])
    }

    @Test func demoMode_loadsAndSavesThroughTheSessionStore() async {
        let store = InMemoryProfileStore()
        let demoStore = DemoSessionStore()
        let viewModel = ProfileViewModel(
            store: store,
            userID: { "user" },
            isDemoMode: true,
            demoStore: demoStore
        )
        await viewModel.load()
        viewModel.name = "Changed locally"

        let didSave = await viewModel.save()
        #expect(didSave)

        #expect(demoStore.profile()["name"] == "Changed locally")
        #expect(viewModel.address == "123 Service Lane")
        #expect(store.savedUIDs.isEmpty)
    }

    @Test func save_preservesAnUnknownExistingProfileKey() async {
        let store = InMemoryProfileStore(profiles: ["user": ["futureProfileKey": "preserve me"]])
        let viewModel = ProfileViewModel(store: store, userID: { "user" }, isDemoMode: false)
        await viewModel.load()
        viewModel.name = "Ada Driver"

        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(store.profile(uid: "user")?["futureProfileKey"] == "preserve me")
        #expect(store.profile(uid: "user")?["name"] == "Ada Driver")
    }
}

@MainActor
private final class InMemoryProfileStore: ProfileStore {
    private var profiles: [String: [String: String]]
    private(set) var savedUIDs: [String] = []

    init(profiles: [String: [String: String]] = [:]) {
        self.profiles = profiles
    }

    func loadProfile(uid: String) async throws -> [String: String]? {
        profiles[uid]
    }

    func saveProfile(_ fields: [String: String], uid: String) async throws {
        profiles[uid, default: [:]].merge(fields) { _, replacement in replacement }
        savedUIDs.append(uid)
    }

    func profile(uid: String) -> [String: String]? {
        profiles[uid]
    }
}
