import Observation

@MainActor
@Observable
final class LogViewModel {
    /// Matches ExportViewModel's page-fetch seam: a closure, not just object substitution, so
    /// tests can control fetch timing (e.g. to make a concurrent loadMore() race deterministic).
    typealias EntryPageFetch = @MainActor (EntryQuery, Int, EntryCursor?) async throws -> EntryPage

    /// Vehicle + revision pair already reflected in `allEntries`; matches VehicleDataRevisionStore
    /// semantics used by DashboardViewModel/StatsViewModel.
    private struct LoadKey: Equatable {
        let vehicleId: String
        let revision: Int
    }

    private let revisionStore: VehicleDataRevisionStore
    private let gateEnabled: Bool
    private let pageFetch: EntryPageFetch

    var searchText = ""
    var selectedTypes = Set<EntryType>()
    private(set) var allEntries: [FirestoreEntry] = []
    private(set) var entries: [FirestoreEntry] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    /// True once a reload has RESOLVED (either way). Distinct from `entries.isEmpty`, which is also
    /// true before the first fetch lands — and the Log tab is now built on first selection, so that
    /// frame happens on every first visit. Telling the two apart is what keeps "No log entries yet"
    /// off the screen of an owner who has plenty (the false-empty-state bug, shipped twice).
    private(set) var hasCompletedFirstLoad = false
    private(set) var error: AppError?
    private var reloadToken = 0
    private var lastLoadedKey: LoadKey?
    private var nextCursor: EntryCursor?
    private var loadedVehicleId: String?

    /// Whether older history beyond `allEntries` is still available via loadMore().
    var hasMoreEntries: Bool { nextCursor != nil }

    init(
        entryService: EntryService = .shared,
        revisionStore: VehicleDataRevisionStore = .shared,
        gateEnabled: Bool = VehicleDataRevisionStore.skipGateIsEnabled,
        pageFetch: EntryPageFetch? = nil
    ) {
        self.revisionStore = revisionStore
        self.gateEnabled = gateEnabled
        self.pageFetch = pageFetch ?? { query, limit, cursor in
            try await entryService.fetchEntries(query: query, limit: limit, after: cursor)
        }
    }

    /// Fetches the vehicle's newest `Constants.logPageSize` entries, then filters client-side.
    /// Search and type changes re-filter the cached page without re-fetching, so a keystroke never
    /// triggers a Firestore round-trip — but search only covers the entries currently loaded, not
    /// the vehicle's full history. Call loadMore() to pull older entries into the loaded set.
    ///
    /// One page, not the whole 500-entry cap: a revision bump (any write, any screen) re-runs this,
    /// and the tab renders a dozen rows. Deeper history is paged in on demand.
    func reload(vehicleId: String) async {
        let currentKey = LoadKey(vehicleId: vehicleId, revision: revisionStore.revision(for: vehicleId))
        // Demo/UI-test runtimes never skip: demo writes bump a different counter, and UI-test
        // journeys mutate then re-check views in-process, so a stale match here would hide them.
        if gateEnabled, lastLoadedKey == currentKey { return }
        reloadToken &+= 1
        let token = reloadToken
        isLoading = true
        defer {
            if token == reloadToken {
                isLoading = false
                hasCompletedFirstLoad = true
            }
        }

        do {
            let query = EntryQuery(vehicleId: vehicleId, entryTypes: [], searchText: "")
            let page = try await pageFetch(query, Constants.logPageSize, nil)
            guard token == reloadToken else { return }
            loadedVehicleId = vehicleId
            allEntries = page.entries
            nextCursor = page.nextCursor
            applyFilter()
            error = nil
            lastLoadedKey = currentKey
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
            lastLoadedKey = nil
        }
    }

    /// Appends the next page of older history, resuming from `nextCursor` — which the fetch anchored
    /// on the last DOCUMENT of the previous page, not its last decoded entry, so a skipped corrupt
    /// document is paged PAST rather than looped on. Passing that cursor straight back through
    /// unmodified is the whole contract; this method must never derive its own from `allEntries`.
    /// Not revision-gated (it's additive, not a reload).
    /// Three guards: concurrent taps (isLoadingMore); an in-flight reload() (isLoading) — reload()
    /// only replaces nextCursor/loadedVehicleId on success, so without this a loadMore() racing a
    /// vehicle-switching reload() could fire using the PREVIOUS vehicle's still-stale cursor; and
    /// a vehicle switch completing mid-flight, caught by re-checking reloadToken below.
    func loadMore() async {
        guard !isLoading, !isLoadingMore, let cursor = nextCursor, let vehicleId = loadedVehicleId else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let token = reloadToken
        do {
            let query = EntryQuery(vehicleId: vehicleId, entryTypes: [], searchText: "")
            let page = try await pageFetch(query, Constants.logPageSize, cursor)
            guard token == reloadToken else { return }
            allEntries += page.entries
            nextCursor = page.nextCursor
            applyFilter()
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
        }
    }

    func applyFilter() {
        let byType = selectedTypes.isEmpty
            ? allEntries
            : allEntries.filter { selectedTypes.contains($0.entryType) }
        entries = EntryService.filter(byType, with: searchText)
    }
}
