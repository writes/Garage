import Testing
@testable import Garage

/// The lazy-tab latch, and the awaiting-first-load flags that keep deferring a tab's fetch from
/// flashing an empty state at an owner who has data. Both halves matter: without the latch the
/// launch fans out every tab's queries, and without the flags the first visit to a deferred tab
/// renders "nothing here" for the frame before its first result lands.
///
/// The flags are per-vehicle. As plain Bools they stayed true once ANY vehicle's load resolved, so
/// switching vehicles reproduced the same flash the flags exist to prevent — the new vehicle's
/// first frame skipped the loading state and rendered the previous vehicle's content instead.
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
        #expect(viewModel.hasCompletedFirstLoad(for: "vehicle") == false)

        await viewModel.reload(vehicleId: "vehicle")

        // Zero entries AND a completed load: only now may the view say "No log entries yet".
        #expect(viewModel.hasCompletedFirstLoad(for: "vehicle"))
        #expect(viewModel.entries.isEmpty)
    }

    @Test func logViewModel_reportsFirstLoadEvenWhenItFails() async {
        let viewModel = LogViewModel(pageFetch: { _, _, _ in throw AppError.database("offline") })

        await viewModel.reload(vehicleId: "vehicle")

        // A failed load still resolves the tri-state, so the view falls through to its error
        // branch instead of spinning forever.
        #expect(viewModel.hasCompletedFirstLoad(for: "vehicle"))
        #expect(viewModel.error != nil)
    }

    @Test func logViewModel_reportsFirstLoadForTheLoadedVehicleOnly() async {
        let viewModel = LogViewModel(entryService: EntryService(testEntries: []))

        await viewModel.reload(vehicleId: "vehicle-a")

        #expect(viewModel.hasCompletedFirstLoad(for: "vehicle-a"))
        #expect(viewModel.hasCompletedFirstLoad(for: "vehicle-b") == false)
    }

    /// `allEntries` holds one vehicle at a time, so the flag is single-slot to match: switching to
    /// B shows loading until B's own page lands, and coming back to A shows loading again rather
    /// than the rows B's load replaced.
    @Test func logViewModel_switchingVehiclesReshowsLoadingUntilTheNewVehicleResolves() async {
        let probe = InFlightFirstLoadProbe()
        let viewModel = LogViewModel(pageFetch: { query, _, _ in
            probe.observe(query.vehicleId)
            return EntryPage(entries: [], nextCursor: nil)
        })
        probe.isResolved = { [weak viewModel] in viewModel?.hasCompletedFirstLoad(for: $0) ?? false }

        await viewModel.reload(vehicleId: "vehicle-a")
        await viewModel.reload(vehicleId: "vehicle-b")

        #expect(probe.wasResolvedMidLoad == false)
        #expect(viewModel.hasCompletedFirstLoad(for: "vehicle-b"))
        #expect(viewModel.hasCompletedFirstLoad(for: "vehicle-a") == false)
    }

    @Test func statsViewModel_reportsFirstLoadOnlyAfterItResolves() async {
        let viewModel = StatsViewModel(contentLoader: { _ in
            StatsViewModel.StatsContent(entries: [], wearItems: [])
        })
        #expect(viewModel.hasCompletedFirstLoad(for: "vehicle") == false)

        await viewModel.load(vehicleId: "vehicle", isPro: true)

        #expect(viewModel.hasCompletedFirstLoad(for: "vehicle"))
        #expect(viewModel.hasContent == false)
    }

    @Test func statsViewModel_switchingVehiclesReshowsLoadingUntilTheNewVehicleResolves() async {
        let probe = InFlightFirstLoadProbe()
        let viewModel = StatsViewModel(
            entryService: EntryService(testEntries: []),
            wearFetch: { vehicleId in
                probe.observe(vehicleId)
                return []
            }
        )
        probe.isResolved = { [weak viewModel] in viewModel?.hasCompletedFirstLoad(for: $0) ?? false }

        await viewModel.load(vehicleId: "vehicle-a", isPro: true)
        await viewModel.load(vehicleId: "vehicle-b", isPro: true)

        #expect(probe.wasResolvedMidLoad == false)
        #expect(viewModel.hasCompletedFirstLoad(for: "vehicle-b"))
        #expect(viewModel.hasCompletedFirstLoad(for: "vehicle-a") == false)
    }
}

/// Reads the flag from INSIDE an in-flight load — the frame a vehicle switch used to render with
/// the PREVIOUS vehicle's flag still set. Holds a closure rather than the view model itself because
/// it has to be passed to that view model's own initializer.
@MainActor private final class InFlightFirstLoadProbe {
    var isResolved: (@MainActor (String) -> Bool)?
    private(set) var wasResolvedMidLoad: Bool?

    func observe(_ vehicleId: String) {
        wasResolvedMidLoad = isResolved?(vehicleId)
    }
}
