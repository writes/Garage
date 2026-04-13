import Observation

@MainActor
@Observable
final class StatsViewModel {
    private let entryService: EntryService
    private let wearService: WearService

    private(set) var entries: [FirestoreEntry] = []
    private(set) var wearItems: [WearItem] = []
    private(set) var error: AppError?

    init(entryService: EntryService = .shared, wearService: WearService = .shared) {
        self.entryService = entryService
        self.wearService = wearService
    }

    func load(vehicleId: String) async {
        do {
            async let entries = entryService.fetchEntries(query: EntryQuery(vehicleId: vehicleId), limit: 100)
            async let wear = wearService.fetchDashboard(vehicleId: vehicleId)
            self.entries = try await entries
            self.wearItems = try await wear
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }
}
