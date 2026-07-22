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

    @Test func applyVehicleSnapshot_keepsSelectionAndFallsBackWhenRemoved() {
        let purchaseService = PurchaseService(testIsPro: false)
        let state = AppState(
            authService: AuthService(testUID: "user", analytics: AnalyticsSpy()),
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: AnalyticsSpy(),
            crashReporter: NoopCrashReporter(),
            profileStore: AppStateProfileStore(fields: [:])
        )
        let first = snapshotVehicle(id: "first", displayOrder: 0)
        let second = snapshotVehicle(id: "second", displayOrder: 1)

        state.applyVehicleSnapshot(envelope([first, second]))
        #expect(state.vehicles.map(\.id) == ["first", "second"])
        #expect(state.currentVehicle?.id == "first")

        state.selectVehicle(second)
        var renamed = second
        renamed.nickname = "Renamed"
        state.applyVehicleSnapshot(envelope([first, renamed]))
        #expect(state.currentVehicle?.nickname == "Renamed")

        state.applyVehicleSnapshot(envelope([first]))
        #expect(state.currentVehicle?.id == "first")
    }

    private func envelope(_ vehicles: [Vehicle]) -> VehicleSnapshotEnvelope {
        VehicleSnapshotEnvelope(vehicles: vehicles, isFromCache: false, hasPendingWrites: false)
    }

    private func snapshotVehicle(id: String, displayOrder: Int) -> Vehicle {
        Vehicle(
            id: id, userId: "user", nickname: id, make: "Garage", model: "Test", year: 2026,
            currentOdometer: 1, displayOrder: displayOrder
        )
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
