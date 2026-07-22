import Observation

@MainActor
@Observable
final class LogViewModel {
    private let entryService: EntryService

    var searchText = ""
    var selectedTypes = Set<EntryType>()
    private(set) var allEntries: [FirestoreEntry] = []
    private(set) var entries: [FirestoreEntry] = []
    private(set) var isLoading = false
    private(set) var error: AppError?
    private var reloadToken = 0

    init(entryService: EntryService = .shared) {
        self.entryService = entryService
    }

    /// Fetches the vehicle's history once (up to maxLogEntries), then filters client-side. Search
    /// and type changes re-filter the cached set without re-fetching, so search covers the full
    /// history and a keystroke never triggers a Firestore round-trip (nor a reload race).
    func reload(vehicleId: String) async {
        reloadToken &+= 1
        let token = reloadToken
        isLoading = true
        defer { if token == reloadToken { isLoading = false } }

        do {
            let fetched = try await entryService.fetchEntries(
                query: EntryQuery(vehicleId: vehicleId, entryTypes: [], searchText: ""),
                limit: Constants.maxLogEntries
            )
            guard token == reloadToken else { return }
            allEntries = fetched
            applyFilter()
            error = nil
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
