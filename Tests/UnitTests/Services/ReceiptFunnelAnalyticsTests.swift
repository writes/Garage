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
            "receipt_entry_confirmed"
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
    }

    /// Failure/denial-reason parameters across every batch share the wire key "reason" — one key
    /// to group on in BigQuery — while staying distinct closed enums in code.
    @Test func failureAndQuotaReasons_shareTheReasonWireKey() {
        let events: [AnalyticsEvent] = [
            .receiptProposalFailed(reason: .notAReceipt),
            .receiptQuotaDenied(reason: .proDailyExhausted)
        ]
        let values = events.map { $0.definition.firebaseParameters["reason"] as? String }
        #expect(values == ["not_a_receipt", "pro_daily_exhausted"])
    }

    @Test func receiptCaptureStarted_usesTheSourceWireKey() {
        let params = AnalyticsEvent.receiptCaptureStarted(source: .camera).definition.firebaseParameters
        #expect(params["source"] as? String == "camera")
    }
}
