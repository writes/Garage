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

    /// `WarrantyService.saveWarranty` and `saveRecall` shipped with zero callers, so this screen
    /// was read-only and could never hold a record — it showed "No warranty records yet" forever.
    /// Reloading on success is what makes the new row appear without leaving the screen.
    func add(_ warranty: Warranty) async -> Bool {
        await save(vehicleId: warranty.vehicleId) {
            try await self.warrantyService.saveWarranty(warranty)
        }
    }

    func add(_ recall: Recall) async -> Bool {
        await save(vehicleId: recall.vehicleId) {
            try await self.warrantyService.saveRecall(recall)
        }
    }

    private func save(vehicleId: String, _ write: () async throws -> Void) async -> Bool {
        do {
            try await write()
            error = nil
            await load(vehicleId: vehicleId)
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }

    private static func sortKey(_ warranty: Warranty) -> Date {
        warranty.expirationDate ?? warranty.coverageEnd ?? warranty.createdAt ?? .distantPast
    }
}
