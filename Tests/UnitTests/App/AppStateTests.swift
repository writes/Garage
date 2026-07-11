import Testing
@testable import Garage

@MainActor
struct AppStateTests {
    @Test func bootstrapLoadsOptInAndPaywallThenSignOutAppliesPrivacyState() async {
        let analytics = AnalyticsSpy()
        let purchaseService = PurchaseService(testIsPro: false)
        let authService = AuthService(testUID: "user", analytics: analytics)
        let profileStore = AppStateProfileStore(fields: ["analyticsOptOut": .boolean(false)])
        let state = AppState(
            authService: authService,
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: analytics,
            profileStore: profileStore
        )

        await state.bootstrap()

        #expect(state.userProfile?.id == "user")
        #expect(state.userProfile?.analyticsOptOut == false)
        #expect(analytics.enabledValues.last == true)

        state.paywallDidAppear(source: .settings)

        #expect(analytics.events == [.paywallViewed(source: .settings)])
        #expect(analytics.events.map(\.definition) == [
            AnalyticsEventDefinition(name: "paywall_viewed", parameters: [.source(.settings)])
        ])

        state.signOut()

        #expect(analytics.enabledValues.last == false)
    }

    @Test func accountSwitchDuringProfileLoad_restartsForTheCurrentAccount() async {
        let analytics = AnalyticsSpy()
        let purchaseService = PurchaseService(testIsPro: false)
        let authService = AuthService(testUID: "first-user", analytics: analytics)
        let profileStore = BlockingProfileStore()
        let state = AppState(
            authService: authService,
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: analytics,
            profileStore: profileStore
        )

        let bootstrap = Task { await state.bootstrap() }
        await profileStore.waitForFirstLoad()

        authService.switchAuthenticatedUserForTesting(to: "second-user")
        profileStore.finishFirstLoad()
        await bootstrap.value

        #expect(profileStore.requestedUIDs == ["first-user", "second-user"])
        #expect(state.userProfile?.id == "second-user")
        #expect(state.userProfile?.analyticsOptOut == false)
        #expect(analytics.enabledValues.last == true)
    }
}

@MainActor
private final class AppStateProfileStore: ProfileStore {
    private var fields: ProfileFields

    init(fields: ProfileFields) {
        self.fields = fields
    }

    func loadProfile(uid _: String) async throws -> ProfileFields? {
        fields
    }

    func saveProfile(_ fields: ProfileFields, uid _: String) async throws {
        self.fields = fields
    }
}

@MainActor
private final class BlockingProfileStore: ProfileStore {
    private var firstLoadStarted = false
    private var firstLoadWaiter: CheckedContinuation<Void, Never>?
    private var firstLoadContinuation: CheckedContinuation<ProfileFields?, Never>?
    private(set) var requestedUIDs: [String] = []

    func loadProfile(uid: String) async throws -> ProfileFields? {
        requestedUIDs.append(uid)
        guard uid == "first-user" else {
            return ["analyticsOptOut": .boolean(false)]
        }

        firstLoadStarted = true
        firstLoadWaiter?.resume()
        firstLoadWaiter = nil
        return await withCheckedContinuation { continuation in
            firstLoadContinuation = continuation
        }
    }

    func saveProfile(_: ProfileFields, uid _: String) async throws {}

    func waitForFirstLoad() async {
        guard !firstLoadStarted else { return }
        await withCheckedContinuation { continuation in
            firstLoadWaiter = continuation
        }
    }

    func finishFirstLoad() {
        firstLoadContinuation?.resume(returning: ["analyticsOptOut": .boolean(false)])
        firstLoadContinuation = nil
    }
}
