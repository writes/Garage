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
