import Testing
@testable import Garage

@MainActor
struct AppStateVehicleSnapshotTests {
    @Test func applyVehicleSnapshot_keepsSelectionAndFallsBackWhenRemoved() {
        let purchaseService = PurchaseService(testIsPro: false)
        let state = AppState(
            authService: AuthService(testUID: "user", analytics: AnalyticsSpy()),
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: AnalyticsSpy(),
            crashReporter: NoopCrashReporter(),
            profileStore: EmptyProfileStore()
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

        // An empty live snapshot means an empty garage — never reseeded fixtures.
        state.applyVehicleSnapshot(envelope([]))
        #expect(state.vehicles.isEmpty)
        #expect(state.currentVehicle == nil)
    }

    @Test func applyVehicleSnapshot_retainsKnownCopiesOfUndecodableDocs() {
        let purchaseService = PurchaseService(testIsPro: false)
        let state = AppState(
            authService: AuthService(testUID: "user", analytics: AnalyticsSpy()),
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: AnalyticsSpy(),
            crashReporter: NoopCrashReporter(),
            profileStore: EmptyProfileStore()
        )
        let first = snapshotVehicle(id: "first", displayOrder: 0)
        let second = snapshotVehicle(id: "second", displayOrder: 1)
        state.applyVehicleSnapshot(envelope([first, second]))
        state.selectVehicle(second)

        // A transiently corrupt doc must neither vanish nor steal the selection.
        state.applyVehicleSnapshot(VehicleSnapshotEnvelope(
            vehicles: [first], isFromCache: false, hasPendingWrites: false,
            decodeFailureDocumentIDs: ["second"]
        ))

        #expect(state.vehicles.map(\.id) == ["first", "second"])
        #expect(state.currentVehicle?.id == "second")
    }

    /// Bootstrap no longer fetches vehicles: `VehicleSyncHost`'s single live listener is the
    /// initial load (its snapshot flips the flag — see the test below), and `refreshVehicles()` is
    /// both the user-triggered refresh and the host's fallback when the listener fails before
    /// delivering anything. The flag must still flip on that path, and still reset on sign-out.
    @Test func hasCompletedInitialVehicleLoad_trueAfterRefreshFalseAgainAfterSignOut() async {
        let analytics = AnalyticsSpy()
        let purchaseService = PurchaseService(testIsPro: false)
        let authService = AuthService(testUID: "user", analytics: analytics)
        let state = AppState(
            authService: authService,
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: analytics,
            crashReporter: NoopCrashReporter(),
            profileStore: EmptyProfileStore()
        )
        #expect(state.hasCompletedInitialVehicleLoad == false)

        await state.bootstrap()
        #expect(state.hasCompletedInitialVehicleLoad == false)

        await state.refreshVehicles()
        #expect(state.hasCompletedInitialVehicleLoad == true)

        state.signOut()
        #expect(state.hasCompletedInitialVehicleLoad == false)
    }

    @Test func hasCompletedInitialVehicleLoad_trueAfterApplyVehicleSnapshotEvenWithZeroVehicles() {
        let analytics = AnalyticsSpy()
        let purchaseService = PurchaseService(testIsPro: false)
        let state = AppState(
            authService: AuthService(testUID: "user", analytics: analytics),
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: analytics,
            crashReporter: NoopCrashReporter(),
            profileStore: EmptyProfileStore()
        )
        #expect(state.hasCompletedInitialVehicleLoad == false)

        // Empty on purpose: the flag must flip on a completed load regardless of its result —
        // this is exactly the "confirmed zero vehicles" case AppRouter's gate needs to trust.
        state.applyVehicleSnapshot(VehicleSnapshotEnvelope(vehicles: [], isFromCache: false, hasPendingWrites: false))
        #expect(state.hasCompletedInitialVehicleLoad == true)
        #expect(state.vehicles.isEmpty)
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
}

@MainActor
private final class EmptyProfileStore: ProfileStore {
    func loadProfile(uid _: String) async throws -> ProfileFields? { [:] }
    func saveProfile(_: ProfileFields, uid _: String) async throws {}
}
