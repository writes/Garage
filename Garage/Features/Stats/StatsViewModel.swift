import Observation

@MainActor
@Observable
final class StatsViewModel {
    struct StatsContent: Sendable {
        var entries: [FirestoreEntry]
        var wearItems: [WearItem]
    }

    /// `isPro` rides in the key alongside vehicle + revision: a Pro flip changes nothing about the
    /// vehicle's data (no bump), but the charts must still reload once entitlement unlocks them.
    /// Folding it into one struct comparison is simpler than a second "clear on isPro change" path.
    private struct LoadKey: Equatable {
        let vehicleId: String
        let revision: Int
        let isPro: Bool
    }

    /// Stats reports a LIFETIME total, so it walks the vehicle's whole history rather than one
    /// page. Same page size as the export walk (`ExportViewModel.exportPageSize`): both trade a
    /// larger single read against fewer round-trips for the same reason.
    static let statsPageSize = 500

    private let entryService: EntryService
    private let revisionStore: VehicleDataRevisionStore
    private let gateEnabled: Bool
    private let pageSize: Int
    /// Closure seam rather than injected services: `EntryService`/`WearService` are concrete final
    /// classes with `.shared` singletons, so a unit test cannot substitute them. Mirrors the same
    /// seam `LogViewModel` uses for paging.
    private let contentLoader: ((String) async throws -> StatsContent)?
    /// Second, narrower seam alongside `contentLoader`: a test that exercises the real entry
    /// pagination still must not reach `WearService.shared`, whose `private init` admits no
    /// hermetic double and whose fetch would hit Firestore.
    private let wearFetch: @MainActor (String) async throws -> [WearItem]

    private(set) var entries: [FirestoreEntry] = []
    private(set) var wearItems: [WearItem] = []
    private(set) var error: AppError?
    private(set) var isLoading = false
    /// The vehicle whose load has RESOLVED (either way); nil until one has. `hasContent` alone is
    /// also false before the first fetch lands — and Stats is now built on first selection, so that
    /// frame happens on every first visit; without this the tab would greet a Pro owner with "No
    /// stats data yet". Per-vehicle because `entries`/`wearItems` hold one vehicle at a time: as a
    /// Bool it stayed true across a vehicle switch, so the new vehicle's first frame skipped the
    /// loading state and charted the previous one's history.
    private(set) var firstLoadResolvedVehicleId: String?
    var hasContent: Bool { !entries.isEmpty || !wearItems.isEmpty }
    private var reloadToken = 0
    private var lastLoadedKey: LoadKey?

    func hasCompletedFirstLoad(for vehicleId: String) -> Bool {
        firstLoadResolvedVehicleId == vehicleId
    }

    init(
        entryService: EntryService = .shared,
        wearService: WearService = .shared,
        revisionStore: VehicleDataRevisionStore = .shared,
        gateEnabled: Bool = VehicleDataRevisionStore.skipGateIsEnabled,
        pageSize: Int = StatsViewModel.statsPageSize,
        contentLoader: ((String) async throws -> StatsContent)? = nil,
        wearFetch: (@MainActor (String) async throws -> [WearItem])? = nil
    ) {
        self.entryService = entryService
        self.revisionStore = revisionStore
        self.gateEnabled = gateEnabled
        self.pageSize = pageSize
        self.contentLoader = contentLoader
        self.wearFetch = wearFetch ?? { try await wearService.fetchDashboard(vehicleId: $0) }
    }

    func load(vehicleId: String, isPro: Bool) async {
        let currentKey = LoadKey(vehicleId: vehicleId, revision: revisionStore.revision(for: vehicleId), isPro: isPro)
        // Demo/UI-test runtimes never skip: demo writes bump a different counter, and UI-test
        // journeys mutate then re-check views in-process, so a stale match here would hide them.
        if gateEnabled, lastLoadedKey == currentKey { return }
        reloadToken &+= 1
        let token = reloadToken
        // Load-bearing for the empty state: without it, `entries`/`wearItems` are still empty
        // while the fetch is in flight, so every owner WITH data would be told "No stats data yet"
        // until it resolved. Set before the first await, and the view branches on it first.
        isLoading = true
        defer {
            if token == reloadToken {
                isLoading = false
                firstLoadResolvedVehicleId = vehicleId
            }
        }
        do {
            let content: StatsContent
            if let contentLoader {
                content = try await contentLoader(vehicleId)
            } else {
                async let entriesTask = fetchAllEntries(vehicleId: vehicleId)
                async let wearTask = wearFetch(vehicleId)
                let (fetchedEntries, fetchedWear) = try await (entriesTask, wearTask)
                content = StatsContent(entries: fetchedEntries, wearItems: fetchedWear)
            }
            guard token == reloadToken else { return }
            entries = content.entries
            wearItems = content.wearItems
            error = nil
            lastLoadedKey = currentKey
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
            lastLoadedKey = nil
        }
    }

    /// Walks every page of the vehicle's history. The single-page fetch this replaces capped the
    /// screen's "Total" — the one figure here derived rather than replayed — at the most recent 100
    /// entries, so a long-owned car was quoted a lifetime cost that silently excluded its earliest
    /// years. The single-argument `fetchEntries` overload discards the `hasMore` sentinel, so
    /// nothing downstream could even detect the truncation.
    private func fetchAllEntries(vehicleId: String) async throws -> [FirestoreEntry] {
        let query = EntryQuery(vehicleId: vehicleId)
        var entries: [FirestoreEntry] = []
        var cursor: EntryCursor?
        repeat {
            let page = try await entryService.fetchEntries(query: query, limit: pageSize, after: cursor)
            entries += page.entries
            cursor = page.nextCursor
        } while cursor != nil
        return entries
    }
}
