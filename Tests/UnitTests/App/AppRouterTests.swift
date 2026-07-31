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

    @Test func gateRedirectDropsAnyPendingVoicePrefillSoALaterFormNeverReadsStaleState() {
        var hasVehicles = true
        let router = AppRouter(hasVehicles: { hasVehicles })
        router.presentVoicePrefilledForm(proposal())
        #expect(router.pendingVoicePrefill != nil)

        hasVehicles = false
        router.present(.entryForm(.fuel))
        #expect(router.activeSheet == .vehicleForm)
        #expect(router.pendingVoicePrefill == nil)
    }

    /// The slot must survive repeated reads: SwiftUI can build the destination sheet's content
    /// more than once during the voice→form swap, and each fresh build re-reads the prefill. A
    /// consume-on-first-read handoff handed the payload to a throwaway build and left the
    /// surviving form blank on device.
    @Test func presentVoicePrefilledFormHoldsThePrefillAcrossRepeatedReads() {
        let router = AppRouter(hasVehicles: { true })
        let proposal = proposal()
        router.presentVoicePrefilledForm(proposal)
        #expect(router.activeSheet == .entryForm(.maintenance))
        #expect(router.pendingVoicePrefill == proposal)
        #expect(router.pendingVoicePrefill == proposal)
    }

    @Test func dismissSheetEndsThePresentationAndTheVoiceHandoffWithIt() {
        let router = AppRouter(hasVehicles: { true })
        router.presentVoicePrefilledForm(proposal())
        router.dismissSheet()
        #expect(router.activeSheet == nil)
        #expect(router.pendingVoicePrefill == nil)
    }

    /// Any plain presentation starts a new flow, so it must wipe whatever handoff a dismissed
    /// prefilled form left behind — a manually-opened form must never inherit spoken details.
    @Test func presentingANewSheetWipesAStaleVoiceHandoff() {
        let router = AppRouter(hasVehicles: { true })
        router.presentVoicePrefilledForm(proposal())
        router.present(.entryForm(.fuel))
        #expect(router.pendingVoicePrefill == nil)

        router.presentVoicePrefilledForm(proposal())
        router.present(.entryPicker)
        #expect(router.pendingVoicePrefill == nil)
    }

    @Test func presentReceiptPrefilledFormHoldsThePrefillAcrossRepeatedReads() {
        let router = AppRouter(hasVehicles: { true })
        let package = receiptPackage()
        router.presentReceiptPrefilledForm(package)
        #expect(router.activeSheet == .entryForm(.maintenance))
        #expect(router.pendingReceiptPrefill == package)
        #expect(router.pendingReceiptPrefill == package)
    }

    @Test func gateRedirectDropsAnyPendingReceiptPrefillSoALaterFormNeverReadsStaleState() {
        var hasVehicles = true
        let router = AppRouter(hasVehicles: { hasVehicles })
        router.presentReceiptPrefilledForm(receiptPackage())
        #expect(router.pendingReceiptPrefill != nil)

        hasVehicles = false
        router.present(.entryForm(.fuel))
        #expect(router.activeSheet == .vehicleForm)
        #expect(router.pendingReceiptPrefill == nil)
    }

    @Test func dismissSheetEndsThePresentationAndTheReceiptHandoffWithIt() {
        let router = AppRouter(hasVehicles: { true })
        router.presentReceiptPrefilledForm(receiptPackage())
        router.dismissSheet()
        #expect(router.activeSheet == nil)
        #expect(router.pendingReceiptPrefill == nil)
    }

    @Test func presentEditFormHoldsThePendingEditAndGoesThroughTheVehicleGate() {
        let router = AppRouter(hasVehicles: { true })
        let entry = makeEntry()
        router.presentEditForm(for: entry)
        #expect(router.activeSheet == .entryForm(.maintenance))
        #expect(router.pendingEditEntry == entry)
        #expect(router.pendingEditEntry == entry)
    }

    @Test func presentEditFormWithNoVehiclesRedirectsToVehicleCreationAndDropsThePendingEdit() {
        let router = AppRouter(hasVehicles: { false })
        router.presentEditForm(for: makeEntry())
        #expect(router.activeSheet == .vehicleForm)
        #expect(router.pendingEditEntry == nil)
    }

    @Test func dismissSheetEndsThePresentationAndTheEditHandoffWithIt() {
        let router = AppRouter(hasVehicles: { true })
        router.presentEditForm(for: makeEntry())
        router.dismissSheet()
        #expect(router.activeSheet == nil)
        #expect(router.pendingEditEntry == nil)
    }

    /// The three handoff sources are mutually exclusive: starting one clears the other two, so a
    /// form can never see, say, a voice prefill AND a pending edit from two abandoned flows.
    @Test func startingOneHandoffClearsTheOtherTwo() {
        let router = AppRouter(hasVehicles: { true })
        router.presentVoicePrefilledForm(proposal())
        router.presentEditForm(for: makeEntry())
        #expect(router.pendingVoicePrefill == nil)
        #expect(router.pendingEditEntry != nil)

        router.presentReceiptPrefilledForm(receiptPackage())
        #expect(router.pendingEditEntry == nil)
        #expect(router.pendingReceiptPrefill != nil)
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
            attachments: [], token: nil, quota: nil
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
