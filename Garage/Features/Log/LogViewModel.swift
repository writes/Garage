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

    init(entryService: EntryService = .shared) {
        self.entryService = entryService
    }

    func reload(vehicleId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            entries = try await entryService.fetchEntries(
                query: EntryQuery(vehicleId: vehicleId, entryTypes: selectedTypes, searchText: searchText)
            )
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }
}
