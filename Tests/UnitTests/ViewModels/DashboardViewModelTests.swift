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

    // MARK: - Maintenance advisor input (the advisor must not be hostage to fuel-log volume)

    /// THE defect: the advisor read the dashboard's type-agnostic recent slice, so an owner who
    /// logged more fill-ups than `historyDepth` since their last service pushed every oil change
    /// out of the window — and was told "never logged" for a car serviced a year ago.
    @Test func advisorHistoryFindsAnOilChangeBuriedUnderSixtyLaterFuelEntries() async throws {
        let oilChange = advisorEntry(id: "oil", type: .oilChange, daysAgo: 400, odometer: 40_000)
        let fuel = (0..<60).map {
            advisorEntry(id: "fuel-\($0)", type: .fuel, daysAgo: Double($0), odometer: 50_000)
        }
        let entryService = EntryService(testEntries: fuel + [oilChange])
        let viewModel = DashboardViewModel(entryService: entryService)

        let advisorInput = await viewModel.advisorHistory(vehicleId: "vehicle")
        #expect(advisorInput.map(\.id) == ["oil"])

        // The pre-fix input, for contrast: the recent slice at the same depth is fuel end to end.
        let recent = try await entryService.fetchRecent(
            vehicleId: "vehicle", limit: DashboardViewModel.historyDepth
        )
        #expect(recent.count == DashboardViewModel.historyDepth)
        #expect(!recent.contains { $0.entryType == .oilChange })
    }

    /// The narrowed fetch must not leak another vehicle's service history into this one's advice.
    @Test func advisorHistoryIsScopedToTheRequestedVehicle() async {
        var otherVehicle = advisorEntry(id: "other-oil", type: .oilChange, daysAgo: 10, odometer: 10_000)
        otherVehicle.vehicleId = "vehicle-b"
        let entryService = EntryService(testEntries: [
            advisorEntry(id: "oil", type: .oilChange, daysAgo: 400, odometer: 40_000), otherVehicle
        ])
        let viewModel = DashboardViewModel(entryService: entryService)

        let advisorInput = await viewModel.advisorHistory(vehicleId: "vehicle")
        #expect(advisorInput.map(\.id) == ["oil"])
    }

    /// The end state the owner sees: a real overdue verdict rather than the "never logged" the
    /// fuel-buried window used to produce.
    @Test func adviceComesFromTheNarrowedFetchNotTheFuelHeavyFeed() async {
        let fuel = (0..<50).map {
            advisorEntry(id: "fuel-\($0)", type: .fuel, daysAgo: Double($0), odometer: 50_000)
        }
        let oilChange = advisorEntry(id: "oil", type: .oilChange, daysAgo: 400, odometer: 40_000)
        let viewModel = DashboardViewModel(contentLoader: { _ in
            DashboardContent(
                entries: fuel, advisorEntries: [oilChange],
                wearItems: [], reminders: [], warranties: [], recalls: []
            )
        })

        await viewModel.loadDashboard(vehicleId: "vehicle")

        let oil = viewModel.maintenanceDue.first { $0.item == .oilAndFilter }
        #expect(oil?.status == .overdue)
        #expect(oil?.milesPastDue == 5_000)
        #expect(oil?.lastServicedAt == oilChange.entryDate)
    }

    /// Regression guard on the union: the advisor's own fetch is narrowed, but "has any history at
    /// all" still comes from the feed, so a fuel-only vehicle keeps its four `neverLogged` rows
    /// instead of falling silent (MaintenanceAdvisor.attentionNeeded returns [] on empty input).
    @Test func aFuelOnlyVehicleStillGetsNeverLoggedAdviceWithAnEmptyAdvisorFetch() async {
        let viewModel = DashboardViewModel(contentLoader: { _ in
            DashboardContent(
                entries: [self.advisorEntry(id: "fuel", type: .fuel, daysAgo: 1, odometer: 50_000)],
                wearItems: [], reminders: [], warranties: [], recalls: []
            )
        })

        await viewModel.loadDashboard(vehicleId: "vehicle")

        #expect(viewModel.maintenanceDue.count == MaintenanceItem.allCases.count)
        #expect(viewModel.maintenanceDue.allSatisfy { $0.status == .neverLogged })
    }

    private func advisorEntry(
        id: String, type: EntryType, daysAgo: Double, odometer: Int
    ) -> FirestoreEntry {
        var entry = dashboardEntry(id: id)
        entry.entryType = type
        entry.entryDate = Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(-daysAgo * 24 * 60 * 60)
        entry.odometerReading = odometer
        return entry
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
