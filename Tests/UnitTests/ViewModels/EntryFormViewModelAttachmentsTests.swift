import Foundation
import Testing
@testable import Garage

/// Attachment lifecycle: pending picks are queued locally, uploaded only at save() time (before
/// the entry write), and already-uploaded removals are deferred until after a successful write.
/// See EntryFormViewModel+Attachments.swift for the implementation this exercises.
@MainActor
struct EntryFormViewModelAttachmentsTests {
    @Test func addPendingImage_andRemovePendingAttachment_dropsOnlyTheMatchingItem() {
        let viewModel = EntryFormViewModel()
        viewModel.addPendingImage(Data([0x01]))
        viewModel.addPendingPDF(Data([0x02]), filename: "receipt.pdf")
        let keep = viewModel.pendingAttachments[0].id

        viewModel.removePendingAttachment(viewModel.pendingAttachments[1].id)

        #expect(viewModel.pendingAttachments.map(\.id) == [keep])
    }

    @Test func queueAttachmentRemoval_dropsFromAttachmentPathsImmediatelyButLeavesStorageUntouched() async {
        let attachments = EntryAttachmentService(testUploads: ["users/user/entry-attachments/vehicle/e/a.jpg": Data()])
        let viewModel = model(
            entryService: EntryService(testEntries: []),
            vehicleService: hermeticVehicleService(vehicles: []),
            entryAttachmentService: attachments
        )
        viewModel.attachmentPaths = ["users/user/entry-attachments/vehicle/e/a.jpg"]

        viewModel.queueAttachmentRemoval("users/user/entry-attachments/vehicle/e/a.jpg")

        #expect(viewModel.attachmentPaths.isEmpty)
        #expect(viewModel.queuedAttachmentRemovals == ["users/user/entry-attachments/vehicle/e/a.jpg"])
        #expect(attachments.uploadedPathsForTesting() == ["users/user/entry-attachments/vehicle/e/a.jpg"])
    }

    @Test func save_uploadsPendingAttachmentsBeforeWritingAndClearsTheQueue() async throws {
        let vehicle = testVehicle()
        let entries = EntryService(testEntries: [])
        let attachments = EntryAttachmentService(uuidProvider: { "fixed-uuid" })
        let viewModel = model(
            entryService: entries, vehicleService: hermeticVehicleService(vehicles: [vehicle]),
            entryAttachmentService: attachments
        )
        viewModel.odometerReading = "12100"
        viewModel.addPendingImage(Data([0x01]))

        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())

        let stored = try await entries.fetchRecent(vehicleId: vehicle.id, limit: 10)
        #expect(saved)
        #expect(viewModel.pendingAttachments.isEmpty)
        #expect(attachments.uploadedPathsForTesting().count == 1)
        #expect(stored.first?.attachmentPaths == Array(attachments.uploadedPathsForTesting()))
        #expect(viewModel.attachmentPaths == stored.first?.attachmentPaths)
    }

    /// Review-mandated ordering: any upload failure aborts BEFORE the entry doc/vehicle patch are
    /// touched (nothing half-written), and whatever DID upload earlier in the same batch is
    /// best-effort deleted so a retry never leaves an orphaned blob. pendingAttachments is left
    /// alone so the user's picks survive the retry.
    @Test func save_uploadFailureWritesNothingAndCleansUpWhateverAlreadyUploaded() async throws {
        let vehicle = testVehicle()
        let entries = EntryService(testEntries: [])
        var uploadCount = 0
        let attachments = EntryAttachmentService(
            uuidProvider: { "fixed-uuid" },
            testUploadInterceptor: {
                uploadCount += 1
                if uploadCount == 2 { throw AppError.validation("simulated upload failure") }
            }
        )
        let viewModel = model(
            entryService: entries, vehicleService: hermeticVehicleService(vehicles: [vehicle]),
            entryAttachmentService: attachments
        )
        viewModel.odometerReading = "12100"
        viewModel.addPendingImage(Data([0x01]))
        viewModel.addPendingPDF(Data([0x02]), filename: "receipt.pdf")

        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())

        let stored = try await entries.fetchRecent(vehicleId: vehicle.id, limit: 10)
        #expect(!saved)
        #expect(viewModel.error != nil)
        #expect(stored.isEmpty)
        #expect(attachments.uploadedPathsForTesting().isEmpty)
        #expect(viewModel.pendingAttachments.count == 2)
    }

    @Test func save_appliesQueuedAttachmentRemovalsOnlyAfterTheWriteSucceeds() async throws {
        let vehicle = testVehicle()
        let path = "users/user/entry-attachments/\(vehicle.id)/existing-entry/a.jpg"
        let existing = makeEntry(
            id: "existing-entry", vehicleId: vehicle.id, odometer: vehicle.currentOdometer, attachmentPaths: [path]
        )
        let entries = EntryService(testEntries: [existing])
        let attachments = EntryAttachmentService(testUploads: [path: Data()])
        let viewModel = model(
            entryService: entries, vehicleService: hermeticVehicleService(vehicles: [vehicle]),
            entryAttachmentService: attachments
        )

        viewModel.applyExistingEntry(existing)
        viewModel.queueAttachmentRemoval(path)
        #expect(attachments.uploadedPathsForTesting() == [path], "not deleted yet — the write hasn't succeeded")

        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())

        let stored = try await entries.fetchRecent(vehicleId: vehicle.id, limit: 10).first
        #expect(saved)
        #expect(stored?.attachmentPaths.isEmpty == true)
        #expect(attachments.uploadedPathsForTesting().isEmpty)
        #expect(viewModel.queuedAttachmentRemovals.isEmpty)
    }

    @Test func save_thatFailsBeforeTheWriteNeverAppliesTheQueuedRemoval() async throws {
        let originalVehicle = testVehicle()
        var otherVehicle = testVehicle()
        otherVehicle.id = "other-vehicle"
        let path = "users/user/entry-attachments/\(originalVehicle.id)/existing-entry/a.jpg"
        let existing = makeEntry(
            id: "existing-entry", vehicleId: originalVehicle.id, odometer: originalVehicle.currentOdometer,
            attachmentPaths: [path]
        )
        let entries = EntryService(testEntries: [existing])
        let attachments = EntryAttachmentService(testUploads: [path: Data()])
        let viewModel = model(
            entryService: entries, vehicleService: hermeticVehicleService(vehicles: [originalVehicle, otherVehicle]),
            entryAttachmentService: attachments
        )

        viewModel.applyExistingEntry(existing)
        viewModel.queueAttachmentRemoval(path)
        // BLOCKER-guard failure (cross-vehicle save): validatedUID rejects before any write.
        let saved = await viewModel.save(vehicle: otherVehicle, entryType: .maintenance, details: maintenanceDetails())

        #expect(!saved)
        #expect(attachments.uploadedPathsForTesting() == [path])
        #expect(viewModel.queuedAttachmentRemovals == [path])
    }

    private func model(
        entryService: EntryService, vehicleService: VehicleService, entryAttachmentService: EntryAttachmentService
    ) -> EntryFormViewModel {
        EntryFormViewModel(
            entryService: entryService, vehicleService: vehicleService,
            syncService: SyncService(monitorFactory: { AttachmentsPassiveMonitor() }),
            entryAttachmentService: entryAttachmentService,
            analytics: NoopAnalyticsService(), userID: { "user" }
        )
    }

    private func hermeticVehicleService(vehicles: [Vehicle]) -> VehicleService {
        VehicleService(testVehicles: vehicles, purchaseService: PurchaseService(testIsPro: false))
    }

    private func maintenanceDetails() -> MaintenanceEntry {
        MaintenanceEntry(
            item: .airFilter, otherLabel: nil, nextDueMileage: nil, nextDueDate: nil,
            symptomDescription: nil, resolutionDescription: nil, status: .resolved
        )
    }

    private func makeEntry(
        id: String = "entry", vehicleId: String = "vehicle", odometer: Int = 12_100,
        attachmentPaths: [String] = []
    ) -> FirestoreEntry {
        FirestoreEntry(
            id: id, vehicleId: vehicleId, userId: "user", entryType: .maintenance,
            entryDate: .now, odometerReading: odometer, cost: nil, isDiy: nil,
            shopName: nil, notes: nil, attachmentPaths: attachmentPaths, isResolved: nil,
            details: [:], createdAt: nil, updatedAt: nil
        )
    }

    private func testVehicle() -> Vehicle {
        Vehicle(
            id: "vehicle", userId: "user", nickname: "Test car", make: "Garage", model: "Test",
            year: 2026, currentOdometer: 12_100
        )
    }
}

@MainActor private final class AttachmentsPassiveMonitor: SyncConnectivityMonitoring {
    func start(_ handler: @escaping @MainActor @Sendable (SyncConnectivity) -> Void) {}
    func cancel() {}
}
