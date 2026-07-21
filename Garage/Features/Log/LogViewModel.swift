import Observation

@MainActor
@Observable
final class LogViewModel {
    private let entryService: EntryService

    var searchText = ""
    var selectedTypes = Set<EntryType>()
    private(set) var entries: [FirestoreEntry] = []
    private(set) var isLoading = false
    private(set) var error: AppError?
    private var reloadToken = 0

    init(entryService: EntryService = .shared) {
        self.entryService = entryService
    }

    func reload(vehicleId: String) async {
        // Each search keystroke/filter change fires a reload; a slow earlier fetch must not
        // overwrite a newer one (that is why clearing the search "never reset"). Only the
        // latest request applies its result.
        reloadToken &+= 1
        let token = reloadToken
        isLoading = true
        defer { if token == reloadToken { isLoading = false } }

        do {
            let fetched = try await entryService.fetchEntries(
                query: EntryQuery(vehicleId: vehicleId, entryTypes: selectedTypes, searchText: searchText)
            )
            guard token == reloadToken else { return }
            entries = fetched
            error = nil
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
        }
    }
}
