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

    @Test func loadAndRefresh_replaceDashboardContent() async {
        var calls = 0
        let viewModel = DashboardViewModel(contentLoader: { _ in
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
