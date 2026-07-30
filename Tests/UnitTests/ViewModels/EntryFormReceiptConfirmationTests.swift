import Foundation
import Testing
@testable import Garage

@MainActor
struct EntryFormReceiptConfirmationTests {
    @Test func savingReceiptPrefillConfirmsExactlyOnceAndClearsTheToken() async {
        let service = receiptService()
        let analytics = enabledAnalytics()
        let viewModel = receiptForm(service: service, analytics: analytics)
        viewModel.applyReceiptPrefill(package(token: "confirm-token"), isPro: false)
        viewModel.reconcileReceiptOdometerFloor()

        let firstSaved = await viewModel.save(vehicle: vehicle(), entryType: .maintenance, details: details())
        let secondSaved = await viewModel.save(vehicle: vehicle(), entryType: .maintenance, details: details())
        await waitForConfirmCall(service)

        #expect(firstSaved)
        #expect(secondSaved)
        #expect(service.confirmTokens == ["confirm-token"])
        #expect(viewModel.receiptConfirmationToken == nil)
        #expect(analytics.events.filter { $0 == .receiptEntryConfirmed }.count == 1)
    }

    @Test func failedConfirmEmitsSyncFailureAndStillClearsTheToken() async {
        let service = receiptService()
        service.confirmResult = .failure(AppError.unknown("confirmation unavailable"))
        let analytics = enabledAnalytics()
        let viewModel = receiptForm(service: service, analytics: analytics)
        viewModel.applyReceiptPrefill(package(token: "confirm-token"), isPro: false)
        viewModel.reconcileReceiptOdometerFloor()

        let saved = await viewModel.save(vehicle: vehicle(), entryType: .maintenance, details: details())
        await waitForSyncFailure(analytics)

        #expect(saved)
        #expect(viewModel.receiptConfirmationToken == nil)
        #expect(analytics.events.contains(.receiptConfirmSyncFailed))
    }

    @Test func abandoningCaptureBeforeAnEntrySaveNeverConfirmsTheReceipt() async {
        let service = FakeReceiptService(result: .success(.init(
            proposal: sampleReceiptProposal, token: "confirm-token", quota: .fixture
        )))
        let capture = makeReceiptCaptureViewModel(service: service)
        capture.addImage(Data([0x01]), source: .camera)

        await capture.confirmAndParse(vehicle: nil)
        capture.abandon()
        await Task.yield()

        #expect(service.confirmTokens.isEmpty)
    }

    private func receiptService() -> FakeReceiptService {
        FakeReceiptService(result: .success(.init(
            proposal: sampleReceiptProposal, token: nil, quota: nil
        )))
    }

    private func enabledAnalytics() -> AnalyticsSpy {
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        return analytics
    }

    private func receiptForm(service: FakeReceiptService, analytics: AnalyticsSpy) -> EntryFormViewModel {
        EntryFormViewModel(
            entryService: EntryService(testEntries: []),
            vehicleService: VehicleService(
                testVehicles: [vehicle()], purchaseService: PurchaseService(testIsPro: false)
            ),
            syncService: SyncService(monitorFactory: { SyncPassiveMonitor() }),
            analytics: analytics, receiptQuickAddService: service,
            firstEntryFollowUp: { _ in }, userID: { "user" }
        )
    }

    private func package(token: String?) -> ReceiptPrefillPackage {
        ReceiptPrefillPackage(
            proposal: ReceiptEntryProposal(
                entryType: .maintenance, odometerReading: 12_100, cost: nil, shopName: nil,
                isDiy: nil, entryDate: nil, notes: nil, lineItems: nil
            ),
            attachments: [], token: token
        )
    }

    private func vehicle() -> Vehicle {
        Vehicle(
            id: "vehicle", userId: "user", nickname: "Test car", make: "Garage", model: "Test",
            year: 2026, currentOdometer: 10_000
        )
    }

    private func details() -> MaintenanceEntry {
        MaintenanceEntry(
            item: .airFilter, otherLabel: nil, nextDueMileage: nil, nextDueDate: nil,
            symptomDescription: nil, resolutionDescription: nil, status: .resolved
        )
    }

    private func waitForConfirmCall(_ service: FakeReceiptService) async {
        for _ in 0 ..< 100 {
            if service.confirmTokens.count == 1 { return }
            await Task.yield()
        }
        Issue.record("Expected exactly one receipt confirmation call.")
    }

    private func waitForSyncFailure(_ analytics: AnalyticsSpy) async {
        for _ in 0 ..< 100 {
            if analytics.events.contains(.receiptConfirmSyncFailed) { return }
            await Task.yield()
        }
        Issue.record("Expected receipt_confirm_sync_failed analytics.")
    }
}
