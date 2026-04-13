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
}
