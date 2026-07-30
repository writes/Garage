import Testing
@testable import Garage

/// The lazy-tab latch, and the awaiting-first-load flags that keep deferring a tab's fetch from
/// flashing an empty state at an owner who has data. Both halves matter: without the latch the
/// launch fans out every tab's queries, and without the flags the first visit to a deferred tab
/// renders "nothing here" for the frame before its first result lands.
@MainActor
struct LazyTabContentTests {
    @Test func lazyTabLoadState_buildsNothingUntilTheTabIsFirstSelected() {
        var state = LazyTabLoadState()
        #expect(state.shouldRenderContent == false)

        // Launch: another tab is selected. This tab must stay unbuilt — no view, no .task, no fetch.
        state.update(isSelected: false)
        #expect(state.shouldRenderContent == false)

        state.update(isSelected: true)
        #expect(state.shouldRenderContent)
    }

    @Test func lazyTabLoadState_keepsContentAfterSwitchingAway() {
        var state = LazyTabLoadState()
        state.update(isSelected: true)

        // Switching away must NOT tear the tab down: rebuilding it would refetch on every switch,
        // and drop scroll position, filters and already-paged history with it.
        state.update(isSelected: false)
        #expect(state.shouldRenderContent)
    }

    @Test func logViewModel_reportsFirstLoadOnlyAfterItResolves() async {
        let viewModel = LogViewModel(entryService: EntryService(testEntries: []))
        #expect(viewModel.hasCompletedFirstLoad == false)

        await viewModel.reload(vehicleId: "vehicle")

        // Zero entries AND a completed load: only now may the view say "No log entries yet".
        #expect(viewModel.hasCompletedFirstLoad)
        #expect(viewModel.entries.isEmpty)
    }

    @Test func logViewModel_reportsFirstLoadEvenWhenItFails() async {
        let viewModel = LogViewModel(pageFetch: { _, _, _ in throw AppError.database("offline") })

        await viewModel.reload(vehicleId: "vehicle")

        // A failed load still resolves the tri-state, so the view falls through to its error
        // branch instead of spinning forever.
        #expect(viewModel.hasCompletedFirstLoad)
        #expect(viewModel.error != nil)
    }

    @Test func statsViewModel_reportsFirstLoadOnlyAfterItResolves() async {
        let viewModel = StatsViewModel(contentLoader: { _ in
            StatsViewModel.StatsContent(entries: [], wearItems: [])
        })
        #expect(viewModel.hasCompletedFirstLoad == false)

        await viewModel.load(vehicleId: "vehicle", isPro: true)

        #expect(viewModel.hasCompletedFirstLoad)
        #expect(viewModel.hasContent == false)
    }
}
