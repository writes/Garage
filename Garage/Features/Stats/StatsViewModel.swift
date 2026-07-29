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

    private let entryService: EntryService
    private let wearService: WearService
    private let revisionStore: VehicleDataRevisionStore
    private let gateEnabled: Bool
    /// Closure seam rather than injected services: `EntryService`/`WearService` are concrete final
    /// classes with `.shared` singletons, so a unit test cannot substitute them. Mirrors the same
    /// seam `LogViewModel` uses for paging.
    private let contentLoader: ((String) async throws -> StatsContent)?

    private(set) var entries: [FirestoreEntry] = []
    private(set) var wearItems: [WearItem] = []
    private(set) var error: AppError?
    private(set) var isLoading = false
    var hasContent: Bool { !entries.isEmpty || !wearItems.isEmpty }
    private var reloadToken = 0
    private var lastLoadedKey: LoadKey?

    init(
        entryService: EntryService = .shared,
        wearService: WearService = .shared,
        revisionStore: VehicleDataRevisionStore = .shared,
        gateEnabled: Bool = VehicleDataRevisionStore.skipGateIsEnabled,
        contentLoader: ((String) async throws -> StatsContent)? = nil
    ) {
        self.entryService = entryService
        self.wearService = wearService
        self.revisionStore = revisionStore
        self.gateEnabled = gateEnabled
        self.contentLoader = contentLoader
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
        defer { if token == reloadToken { isLoading = false } }
        do {
            let content: StatsContent
            if let contentLoader {
                content = try await contentLoader(vehicleId)
            } else {
                async let entriesTask = entryService.fetchEntries(query: EntryQuery(vehicleId: vehicleId), limit: 100)
                async let wearTask = wearService.fetchDashboard(vehicleId: vehicleId)
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
}
