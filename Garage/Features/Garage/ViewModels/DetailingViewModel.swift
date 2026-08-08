import Observation

@MainActor
@Observable
final class DetailingViewModel {
    private let detailingService: DetailingService
    /// Closure seam rather than an injected service: `DetailingService` is a concrete final class
    /// behind a `private init` singleton, so a unit test cannot substitute it — and a test for the
    /// FAILED load has no other way to make the fetch throw. Mirrors `StatsViewModel.contentLoader`.
    private let recordsLoader: ((String) async throws -> [DetailingRecord])?

    private(set) var records: [DetailingRecord] = []
    private(set) var error: AppError?
    private(set) var isLoading = false
    /// The vehicle whose load has RESOLVED (either way); nil until one has. `records.isEmpty` is
    /// also true before the first fetch lands, so without this the screen greets every owner WITH
    /// records — and every owner whose fetch is about to fail — with "No detailing history yet".
    ///
    /// Per-vehicle, not a Bool: `records` holds one vehicle at a time, so a Bool stayed true across
    /// a vehicle switch and let the next vehicle's first frame skip the loading state entirely.
    /// Switching back re-shows loading — nothing here is cached per vehicle.
    private(set) var firstLoadResolvedVehicleId: String?
    private var reloadToken = 0

    func hasCompletedFirstLoad(for vehicleId: String) -> Bool {
        firstLoadResolvedVehicleId == vehicleId
    }

    init(
        detailingService: DetailingService = .shared,
        recordsLoader: ((String) async throws -> [DetailingRecord])? = nil
    ) {
        self.detailingService = detailingService
        self.recordsLoader = recordsLoader
    }

    func load(vehicleId: String) async {
        reloadToken &+= 1
        let token = reloadToken
        isLoading = true
        defer {
            if token == reloadToken {
                isLoading = false
                firstLoadResolvedVehicleId = vehicleId
            }
        }
        do {
            let fetched: [DetailingRecord]
            if let recordsLoader {
                fetched = try await recordsLoader(vehicleId)
            } else {
                fetched = try await detailingService.fetchRecords(vehicleId: vehicleId)
            }
            guard token == reloadToken else { return }
            records = fetched.sorted { $0.serviceDate > $1.serviceDate }
            error = nil
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
        }
    }
}
