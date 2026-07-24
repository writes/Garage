import Foundation
import Testing
@testable import Garage

@MainActor
struct DashboardViewModelTests {
    @Test func initialState_isEmptyAndIdle() {
        let viewModel = DashboardViewModel()

        #expect(viewModel.recentEntries.isEmpty)
        #expect(viewModel.wearItems.isEmpty)
        #expect(viewModel.upcomingReminders.isEmpty)
        #expect(viewModel.openRecalls == 0)
        #expect(viewModel.isLoading == false)
    }

    @Test func loadAndRefresh_replaceDashboardContentAfterARevisionBump() async {
        // A bare second load for the same vehicle is now a gated no-op (see the revision-gate
        // tests below); a "refresh" that should actually re-fetch models a live write landing
        // in between, which is what bumps the revision store.
        let revisionStore = VehicleDataRevisionStore()
        var calls = 0
        let viewModel = DashboardViewModel(revisionStore: revisionStore, contentLoader: { _ in
            calls += 1
            return DashboardContent(
                entries: [dashboardEntry(id: "entry-\(calls)")],
                wearItems: [],
                reminders: [],
                warranties: [],
                recalls: []
            )
        })

        await viewModel.loadDashboard(vehicleId: "vehicle")
        revisionStore.bump(vehicleId: "vehicle")
        await viewModel.loadDashboard(vehicleId: "vehicle")

        #expect(calls == 2)
        #expect(viewModel.recentEntries.map(\.id) == ["entry-2"])
        #expect(viewModel.error == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test func load_errorMapsAndLeavesLoadingFalse() async {
        let viewModel = DashboardViewModel(contentLoader: { _ in
            throw NSError(
                domain: NSURLErrorDomain,
                code: -1009,
                userInfo: [NSLocalizedDescriptionKey: "Offline"]
            )
        })

        await viewModel.loadDashboard(vehicleId: "vehicle")

        #expect(viewModel.error == .network("Offline"))
        #expect(viewModel.isLoading == false)
    }

    @Test func revisionGate_sameVehicleAndRevisionSkipsTheSecondFetch() async {
        let revisionStore = VehicleDataRevisionStore()
        var calls = 0
        let viewModel = DashboardViewModel(revisionStore: revisionStore, contentLoader: { _ in
            calls += 1
            return DashboardContent(entries: [], wearItems: [], reminders: [], warranties: [], recalls: [])
        })

        await viewModel.loadDashboard(vehicleId: "vehicle")
        await viewModel.loadDashboard(vehicleId: "vehicle")

        #expect(calls == 1)
    }

    @Test func revisionGate_bumpBetweenLoadsForcesARefetch() async {
        let revisionStore = VehicleDataRevisionStore()
        var calls = 0
        let viewModel = DashboardViewModel(revisionStore: revisionStore, contentLoader: { _ in
            calls += 1
            return DashboardContent(entries: [], wearItems: [], reminders: [], warranties: [], recalls: [])
        })

        await viewModel.loadDashboard(vehicleId: "vehicle")
        revisionStore.bump(vehicleId: "vehicle")
        await viewModel.loadDashboard(vehicleId: "vehicle")

        #expect(calls == 2)
    }

    @Test func revisionGate_vehicleSwitchAlwaysFetchesEvenAtTheSameRevision() async {
        let revisionStore = VehicleDataRevisionStore()
        var calls = 0
        let viewModel = DashboardViewModel(revisionStore: revisionStore, contentLoader: { _ in
            calls += 1
            return DashboardContent(entries: [], wearItems: [], reminders: [], warranties: [], recalls: [])
        })

        await viewModel.loadDashboard(vehicleId: "vehicle-a")
        await viewModel.loadDashboard(vehicleId: "vehicle-b")
        await viewModel.loadDashboard(vehicleId: "vehicle-a")

        #expect(calls == 3)
    }

    @Test func revisionGate_errorClearsTheGateSoARetryRefetches() async {
        let revisionStore = VehicleDataRevisionStore()
        var calls = 0
        let viewModel = DashboardViewModel(revisionStore: revisionStore, contentLoader: { _ in
            calls += 1
            if calls == 1 {
                throw NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [NSLocalizedDescriptionKey: "Offline"])
            }
            return DashboardContent(entries: [], wearItems: [], reminders: [], warranties: [], recalls: [])
        })

        await viewModel.loadDashboard(vehicleId: "vehicle")
        #expect(viewModel.error != nil)
        await viewModel.loadDashboard(vehicleId: "vehicle")

        #expect(calls == 2)
        #expect(viewModel.error == nil)
    }

    @Test func revisionGate_disabledGateAlwaysRefetchesEvenAtTheSameRevision() async {
        // Regression: demo-mode writes bump DemoSessionStore.revision, not this store, and
        // UI-test journeys mutate + re-check views in-process — in both runtimes the gate must
        // not skip. gateEnabled: false models that (DashboardViewModel defaults it from
        // VehicleDataRevisionStore.skipGateIsEnabled, which reads AppRuntime).
        let revisionStore = VehicleDataRevisionStore()
        var calls = 0
        let viewModel = DashboardViewModel(revisionStore: revisionStore, gateEnabled: false, contentLoader: { _ in
            calls += 1
            return DashboardContent(entries: [], wearItems: [], reminders: [], warranties: [], recalls: [])
        })

        await viewModel.loadDashboard(vehicleId: "vehicle")
        await viewModel.loadDashboard(vehicleId: "vehicle")

        #expect(calls == 2)
    }

    private func dashboardEntry(id: String) -> FirestoreEntry {
        FirestoreEntry(
            id: id,
            vehicleId: "vehicle",
            userId: "user",
            entryType: .maintenance,
            entryDate: .now,
            odometerReading: 1,
            cost: nil,
            isDiy: nil,
            shopName: nil,
            notes: nil,
            attachmentPaths: [],
            isResolved: nil,
            details: [:],
            createdAt: nil,
            updatedAt: nil
        )
    }
}
