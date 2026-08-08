import Foundation
import Observation

@MainActor
@Observable
final class WarrantyViewModel {
    struct WarrantyContent: Sendable {
        var warranties: [Warranty]
        var recalls: [Recall]
    }

    private let warrantyService: WarrantyService
    private let recallLookup: any RecallLooking
    /// `WarrantyService(testWarranties:testRecalls:)` covers the happy path but can only ever
    /// succeed, so the failed load — which used to leave "No warranty records yet" on screen with
    /// no error and no retry — needs this closure seam. Mirrors `StatsViewModel.contentLoader`.
    private let contentLoader: ((String) async throws -> WarrantyContent)?

    private(set) var warranties: [Warranty] = []
    private(set) var recalls: [Recall] = []
    private(set) var error: AppError?
    private(set) var isLoading = false
    /// The vehicle whose load has RESOLVED (either way) — see
    /// `DetailingViewModel.firstLoadResolvedVehicleId`.
    /// Deliberately NOT touched by `checkForRecalls`, which reports through `isCheckingRecalls`.
    private(set) var firstLoadResolvedVehicleId: String?
    private var reloadToken = 0

    private(set) var isCheckingRecalls = false
    /// Set after a successful check so the screen can report "nothing found" — otherwise a lookup
    /// that legitimately returns zero recalls is indistinguishable from one that did nothing.
    private(set) var lastRecallCheck: String?

    func hasCompletedFirstLoad(for vehicleId: String) -> Bool {
        firstLoadResolvedVehicleId == vehicleId
    }

    init(
        warrantyService: WarrantyService = .shared,
        recallLookup: any RecallLooking = RecallLookupService.shared,
        contentLoader: ((String) async throws -> WarrantyContent)? = nil
    ) {
        self.warrantyService = warrantyService
        self.recallLookup = recallLookup
        self.contentLoader = contentLoader
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
                try warrantyService.saveRecall(recall)
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
        isLoading = true
        defer {
            if token == reloadToken {
                isLoading = false
                firstLoadResolvedVehicleId = vehicleId
            }
        }
        do {
            let content: WarrantyContent
            if let contentLoader {
                content = try await contentLoader(vehicleId)
            } else {
                async let warrantiesTask = warrantyService.fetchWarranties(vehicleId: vehicleId)
                async let recallsTask = warrantyService.fetchRecalls(vehicleId: vehicleId)
                let (fetchedWarranties, fetchedRecalls) = try await (warrantiesTask, recallsTask)
                content = WarrantyContent(warranties: fetchedWarranties, recalls: fetchedRecalls)
            }
            guard token == reloadToken else { return }
            warranties = content.warranties.sorted { Self.sortKey($0) > Self.sortKey($1) }
            recalls = content.recalls.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
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
            try self.warrantyService.saveWarranty(warranty)
        }
    }

    func add(_ recall: Recall) async -> Bool {
        await save(vehicleId: recall.vehicleId) {
            try self.warrantyService.saveRecall(recall)
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
