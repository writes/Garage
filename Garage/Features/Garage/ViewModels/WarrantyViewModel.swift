import Foundation
import Observation

@MainActor
@Observable
final class WarrantyViewModel {
    private let warrantyService: WarrantyService
    private let recallLookup: any RecallLooking

    private(set) var warranties: [Warranty] = []
    private(set) var recalls: [Recall] = []
    private(set) var error: AppError?
    private var reloadToken = 0

    private(set) var isCheckingRecalls = false
    /// Set after a successful check so the screen can report "nothing found" — otherwise a lookup
    /// that legitimately returns zero recalls is indistinguishable from one that did nothing.
    private(set) var lastRecallCheck: String?

    init(
        warrantyService: WarrantyService = .shared,
        recallLookup: any RecallLooking = RecallLookupService.shared
    ) {
        self.warrantyService = warrantyService
        self.recallLookup = recallLookup
    }

    /// Looks the vehicle's VIN up against NHTSA and stores anything new.
    ///
    /// Existing campaign numbers are skipped rather than overwritten: once a recall is in the
    /// user's list they may have marked it completed, and re-importing would silently reset that
    /// to outstanding — the app undoing a record of work the owner actually had done.
    func checkForRecalls(vehicle: Vehicle) async {
        guard !isCheckingRecalls else { return }
        isCheckingRecalls = true
        defer { isCheckingRecalls = false }

        do {
            let response = try await recallLookup.lookup(vin: vehicle.vin ?? "")
            let known = Set(recalls.compactMap(\.campaignNumber))
            for result in response.recalls where !known.contains(result.campaignNumber) {
                let recall = result.asRecall(vehicleId: vehicle.id, id: UUID().uuidString)
                try await warrantyService.saveRecall(recall)
            }
            lastRecallCheck = "Checked \(response.modelYear) \(response.make) \(response.model) — "
                + "\(response.recalls.count) recall\(response.recalls.count == 1 ? "" : "s") on file."
            error = nil
            await load(vehicleId: vehicle.id)
        } catch RecallLookupError.vinMissing {
            error = .validation("Add this vehicle's VIN to check for recalls.")
        } catch RecallLookupError.vinNotRecognised {
            error = .validation("NHTSA did not recognise that VIN. Check it for typos.")
        } catch {
            self.error = AppError(from: error)
        }
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
