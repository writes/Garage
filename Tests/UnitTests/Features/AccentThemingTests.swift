import Testing
@testable import Garage

@MainActor
struct AccentSchemeTests {
    @Test func rawValueRoundTripsEveryCase() {
        for scheme in AccentScheme.allCases {
            #expect(AccentScheme(rawValue: scheme.rawValue) == scheme)
            #expect(!scheme.displayName.isEmpty)
        }
    }

    @Test func classicIsTheDefaultScheme() {
        #expect(AccentScheme.allCases.first == .classic)
    }

    @Test func applyGracefullyDowngradesUnknownOrEmptyToClassic() {
        AccentStore.shared.apply(themeID: "marine")
        #expect(AccentStore.shared.scheme == .marine)
        AccentStore.shared.apply(themeID: "not-a-scheme")
        #expect(AccentStore.shared.scheme == .classic)
        AccentStore.shared.apply(themeID: "")
        #expect(AccentStore.shared.scheme == .classic)
        AccentStore.shared.apply(themeID: nil)
        #expect(AccentStore.shared.scheme == .classic)
    }
}

@MainActor
struct UserProfileThemeBridgeTests {
    @Test func themeIDRoundTripsThroughProfileFields() {
        var profile = UserProfile(id: "u", profileFields: [:])
        #expect(profile.themeID == nil)
        profile.themeID = "marine"
        let fields = profile.profileFields
        #expect(fields["themeID"] == .string("marine"))
        #expect(UserProfile(id: "u", profileFields: fields).themeID == "marine")
    }

    @Test func missingThemeIDReadsAsNil() {
        #expect(UserProfile(id: "u", profileFields: [:]).themeID == nil)
    }
}

@MainActor
struct ProfileViewModelThemeTests {
    private func makeViewModel(store: any ProfileStore) -> ProfileViewModel {
        ProfileViewModel(store: store, userID: { "user" }, isDemoMode: false, automaticallyLoad: false)
    }

    @Test func setThemeIDWritesOnlyTheThemeFieldAndUpdatesProfile() async {
        let store = ConsentProfileStore()
        let viewModel = makeViewModel(store: store)
        await viewModel.load()

        let didSet = await viewModel.setThemeID("marine")

        #expect(didSet)
        #expect(viewModel.themeID == "marine")
        #expect(store.savePayloads == [["themeID": .string("marine")]])
        #expect(viewModel.userProfile?.themeID == "marine")
    }

    @Test func fullSavePreservesThemeIDInsteadOfWipingIt() async {
        let store = ConsentProfileStore(fields: ["themeID": .string("plum")])
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        #expect(viewModel.themeID == "plum")

        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(store.profile?["themeID"] == .string("plum"))
    }

    @Test func setThemeIDRollsBackInstanceStateOnStoreFailure() async {
        let store = ConsentProfileStore(saveError: ConsentProfileStoreError.save)
        let viewModel = makeViewModel(store: store)
        await viewModel.load()

        let didSet = await viewModel.setThemeID("marine")

        #expect(!didSet)
        #expect(viewModel.themeID == nil)
        #expect(viewModel.error != nil)
    }
}
