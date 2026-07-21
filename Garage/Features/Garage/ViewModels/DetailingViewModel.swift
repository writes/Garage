import Observation

@MainActor
@Observable
final class DetailingViewModel {
    private let detailingService: DetailingService

    private(set) var records: [DetailingRecord] = []
    private(set) var error: AppError?
    private var reloadToken = 0

    init(detailingService: DetailingService = .shared) {
        self.detailingService = detailingService
    }

    func load(vehicleId: String) async {
        reloadToken &+= 1
        let token = reloadToken
        do {
            let fetched = try await detailingService.fetchRecords(vehicleId: vehicleId)
            guard token == reloadToken else { return }
            records = fetched.sorted { $0.serviceDate > $1.serviceDate }
            error = nil
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
        }
    }
}
