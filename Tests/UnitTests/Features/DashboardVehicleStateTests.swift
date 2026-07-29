import Testing
@testable import Garage

/// Regression cover for the cold-launch flash: DashboardView rendered its "Add Your First Vehicle"
/// empty state from `appState.vehicles.isEmpty` alone. That array is empty for two entirely
/// different reasons — the user owns no vehicles, or the first load has not landed yet — and on
/// every cold launch the second one arrives first, so an owner with a full garage was told to add
/// their first vehicle before their cars appeared.
@MainActor
struct DashboardVehicleStateTests {
    @Test func emptyBeforeTheFirstLoadIsNotAnEmptyGarage() {
        let state = DashboardVehicleState.resolve(
            hasCompletedInitialVehicleLoad: false,
            isVehicleListEmpty: true
        )

        #expect(state == .awaitingFirstLoad)
    }

    @Test func populatedBeforeTheFirstLoadStillWaits() {
        // A stale carry-over list must not short-circuit the gate either: the tri-state has one
        // meaning, "no load has completed", regardless of what is currently in the array.
        let state = DashboardVehicleState.resolve(
            hasCompletedInitialVehicleLoad: false,
            isVehicleListEmpty: false
        )

        #expect(state == .awaitingFirstLoad)
    }

    @Test func emptyAfterACompletedLoadIsAConfirmedEmptyGarage() {
        let state = DashboardVehicleState.resolve(
            hasCompletedInitialVehicleLoad: true,
            isVehicleListEmpty: true
        )

        #expect(state == .noVehicles)
    }

    @Test func populatedAfterACompletedLoadRendersTheDashboard() {
        let state = DashboardVehicleState.resolve(
            hasCompletedInitialVehicleLoad: true,
            isVehicleListEmpty: false
        )

        #expect(state == .ready)
    }
}
