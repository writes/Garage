import Observation

@MainActor
@Observable
final class StatsViewModel {
    struct StatsContent {
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
    private let contentLoader: ((String) async throws -> StatsContent)?

    private(set) var entries: [FirestoreEntry] = []
    private(set) var wearItems: [WearItem] = []
    private(set) var error: AppError?
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
        do {
            if let contentLoader {
                let content = try await contentLoader(vehicleId)
                guard token == reloadToken else { return }
                entries = content.entries
                wearItems = content.wearItems
                error = nil
                lastLoadedKey = currentKey
                return
            }
            async let entriesTask = entryService.fetchEntries(query: EntryQuery(vehicleId: vehicleId), limit: 100)
            async let wearTask = wearService.fetchDashboard(vehicleId: vehicleId)
            let (fetchedEntries, fetchedWear) = try await (entriesTask, wearTask)
            guard token == reloadToken else { return }
            entries = fetchedEntries
            wearItems = fetchedWear
            error = nil
            lastLoadedKey = currentKey
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
            lastLoadedKey = nil
        }
    }
}
