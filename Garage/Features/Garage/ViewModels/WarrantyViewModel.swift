import Foundation
import Observation

@MainActor
@Observable
final class WarrantyViewModel {
    private let warrantyService: WarrantyService

    private(set) var warranties: [Warranty] = []
    private(set) var recalls: [Recall] = []
    private(set) var error: AppError?
    private var reloadToken = 0

    init(warrantyService: WarrantyService = .shared) {
        self.warrantyService = warrantyService
    }

    func load(vehicleId: String) async {
        reloadToken &+= 1
        let token = reloadToken
        do {
            async let warrantiesTask = warrantyService.fetchWarranties(vehicleId: vehicleId)
            async let recallsTask = warrantyService.fetchRecalls(vehicleId: vehicleId)
            let (fetchedWarranties, fetchedRecalls) = try await (warrantiesTask, recallsTask)
            guard token == reloadToken else { return }
            warranties = fetchedWarranties.sorted { Self.sortKey($0) > Self.sortKey($1) }
            recalls = fetchedRecalls.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            error = nil
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
        }
    }

    private static func sortKey(_ warranty: Warranty) -> Date {
        warranty.expirationDate ?? warranty.coverageEnd ?? warranty.createdAt ?? .distantPast
    }
}
