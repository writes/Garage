import Foundation
import Testing
@testable import Garage

@MainActor
struct AppRouterTests {
    @Test func presentEntryPickerWithVehiclesPresentsItDirectly() {
        let router = AppRouter(hasVehicles: { true })
        router.present(.entryPicker)
        #expect(router.activeSheet == .entryPicker)
    }

    @Test func presentEntryPickerWithNoVehiclesRedirectsToVehicleCreation() {
        let router = AppRouter(hasVehicles: { false })
        router.present(.entryPicker)
        #expect(router.activeSheet == .vehicleForm)
    }

    @Test func presentVoiceQuickAddWithNoVehiclesRedirectsToVehicleCreation() {
        let router = AppRouter(hasVehicles: { false })
        router.present(.voiceQuickAdd)
        #expect(router.activeSheet == .vehicleForm)
    }

    @Test func presentReceiptCaptureWithNoVehiclesRedirectsToVehicleCreation() {
        let router = AppRouter(hasVehicles: { false })
        router.present(.receiptCapture)
        #expect(router.activeSheet == .vehicleForm)
    }

    @Test func presentReceiptCaptureWithVehiclesPresentsItDirectly() {
        let router = AppRouter(hasVehicles: { true })
        router.present(.receiptCapture)
        #expect(router.activeSheet == .receiptCapture)
    }

    @Test func presentEntryFormWithNoVehiclesRedirectsToVehicleCreation() {
        let router = AppRouter(hasVehicles: { false })
        router.present(.entryForm(.fuel))
        #expect(router.activeSheet == .vehicleForm)
    }

    @Test func presentEntryFormWithVehiclesPresentsItDirectly() {
        let router = AppRouter(hasVehicles: { true })
        router.present(.entryForm(.fuel))
        #expect(router.activeSheet == .entryForm(.fuel))
    }

    @Test func presentUngatedSheetsIgnoreTheVehicleGate() {
        let router = AppRouter(hasVehicles: { false })
        router.present(.vehicleForm)
        #expect(router.activeSheet == .vehicleForm)
        router.present(.export)
        #expect(router.activeSheet == .export)
    }

    @Test func gateRedirectDropsAnyPendingVoicePrefillSoALaterFormNeverConsumesStaleState() {
        var hasVehicles = true
        let router = AppRouter(hasVehicles: { hasVehicles })
        router.presentVoicePrefilledForm(proposal())
        #expect(router.pendingVoicePrefill != nil)

        hasVehicles = false
        router.present(.entryForm(.fuel))
        #expect(router.activeSheet == .vehicleForm)
        #expect(router.pendingVoicePrefill == nil)
        #expect(router.consumeVoicePrefill() == nil)
    }

    @Test func presentVoicePrefilledFormSeedsAOneShotPendingPrefill() {
        let router = AppRouter(hasVehicles: { true })
        let proposal = proposal()
        router.presentVoicePrefilledForm(proposal)
        #expect(router.activeSheet == .entryForm(.maintenance))
        #expect(router.consumeVoicePrefill() == proposal)
        #expect(router.consumeVoicePrefill() == nil)
    }

    @Test func dismissSheetClearsActiveSheetButNotPendingVoicePrefill() {
        let router = AppRouter(hasVehicles: { true })
        router.presentVoicePrefilledForm(proposal())
        router.dismissSheet()
        #expect(router.activeSheet == nil)
        #expect(router.pendingVoicePrefill != nil)
    }

    @Test func presentReceiptPrefilledFormSeedsAOneShotPendingPrefill() {
        let router = AppRouter(hasVehicles: { true })
        let package = receiptPackage()
        router.presentReceiptPrefilledForm(package)
        #expect(router.activeSheet == .entryForm(.maintenance))
        #expect(router.consumeReceiptPrefill() == package)
        #expect(router.consumeReceiptPrefill() == nil)
    }

    @Test func gateRedirectDropsAnyPendingReceiptPrefillSoALaterFormNeverConsumesStaleState() {
        var hasVehicles = true
        let router = AppRouter(hasVehicles: { hasVehicles })
        router.presentReceiptPrefilledForm(receiptPackage())
        #expect(router.pendingReceiptPrefill != nil)

        hasVehicles = false
        router.present(.entryForm(.fuel))
        #expect(router.activeSheet == .vehicleForm)
        #expect(router.pendingReceiptPrefill == nil)
        #expect(router.consumeReceiptPrefill() == nil)
    }

    @Test func dismissSheetClearsActiveSheetButNotPendingReceiptPrefill() {
        let router = AppRouter(hasVehicles: { true })
        router.presentReceiptPrefilledForm(receiptPackage())
        router.dismissSheet()
        #expect(router.activeSheet == nil)
        #expect(router.pendingReceiptPrefill != nil)
    }

    @Test func presentEditFormSeedsAOneShotPendingEditEntryAndGoesThroughTheVehicleGate() {
        let router = AppRouter(hasVehicles: { true })
        let entry = makeEntry()
        router.presentEditForm(for: entry)
        #expect(router.activeSheet == .entryForm(.maintenance))
        #expect(router.consumeEditEntry() == entry)
        #expect(router.consumeEditEntry() == nil)
    }

    @Test func presentEditFormWithNoVehiclesRedirectsToVehicleCreationAndDropsThePendingEdit() {
        let router = AppRouter(hasVehicles: { false })
        router.presentEditForm(for: makeEntry())
        #expect(router.activeSheet == .vehicleForm)
        #expect(router.consumeEditEntry() == nil)
    }

    @Test func dismissSheetClearsActiveSheetButNotPendingEditEntry() {
        let router = AppRouter(hasVehicles: { true })
        router.presentEditForm(for: makeEntry())
        router.dismissSheet()
        #expect(router.activeSheet == nil)
        #expect(router.pendingEditEntry != nil)
    }

    private func proposal() -> VoiceEntryProposal {
        VoiceEntryProposal(
            entryType: .maintenance, odometerReading: 100, cost: nil,
            shopName: nil, isDiy: nil, entryDate: nil, notes: nil
        )
    }

    private func receiptPackage() -> ReceiptPrefillPackage {
        ReceiptPrefillPackage(
            proposal: ReceiptEntryProposal(
                entryType: .maintenance, odometerReading: 100, cost: nil,
                shopName: nil, isDiy: nil, entryDate: nil, notes: nil, lineItems: nil
            ),
            attachments: []
        )
    }

    private func makeEntry() -> FirestoreEntry {
        FirestoreEntry(
            id: "entry", vehicleId: "vehicle", userId: "user", entryType: .maintenance,
            entryDate: .now, odometerReading: 100, cost: nil, isDiy: nil, shopName: nil,
            notes: nil, attachmentPaths: [], isResolved: nil, details: [:], createdAt: nil, updatedAt: nil
        )
    }
}
