import Foundation
import Testing
@testable import Garage

/// Covers the depth batch (2026-07-28): name stability, typed parameters, and the shared
/// `reason` wire key. See docs/developer/ANALYTICS_CONTRACT.md §5.1.
@MainActor
struct DepthBatchAnalyticsTests {
    @Test func depthNames_areStable() {
        #expect(AnalyticsEvent.depthNames == [
            "voice_capture_started",
            "voice_proposal_succeeded",
            "voice_proposal_failed",
            "voice_entry_confirmed",
            "purchase_attempted",
            "purchase_failed",
            "oil_analysis_failed",
            "reminder_created",
            "reminder_completed",
            "reminder_deleted",
            "notification_permission_denied",
            "recall_lookup_succeeded",
            "recall_lookup_failed",
            "recall_park_alert_shown",
            "vehicle_added",
            "vehicle_switched",
            "vehicle_deleted",
            "entry_saved",
            "entry_deleted",
            "screen_viewed"
        ])
    }

    @Test func depthDefinitions_carryTypedParameters() {
        #expect(AnalyticsEvent.voiceProposalSucceeded(entryType: .oilChange).definition
            == AnalyticsEventDefinition(name: "voice_proposal_succeeded", parameters: [.entryType(.oilChange)]))
        #expect(AnalyticsEvent.purchaseAttempted(productID: .annual).definition
            == AnalyticsEventDefinition(name: "purchase_attempted", parameters: [.productID(.annual)]))
        #expect(AnalyticsEvent.entrySaved(entryType: .fuel, isEdit: true).definition
            == AnalyticsEventDefinition(name: "entry_saved", parameters: [.entryType(.fuel), .isEdit(true)]))
        #expect(AnalyticsEvent.screenViewed(screen: .dashboard).definition
            == AnalyticsEventDefinition(name: "screen_viewed", parameters: [.screen(.dashboard)]))
    }

    /// Counts are clamped at the definition layer so a buggy caller cannot ship a negative.
    @Test func countParameters_clampNegativesToZero() {
        let recall = AnalyticsEvent.recallLookupSucceeded(recallCount: -3).definition
        #expect(recall.parameters.contains(.recallCount(0)))
        let vehicle = AnalyticsEvent.vehicleAdded(vehicleCount: -1).definition
        #expect(vehicle.parameters.contains(.vehicleCount(0)))
    }

    /// All four failure-reason parameters share the wire key "reason" — one key to group on in
    /// BigQuery — while staying distinct closed enums in code.
    @Test func failureReasons_shareTheReasonWireKey() {
        let events: [AnalyticsEvent] = [
            .voiceProposalFailed(reason: .emptyTranscript),
            .purchaseFailed(reason: .cancelled),
            .oilAnalysisFailed(reason: .preflight),
            .recallLookupFailed(reason: .vinMissing)
        ]
        let values = events.map { $0.definition.firebaseParameters["reason"] as? String }
        #expect(values == ["empty_transcript", "cancelled", "preflight", "vin_missing"])
    }

    @Test func isEdit_rendersAsIntFlag() {
        let params = AnalyticsEvent.entrySaved(entryType: .fuel, isEdit: false).definition.firebaseParameters
        #expect(params["is_edit"] as? Int == 0)
    }
}
