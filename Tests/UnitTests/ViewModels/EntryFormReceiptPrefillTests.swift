import Foundation
import Testing
@testable import Garage

@MainActor
struct EntryFormReceiptPrefillTests {
    // MARK: - Field mapping (parallel to EntryFormVoicePrefillTests)

    @Test func prefillWithShopClearsDiyAndFillsCommonFields() {
        let viewModel = EntryFormViewModel()
        viewModel.applyReceiptPrefill(package(proposal(
            odometer: 18_120, cost: 165, shopName: "  Willow Springs  ", isDiy: true, notes: " Mobil 1 "
        )), isPro: false)

        #expect(viewModel.odometerReading == "18120")
        #expect(viewModel.cost == "165")
        #expect(viewModel.shopName == "Willow Springs")
        #expect(viewModel.isDiy == false)
        #expect(viewModel.notes == "Mobil 1")
        #expect(viewModel.wasReceiptSeeded)
    }

    @Test func prefillHonorsDiyWhenNoShopSpoken() {
        let viewModel = EntryFormViewModel()
        viewModel.applyReceiptPrefill(package(proposal(isDiy: true)), isPro: false)
        #expect(viewModel.isDiy == true)
        #expect(viewModel.shopName.isEmpty)
    }

    @Test func prefillFormatsFractionalCostAndKeepsWholeClean() {
        let whole = EntryFormViewModel()
        whole.applyReceiptPrefill(package(proposal(cost: 200)), isPro: false)
        #expect(whole.cost == "200")

        let fractional = EntryFormViewModel()
        fractional.applyReceiptPrefill(package(proposal(cost: 89.99)), isPro: false)
        #expect(fractional.cost == "89.99")
    }

    @Test func prefillIgnoresNonPositiveNumbers() {
        let viewModel = EntryFormViewModel()
        viewModel.applyReceiptPrefill(package(proposal(odometer: 0, cost: 0)), isPro: false)
        #expect(viewModel.odometerReading.isEmpty)
        #expect(viewModel.cost.isEmpty)
    }

    @Test func unreadReceiptCaptionUsesRawPresenceRatherThanAppliedFormValues() {
        let viewModel = EntryFormViewModel()
        viewModel.applyReceiptPrefill(package(proposal(
            odometer: 0, cost: 0, shopName: "", isDiy: false, notes: "", lineItems: []
        )), isPro: false)

        #expect(viewModel.unreadReceiptFieldsCaption == "Not read from the receipt: date")
    }

    @Test func unreadReceiptCaptionListsOnlyFieldsMissingFromTheModelResponse() {
        let viewModel = EntryFormViewModel()
        viewModel.applyReceiptPrefill(package(proposal(odometer: 18_120)), isPro: false)

        #expect(viewModel.unreadReceiptFieldsCaption
            == "Not read from the receipt: date, cost, shop, DIY, notes")
    }

    // MARK: - lineItems -> notes bullet join

    @Test func lineItems_joinIntoNotesWithBulletsAfterFreeTextNotes() {
        let viewModel = EntryFormViewModel()
        viewModel.applyReceiptPrefill(package(proposal(
            notes: "Warranty: 12mo", lineItems: ["Synthetic oil 5W-30 x6 — $54.00", " Filter — $12.00 ", ""]
        )), isPro: false)

        #expect(viewModel.notes == "Warranty: 12mo\n\n• Synthetic oil 5W-30 x6 — $54.00\n• Filter — $12.00")
    }

    @Test func lineItems_aloneWithNoFreeTextNotesStillJoin() {
        let viewModel = EntryFormViewModel()
        viewModel.applyReceiptPrefill(package(proposal(lineItems: ["Brake pads — $80.00"])), isPro: false)
        #expect(viewModel.notes == "• Brake pads — $80.00")
    }

    // MARK: - Pro-only attachment staging (plan §5's cross-feature entitlement rule)

    @Test func attachmentStaging_proStagesEveryAttachmentAsPendingAttachments() {
        let viewModel = EntryFormViewModel()
        let attachments = [
            ReceiptPrefillAttachment(kind: .image, data: Data([0x01]), displayName: "Receipt"),
            ReceiptPrefillAttachment(kind: .pdf, data: Data([0x02]), displayName: "invoice.pdf")
        ]
        viewModel.applyReceiptPrefill(package(proposal(), attachments: attachments), isPro: true)

        #expect(viewModel.pendingAttachments.map(\.kind) == [.image, .pdf])
        #expect(!viewModel.receiptAttachmentNeedsPro)
    }

    @Test func attachmentStaging_freeUserGetsNoStagedAttachmentButSetsTheUpsellFlag() {
        let viewModel = EntryFormViewModel()
        let attachments = [ReceiptPrefillAttachment(kind: .image, data: Data([0x01]), displayName: "Receipt")]
        viewModel.applyReceiptPrefill(package(proposal(), attachments: attachments), isPro: false)

        #expect(viewModel.pendingAttachments.isEmpty)
        #expect(viewModel.receiptAttachmentNeedsPro)
    }

    @Test func attachmentStaging_noAttachmentsNeverSetsTheUpsellFlagEvenWhenFree() {
        let viewModel = EntryFormViewModel()
        viewModel.applyReceiptPrefill(package(proposal()), isPro: false)
        #expect(!viewModel.receiptAttachmentNeedsPro)
    }

    // MARK: - The receipt's own mileage survives the second pass

    /// The defect this replaces: an OLD receipt reading below the vehicle's current odometer had
    /// its mileage overwritten with the inflated floor and the true number demoted to a note. The
    /// app was storing a mileage the car never had on that date — and MaintenanceAdvisor computes
    /// milesPastDue from exactly that field. With the floor now date-scoped, the printed value
    /// validates on its own and is left alone.
    @Test func receiptMileageBelowTheVehiclesCurrentReadingIsKeptExactlyAsPrinted() {
        let viewModel = EntryFormViewModel()
        viewModel.applyReceiptPrefill(package(proposal(odometer: 84_500)), isPro: false)
        // What prepare() loads for a receipt dated before every existing entry: nothing earlier
        // to contradict it. lastKnownOdometer (85,000) is context for the hint, not a floor.
        viewModel.lastKnownOdometer = 85_000
        viewModel.odometerBounds = OdometerBounds()

        viewModel.captureReceiptPrefillBaseline()

        #expect(viewModel.odometerReading == "84500")
        #expect(viewModel.notes.isEmpty)
        #expect(!viewModel.receiptPrefillSeededFields.contains(.notes))
        #expect(viewModel.validateOdometer()) // Save is never blocked
    }

    @Test func receiptMileageAboveTheVehiclesCurrentReadingIsAlsoUntouched() {
        let viewModel = EntryFormViewModel()
        viewModel.applyReceiptPrefill(package(proposal(odometer: 85_500)), isPro: false)
        viewModel.lastKnownOdometer = 85_000

        viewModel.captureReceiptPrefillBaseline()

        #expect(viewModel.odometerReading == "85500")
        #expect(viewModel.notes.isEmpty)
    }

    /// A receipt whose mileage genuinely contradicts an EARLIER-dated entry is still rejected —
    /// dropping the substitution did not drop the check, it only stopped it lying about the value.
    @Test func aReceiptMileageBelowAnEarlierDatedEntryIsStillRejected() {
        let viewModel = EntryFormViewModel()
        viewModel.applyReceiptPrefill(package(proposal(odometer: 84_500)), isPro: false)
        viewModel.odometerBounds = OdometerBounds(
            earlier: OdometerBoundary(reading: 90_000, entryDate: Date(timeIntervalSince1970: 1_700_000_000))
        )

        viewModel.captureReceiptPrefillBaseline()

        #expect(viewModel.odometerReading == "84500")
        #expect(!viewModel.validateOdometer())
    }

    @Test func theBaselineSnapshotIsOnlyCapturedWhenReceiptSeeded() {
        let viewModel = EntryFormViewModel()
        viewModel.odometerReading = "100"
        viewModel.lastKnownOdometer = 500

        viewModel.captureReceiptPrefillBaseline()

        #expect(viewModel.odometerReading == "100")
        #expect(viewModel.receiptPrefillEffectiveSeed == nil)
    }

    // MARK: - Save-confirmed funnel exclusivity

    @Test func savingAReceiptSeededFormEmitsReceiptConfirmedExactlyOnceNeverVoiceConfirmed() async {
        let vehicle = testVehicle()
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let viewModel = EntryFormViewModel(
            entryService: EntryService(testEntries: []),
            vehicleService: VehicleService(testVehicles: [vehicle], purchaseService: PurchaseService(testIsPro: false)),
            syncService: SyncService(monitorFactory: { SyncPassiveMonitor() }),
            analytics: analytics, userID: { "user" }
        )
        viewModel.applyReceiptPrefill(package(proposal(odometer: 12_100)), isPro: false)

        let saved = await viewModel.save(vehicle: vehicle, entryType: .maintenance, details: maintenanceDetails())

        #expect(saved)
        #expect(analytics.events.filter { $0 == .receiptEntryConfirmed }.count == 1)
        #expect(!analytics.events.contains(.voiceEntryConfirmed(entryType: .maintenance)))
        #expect(viewModel.wasReceiptSeeded == false)
    }

    // MARK: - Fixtures

    private func proposal(
        odometer: Int? = nil, cost: Double? = nil, shopName: String? = nil,
        isDiy: Bool? = nil, notes: String? = nil, lineItems: [String]? = nil
    ) -> ReceiptEntryProposal {
        ReceiptEntryProposal(
            entryType: .maintenance, odometerReading: odometer, cost: cost,
            shopName: shopName, isDiy: isDiy, entryDate: nil, notes: notes, lineItems: lineItems
        )
    }

    private func package(
        _ proposal: ReceiptEntryProposal, attachments: [ReceiptPrefillAttachment] = []
    ) -> ReceiptPrefillPackage {
        ReceiptPrefillPackage(proposal: proposal, attachments: attachments, token: nil, quota: nil)
    }

    private func testVehicle() -> Vehicle {
        Vehicle(
            id: "vehicle", userId: "user", nickname: "Test car", make: "Garage", model: "Test",
            year: 2026, currentOdometer: 10_000
        )
    }

    private func maintenanceDetails() -> MaintenanceEntry {
        MaintenanceEntry(
            item: .airFilter, otherLabel: nil, nextDueMileage: nil, nextDueDate: nil,
            symptomDescription: nil, resolutionDescription: nil, status: .resolved
        )
    }
}
