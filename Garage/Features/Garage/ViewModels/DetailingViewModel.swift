import Observation

@MainActor
@Observable
final class DetailingViewModel {
    private let detailingService: DetailingService

    private(set) var records: [DetailingRecord] = []
    private(set) var error: AppError?

    init(detailingService: DetailingService = .shared) {
        self.detailingService = detailingService
    }

    func load(vehicleId: String) async {
        do {
            records = try await detailingService.fetchRecords(vehicleId: vehicleId)
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }
}
