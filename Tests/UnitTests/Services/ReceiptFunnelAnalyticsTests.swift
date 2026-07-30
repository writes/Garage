import Foundation
import Testing
@testable import Garage

/// Covers the receipt-capture funnel (2026-07-28): name stability, typed parameters, and the
/// shared `reason` wire key. See docs/developer/ANALYTICS_CONTRACT.md §5.2.
@MainActor
struct ReceiptFunnelAnalyticsTests {
    @Test func receiptFunnelNames_areStable() {
        #expect(AnalyticsEvent.receiptFunnelNames == [
            "receipt_capture_started",
            "receipt_proposal_succeeded",
            "receipt_proposal_failed",
            "receipt_quota_denied",
            "receipt_entry_confirmed",
            "receipt_field_outcome",
            "receipt_confirm_sync_failed"
        ])
    }

    @Test func receiptFunnelNames_areIncludedInAllNames() {
        for name in AnalyticsEvent.receiptFunnelNames {
            #expect(AnalyticsEvent.allNames.contains(name))
        }
    }

    @Test func receiptDefinitions_carryTypedParameters() {
        #expect(AnalyticsEvent.receiptCaptureStarted(source: .pdf).definition
            == AnalyticsEventDefinition(name: "receipt_capture_started", parameters: [.receiptCaptureSource(.pdf)]))
        #expect(AnalyticsEvent.receiptProposalSucceeded(entryType: .tire).definition
            == AnalyticsEventDefinition(name: "receipt_proposal_succeeded", parameters: [.entryType(.tire)]))
        #expect(AnalyticsEvent.receiptEntryConfirmed.definition
            == AnalyticsEventDefinition(name: "receipt_entry_confirmed"))
        #expect(AnalyticsEvent.receiptFieldOutcome(field: .odometer, edited: true).definition
            == AnalyticsEventDefinition(
                name: "receipt_field_outcome",
                parameters: [.receiptPrefillField(.odometer), .edited(true)]
            ))
        #expect(AnalyticsEvent.receiptConfirmSyncFailed.definition
            == AnalyticsEventDefinition(name: "receipt_confirm_sync_failed"))
    }

    /// Failure/denial-reason parameters across every batch share the wire key "reason" — one key
    /// to group on in BigQuery — while staying distinct closed enums in code.
    @Test func failureAndQuotaReasons_shareTheReasonWireKey() {
        let events: [AnalyticsEvent] = [
            .receiptProposalFailed(reason: .notAReceipt),
            .receiptQuotaDenied(reason: .proMonthExhausted)
        ]
        let values = events.map { $0.definition.firebaseParameters["reason"] as? String }
        #expect(values == ["not_a_receipt", "pro_month_exhausted"])
    }

    @Test func receiptCaptureStarted_usesTheSourceWireKey() {
        let params = AnalyticsEvent.receiptCaptureStarted(source: .camera).definition.firebaseParameters
        #expect(params["source"] as? String == "camera")
    }

    @Test func receiptFieldOutcome_usesOnlyClosedIdentifierAndBooleanParameters() {
        let parameters = AnalyticsEvent.receiptFieldOutcome(field: .notes, edited: false)
            .definition.firebaseParameters
        #expect(parameters["field"] as? String == "notes")
        #expect(parameters["edited"] as? Int == 0)
        #expect(parameters.count == 3) // field, edited, schema_version — never a receipt value.
    }

    @Test func fieldOutcomes_captureOdometerFloorAndDerivedNoteAfterReconciliation() {
        let analytics = enabledAnalytics()
        let viewModel = receiptForm(analytics: analytics)
        viewModel.applyReceiptPrefill(package(proposal(odometer: 84_500)), isPro: false)
        viewModel.lastKnownOdometer = 85_000

        viewModel.reconcileReceiptOdometerFloor()
        viewModel.finishSaveTracking(vehicleId: "vehicle", entryType: .maintenance, wasEdit: false)

        #expect(outcomes(in: analytics) == [
            .receiptFieldOutcome(field: .odometer, edited: false),
            .receiptFieldOutcome(field: .notes, edited: false)
        ])
    }

    @Test func fieldOutcomes_editThenRevertIsUnedited() {
        let analytics = enabledAnalytics()
        let viewModel = receiptForm(analytics: analytics)
        viewModel.applyReceiptPrefill(package(proposal(cost: 165)), isPro: false)
        viewModel.reconcileReceiptOdometerFloor()
        viewModel.cost = "200"
        viewModel.cost = "165"

        viewModel.finishSaveTracking(vehicleId: "vehicle", entryType: .maintenance, wasEdit: false)

        #expect(outcomes(in: analytics) == [.receiptFieldOutcome(field: .cost, edited: false)])
    }

    @Test func fieldOutcomes_neverEmitForUnseededFields() {
        let analytics = enabledAnalytics()
        let viewModel = receiptForm(analytics: analytics)
        viewModel.applyReceiptPrefill(package(proposal(isDiy: false)), isPro: false)
        viewModel.reconcileReceiptOdometerFloor()

        viewModel.finishSaveTracking(vehicleId: "vehicle", entryType: .maintenance, wasEdit: false)

        #expect(outcomes(in: analytics) == [.receiptFieldOutcome(field: .diy, edited: false)])
    }

    @Test func fieldOutcomes_treatEmptySeedAsAValueAndIgnoreZeroThatWasNotApplied() {
        let analytics = enabledAnalytics()
        let viewModel = receiptForm(analytics: analytics)
        viewModel.applyReceiptPrefill(package(proposal(cost: 0, notes: "")), isPro: false)
        viewModel.reconcileReceiptOdometerFloor()

        viewModel.finishSaveTracking(vehicleId: "vehicle", entryType: .maintenance, wasEdit: false)

        #expect(outcomes(in: analytics) == [.receiptFieldOutcome(field: .notes, edited: false)])
    }

    private func enabledAnalytics() -> AnalyticsSpy {
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        return analytics
    }

    private func receiptForm(analytics: AnalyticsSpy) -> EntryFormViewModel {
        EntryFormViewModel(analytics: analytics, firstEntryFollowUp: { _ in })
    }

    private func proposal(
        odometer: Int? = nil, cost: Double? = nil, isDiy: Bool? = nil, notes: String? = nil
    ) -> ReceiptEntryProposal {
        ReceiptEntryProposal(
            entryType: .maintenance, odometerReading: odometer, cost: cost, shopName: nil,
            isDiy: isDiy, entryDate: nil, notes: notes, lineItems: nil
        )
    }

    private func package(_ proposal: ReceiptEntryProposal) -> ReceiptPrefillPackage {
        ReceiptPrefillPackage(proposal: proposal, attachments: [], token: nil, quota: nil)
    }

    private func outcomes(in analytics: AnalyticsSpy) -> [AnalyticsEvent] {
        analytics.events.filter {
            if case .receiptFieldOutcome = $0 { return true }
            return false
        }
    }
}
