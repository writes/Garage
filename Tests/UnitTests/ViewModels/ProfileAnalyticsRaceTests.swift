import Testing
@testable import Garage

@MainActor
struct ProfileAnalyticsRaceTests {
    @Test func accountSwitchDuringLoad_cannotReenableAnalyticsFromTheOldProfile() async {
        let analytics = AnalyticsSpy()
        let authService = AuthService(testUID: "first-user", analytics: analytics)
        let store = SuspendedLoadProfileStore()
        let viewModel = ProfileViewModel(
            store: store,
            userID: { authService.uid },
            analytics: analytics,
            isDemoMode: false,
            automaticallyLoad: false
        )
        analytics.setEnabled(true)

        let load = Task { await viewModel.load() }
        await store.waitForLoad()
        authService.switchAuthenticatedUserForTesting(to: "second-user")
        store.finishLoad()
        await load.value

        #expect(viewModel.userProfile == nil)
        #expect(analytics.enabledValues.last == false)
    }

    @Test func accountSwitchDuringOptInSave_cannotReenableAnalytics() async {
        let analytics = AnalyticsSpy()
        let authService = AuthService(testUID: "first-user", analytics: analytics)
        let store = SuspendedSaveProfileStore()
        let viewModel = ProfileViewModel(
            store: store,
            userID: { authService.uid },
            analytics: analytics,
            isDemoMode: false,
            automaticallyLoad: false
        )
        await viewModel.load()

        let optIn = Task { await viewModel.setAnalyticsSharingEnabled(true) }
        await store.waitForSave()
        authService.switchAuthenticatedUserForTesting(to: "second-user")
        store.finishSave()

        let didOptIn = await optIn.value
        #expect(didOptIn == false)
        #expect(viewModel.userProfile == nil)
        #expect(analytics.enabledValues.last == false)
    }
}

@MainActor
private final class SuspendedLoadProfileStore: ProfileStore {
    private var loadStarted = false
    private var loadWaiter: CheckedContinuation<Void, Never>?
    private var loadContinuation: CheckedContinuation<ProfileFields?, Never>?

    func loadProfile(uid _: String) async throws -> ProfileFields? {
        loadStarted = true
        loadWaiter?.resume()
        loadWaiter = nil
        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func saveProfile(_: ProfileFields, uid _: String) async throws {}

    func waitForLoad() async {
        guard !loadStarted else { return }
        await withCheckedContinuation { loadWaiter = $0 }
    }

    func finishLoad() {
        loadContinuation?.resume(returning: ["analyticsOptOut": .boolean(false)])
        loadContinuation = nil
    }
}

@MainActor
private final class SuspendedSaveProfileStore: ProfileStore {
    private var saveStarted = false
    private var saveWaiter: CheckedContinuation<Void, Never>?
    private var saveContinuation: CheckedContinuation<Void, Never>?

    func loadProfile(uid _: String) async throws -> ProfileFields? {
        ["analyticsOptOut": .boolean(true)]
    }

    func saveProfile(_: ProfileFields, uid _: String) async throws {
        saveStarted = true
        saveWaiter?.resume()
        saveWaiter = nil
        await withCheckedContinuation { continuation in
            saveContinuation = continuation
        }
    }

    func waitForSave() async {
        guard !saveStarted else { return }
        await withCheckedContinuation { saveWaiter = $0 }
    }

    func finishSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }
}

@MainActor
struct ProfileAnalyticsConsentTests {
    @Test func toggleBeforeSuccessfulLoad_doesNotWriteProfileFields() async {
        let store = ConsentProfileStore(fields: populatedFields(analyticsOptOut: false))
        let analytics = AnalyticsSpy()
        let viewModel = makeViewModel(store: store, analytics: analytics)

        let didSave = await viewModel.setAnalyticsSharingEnabled(false)

        #expect(!didSave)
        #expect(!viewModel.hasSuccessfullyLoadedProfile)
        #expect(store.savePayloads.isEmpty)
        #expect(analytics.enabledValues == [false])
    }

    @Test func postLoadConsentToggle_writesOnlyAnalyticsFieldAndPreservesProfile() async {
        let initialFields = populatedFields(analyticsOptOut: false)
        let store = ConsentProfileStore(fields: initialFields)
        let analytics = AnalyticsSpy()
        let viewModel = makeViewModel(store: store, analytics: analytics)
        await viewModel.load()

        let didSave = await viewModel.setAnalyticsSharingEnabled(false)

        #expect(didSave)
        #expect(store.savePayloads == [["analyticsOptOut": .boolean(true)]])
        #expect(store.profile?["name"] == initialFields["name"])
        #expect(store.profile?["address"] == initialFields["address"])
        #expect(store.profile?["phone"] == initialFields["phone"])
        #expect(store.profile?["insuranceCompany"] == initialFields["insuranceCompany"])
        #expect(store.profile?["policyNumber"] == initialFields["policyNumber"])
        #expect(viewModel.userProfile?.analyticsOptOut == true)
    }

    @Test func failedOptOut_revertsTheToggleShowsErrorAndStaysFailClosedForSession() async {
        let store = ConsentProfileStore(
            fields: populatedFields(analyticsOptOut: false),
            saveError: ConsentProfileStoreError.save
        )
        let analytics = AnalyticsSpy()
        let viewModel = makeViewModel(store: store, analytics: analytics)
        await viewModel.load()
        let enabledValueCountBeforeAttempt = analytics.enabledValues.count

        let didSave = await viewModel.setAnalyticsSharingEnabled(false)

        #expect(!didSave)
        #expect(viewModel.analyticsOptOut == false)
        #expect(viewModel.error != nil)
        #expect(store.savePayloads == [["analyticsOptOut": .boolean(true)]])
        #expect(!analytics.enabledValues.dropFirst(enabledValueCountBeforeAttempt).isEmpty)
        #expect(analytics.enabledValues.dropFirst(enabledValueCountBeforeAttempt).allSatisfy { !$0 })

        await viewModel.load()

        #expect(analytics.enabledValues.dropFirst(enabledValueCountBeforeAttempt).allSatisfy { !$0 })
    }

    @Test func failedOptIn_revertsTheToggleAndDoesNotEnableCollection() async {
        let store = ConsentProfileStore(
            fields: populatedFields(analyticsOptOut: true),
            saveError: ConsentProfileStoreError.save
        )
        let analytics = AnalyticsSpy()
        let viewModel = makeViewModel(store: store, analytics: analytics)
        await viewModel.load()
        let enabledValueCountBeforeAttempt = analytics.enabledValues.count

        let didSave = await viewModel.setAnalyticsSharingEnabled(true)

        #expect(!didSave)
        #expect(viewModel.analyticsOptOut)
        #expect(viewModel.error != nil)
        #expect(store.savePayloads == [["analyticsOptOut": .boolean(false)]])
        #expect(analytics.enabledValues.dropFirst(enabledValueCountBeforeAttempt).allSatisfy { !$0 })
    }

    @Test func failedInitialLoad_keepsConsentToggleUnavailableAndShowsError() async {
        let store = ConsentProfileStore(loadError: ConsentProfileStoreError.load)
        let analytics = AnalyticsSpy()
        let viewModel = makeViewModel(store: store, analytics: analytics)

        await viewModel.load()

        #expect(!viewModel.hasSuccessfullyLoadedProfile)
        #expect(viewModel.error != nil)
        #expect(analytics.enabledValues.last == false)
    }

    private func makeViewModel(
        store: any ProfileStore,
        analytics: any AnalyticsTracking
    ) -> ProfileViewModel {
        ProfileViewModel(
            store: store,
            userID: { "user" },
            analytics: analytics,
            isDemoMode: false,
            automaticallyLoad: false
        )
    }

    private func populatedFields(analyticsOptOut: Bool) -> ProfileFields {
        [
            "name": .string("Ada Driver"),
            "address": .string("1 Garage Way"),
            "phone": .string("555-1212"),
            "insuranceCompany": .string("Roadworthy"),
            "policyNumber": .string("POL-42"),
            "analyticsOptOut": .boolean(analyticsOptOut)
        ]
    }
}
