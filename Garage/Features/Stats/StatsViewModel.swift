import Observation

@MainActor
@Observable
final class StatsViewModel {
    private let entryService: EntryService
    private let wearService: WearService

    private(set) var entries: [FirestoreEntry] = []
    private(set) var wearItems: [WearItem] = []
    private(set) var error: AppError?
    private var reloadToken = 0

    init(entryService: EntryService = .shared, wearService: WearService = .shared) {
        self.entryService = entryService
        self.wearService = wearService
    }

    func load(vehicleId: String) async {
        reloadToken &+= 1
        let token = reloadToken
        do {
            async let entriesTask = entryService.fetchEntries(query: EntryQuery(vehicleId: vehicleId), limit: 100)
            async let wearTask = wearService.fetchDashboard(vehicleId: vehicleId)
            let (fetchedEntries, fetchedWear) = try await (entriesTask, wearTask)
            guard token == reloadToken else { return }
            entries = fetchedEntries
            wearItems = fetchedWear
            error = nil
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
        }
    }
}
