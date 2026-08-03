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

/// Tester feedback was "themes don't do anything": a free user used to see a text-only Pro gate
/// with no swatches at all. The grid is now shown to everyone — locked for non-subscribers, and
/// still never applied for them (the client-cosmetic Pro gate is enforcement; the preview is
/// marketing).
@MainActor
struct ThemePickerRowTests {
    @Test func nonProSeesEverySchemeListedAndEveryOneLocked() {
        let rows = ThemePickerRow.rows(isPro: false)

        #expect(rows.map(\.scheme) == AccentScheme.allCases)
        #expect(rows.allSatisfy { $0.isLocked })
    }

    @Test func proSeesEverySchemeUnlockedInTheSameOrder() {
        let rows = ThemePickerRow.rows(isPro: true)

        #expect(rows.map(\.scheme) == AccentScheme.allCases)
        #expect(rows.allSatisfy { !$0.isLocked })
    }

    /// A locked row is a paywall entry point, not a selectable option, so it must never answer to
    /// the `theme.option.*` identifier a selection test drives.
    @Test func lockedAndSelectableRowsUseSeparateIdentifierNamespaces() {
        let locked = ThemePickerRow.rows(isPro: false)
        let selectable = ThemePickerRow.rows(isPro: true)

        #expect(locked.map(\.accessibilityIdentifier) == [
            "themes.locked.row.classic",
            "themes.locked.row.graphite",
            "themes.locked.row.marine",
            "themes.locked.row.plum"
        ])
        #expect(selectable.allSatisfy { $0.accessibilityIdentifier == "theme.option.\($0.scheme.rawValue)" })
    }

    /// Both the gate CTA and every locked row route through the one `.themePicker` source, so the
    /// surface keeps a single exposure denominator instead of two half-counted funnels.
    @Test func lockedRowTapPresentsTheThemePickerPaywallAndAddsNoEventOfItsOwn() {
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let router = AppRouter(hasVehicles: { true }, analytics: analytics)

        router.present(.subscription(.themePicker))

        #expect(router.activeSheet == .subscription(.themePicker))
        #expect(analytics.events.isEmpty)
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
