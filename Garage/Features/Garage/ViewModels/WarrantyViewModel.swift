import Observation

@MainActor
@Observable
final class WarrantyViewModel {
    private let warrantyService: WarrantyService

    private(set) var warranties: [Warranty] = []
    private(set) var recalls: [Recall] = []
    private(set) var error: AppError?

    init(warrantyService: WarrantyService = .shared) {
        self.warrantyService = warrantyService
    }

    func load(vehicleId: String) async {
        do {
            async let warranties = warrantyService.fetchWarranties(vehicleId: vehicleId)
            async let recalls = warrantyService.fetchRecalls(vehicleId: vehicleId)
            self.warranties = try await warranties
            self.recalls = try await recalls
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }
}
