import Testing
@testable import Garage

@MainActor
struct AppStateTests {
    @Test func bootstrapLoadsOptInAndPaywallThenSignOutAppliesPrivacyState() async {
        let analytics = AnalyticsSpy()
        let crashReporter = CrashReporterSpy()
        let purchaseService = PurchaseService(testIsPro: false)
        let authService = AuthService(testUID: "user", analytics: analytics)
        let profileStore = AppStateProfileStore(fields: ["analyticsOptOut": .boolean(false)])
        let state = AppState(
            authService: authService,
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: analytics,
            crashReporter: crashReporter,
            profileStore: profileStore
        )

        await state.bootstrap()

        #expect(state.userProfile?.id == "user")
        #expect(state.userProfile?.analyticsOptOut == false)
        #expect(analytics.enabledValues.last == true)
        #expect(crashReporter.enabledValues.last == true)

        state.paywallDidAppear(source: .settings)

        #expect(analytics.events == [.paywallViewed(source: .settings)])
        #expect(analytics.events.map(\.definition) == [
            AnalyticsEventDefinition(name: "paywall_viewed", parameters: [.source(.settings)])
        ])

        state.signOut()

        #expect(analytics.enabledValues.last == false)
        #expect(crashReporter.enabledValues.last == false)
    }

    @Test func applyProfileOptOutDisablesBothTrackersMidSession() async {
        let analytics = AnalyticsSpy()
        let crashReporter = CrashReporterSpy()
        let purchaseService = PurchaseService(testIsPro: false)
        let state = AppState(
            authService: AuthService(testUID: "user", analytics: analytics),
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: analytics,
            crashReporter: crashReporter,
            profileStore: AppStateProfileStore(fields: ["analyticsOptOut": .boolean(false)])
        )
        await state.bootstrap()
        #expect(crashReporter.enabledValues.last == true)

        // The settings toggle path: an opted-out profile arrives via applyProfile mid-session
        // and BOTH trackers must follow (Crashlytics persisted its enabled flag).
        guard var profile = state.userProfile else {
            Issue.record("Expected a bootstrapped profile")
            return
        }
        profile.analyticsOptOut = true
        state.applyProfile(profile)

        #expect(analytics.enabledValues.last == false)
        #expect(crashReporter.enabledValues.last == false)
    }

    @Test func unconfiguredFirebaseProfileStore_rejectsEveryOperation() async {
        let profileStore = ProfileStoreFactory.makeDefault(
            isLocalDemoMode: false,
            isFirebaseConfigured: false
        )
        let expectedError = AppError.database("Firebase is not configured")
        let fields: ProfileFields = ["name": .string("Garage")]

        do {
            _ = try await profileStore.loadProfile(uid: "user")
            Issue.record("Expected loadProfile to throw \(expectedError).")
        } catch let error as AppError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected \(expectedError), got \(error).")
        }

        do {
            try await profileStore.saveProfile(fields, uid: "user")
            Issue.record("Expected saveProfile to throw \(expectedError).")
        } catch let error as AppError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected \(expectedError), got \(error).")
        }

        do {
            try await profileStore.saveProfileFields(fields, uid: "user")
            Issue.record("Expected saveProfileFields to throw \(expectedError).")
        } catch let error as AppError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected \(expectedError), got \(error).")
        }
    }

    @Test func unconfiguredFirebaseProfileStore_keepsBootstrapAndAnalyticsFailClosed() async {
        let analytics = AnalyticsSpy()
        let purchaseService = PurchaseService(testIsPro: false)
        let authService = AuthService(testUID: "user", analytics: analytics)
        let profileStore = ProfileStoreFactory.makeDefault(
            isLocalDemoMode: false,
            isFirebaseConfigured: false
        )
        let state = AppState(
            authService: authService,
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: analytics,
            crashReporter: NoopCrashReporter(),
            profileStore: profileStore
        )

        await state.bootstrap()

        #expect(state.userProfile == nil)
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
            crashReporter: NoopCrashReporter(),
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
