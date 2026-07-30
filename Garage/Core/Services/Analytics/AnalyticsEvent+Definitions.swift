import Foundation

// The name registry and the event->definition mapping, split from AnalyticsService.swift for
// the 300-line policy cap. Cases stay in the enum declaration (Swift requires it); everything
// derived lives here.
extension AnalyticsEvent {
    static let v1Names = [
        "first_vehicle_added",
        "first_entry_added",
        "paywall_viewed",
        "purchase_completed",
        "purchase_restored",
        "export_csv",
        "export_pdf",
        "oil_analysis_requested",
        "oil_analysis_succeeded",
        "oil_analysis_quota_denied"
    ]

    /// Added in schema v1 (same version — these are additive events, not a breaking change to any
    /// existing event's shape). Kept as a separate list so the v1 contract stays auditable.
    static let activationFunnelNames = [
        "paywall_dismissed",
        "sign_in_started",
        "sign_in_completed",
        "sign_in_failed",
        "trial_started",
        "form_opened"
    ]

    /// Depth batch (additive, 2026-07-28): voice/purchase funnels, reminders, recalls, vehicle
    /// lifecycle, per-save entry usage, tab engagement.
    static let depthNames = [
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
    ]

    /// Receipt-capture funnel (additive, 2026-07-28) — see ANALYTICS_CONTRACT.md §5.2.
    static let receiptFunnelNames = [
        "receipt_capture_started",
        "receipt_proposal_succeeded",
        "receipt_proposal_failed",
        "receipt_quota_denied",
        "receipt_entry_confirmed",
        "receipt_field_outcome",
        "receipt_confirm_sync_failed"
    ]

    static var allNames: [String] { v1Names + activationFunnelNames + depthNames + receiptFunnelNames }

    /// Keeps every v1 event name and parameter definition in one audited mapping.
    var definition: AnalyticsEventDefinition {
        switch self {
        case .firstVehicleAdded:
            return AnalyticsEventDefinition(name: "first_vehicle_added")
        case .firstEntryAdded(let entryType):
            return AnalyticsEventDefinition(
                name: "first_entry_added",
                parameters: [.entryType(entryType)]
            )
        case .paywallViewed(let source):
            return AnalyticsEventDefinition(
                name: "paywall_viewed",
                parameters: [.source(source)]
            )
        case .paywallDismissed(let source):
            return AnalyticsEventDefinition(
                name: "paywall_dismissed",
                parameters: [.source(source)]
            )
        case .purchaseCompleted(let productID):
            return AnalyticsEventDefinition(
                name: "purchase_completed",
                parameters: [.productID(productID)]
            )
        case .trialStarted(let productID):
            return AnalyticsEventDefinition(
                name: "trial_started",
                parameters: [.productID(productID)]
            )
        case .purchaseRestored:
            return AnalyticsEventDefinition(name: "purchase_restored")
        case .exportCSV(let entryCount):
            return AnalyticsEventDefinition(
                name: "export_csv",
                parameters: [.entryCount(max(0, entryCount))]
            )
        case .exportPDF(let entryCount):
            return AnalyticsEventDefinition(
                name: "export_pdf",
                parameters: [.entryCount(max(0, entryCount))]
            )
        case .oilAnalysisRequested:
            return AnalyticsEventDefinition(name: "oil_analysis_requested")
        case .oilAnalysisSucceeded:
            return AnalyticsEventDefinition(name: "oil_analysis_succeeded")
        case .oilAnalysisQuotaDenied(let reason):
            return AnalyticsEventDefinition(
                name: "oil_analysis_quota_denied",
                parameters: [.reason(reason)]
            )
        case .signInStarted(let provider):
            return AnalyticsEventDefinition(
                name: "sign_in_started",
                parameters: [.provider(provider)]
            )
        case .signInCompleted(let provider):
            return AnalyticsEventDefinition(
                name: "sign_in_completed",
                parameters: [.provider(provider)]
            )
        case .signInFailed(let provider, let reason):
            return AnalyticsEventDefinition(
                name: "sign_in_failed",
                parameters: [.provider(provider), .failureReason(reason)]
            )
        case .formOpened(let form):
            return AnalyticsEventDefinition(
                name: "form_opened",
                parameters: [.form(form)]
            )
        case .voiceCaptureStarted:
            return AnalyticsEventDefinition(name: "voice_capture_started")
        case .voiceProposalSucceeded(let entryType):
            return AnalyticsEventDefinition(
                name: "voice_proposal_succeeded",
                parameters: [.entryType(entryType)]
            )
        case .voiceProposalFailed(let reason):
            return AnalyticsEventDefinition(
                name: "voice_proposal_failed",
                parameters: [.voiceFailureReason(reason)]
            )
        case .voiceEntryConfirmed(let entryType):
            return AnalyticsEventDefinition(
                name: "voice_entry_confirmed",
                parameters: [.entryType(entryType)]
            )
        case .purchaseAttempted(let productID):
            return AnalyticsEventDefinition(
                name: "purchase_attempted",
                parameters: [.productID(productID)]
            )
        case .purchaseFailed(let reason):
            return AnalyticsEventDefinition(
                name: "purchase_failed",
                parameters: [.purchaseFailureReason(reason)]
            )
        case .oilAnalysisFailed(let reason):
            return AnalyticsEventDefinition(
                name: "oil_analysis_failed",
                parameters: [.oilAnalysisFailureReason(reason)]
            )
        case .reminderCreated:
            return AnalyticsEventDefinition(name: "reminder_created")
        case .reminderCompleted:
            return AnalyticsEventDefinition(name: "reminder_completed")
        case .reminderDeleted:
            return AnalyticsEventDefinition(name: "reminder_deleted")
        case .notificationPermissionDenied:
            return AnalyticsEventDefinition(name: "notification_permission_denied")
        case .recallLookupSucceeded(let recallCount):
            return AnalyticsEventDefinition(
                name: "recall_lookup_succeeded",
                parameters: [.recallCount(max(0, recallCount))]
            )
        case .recallLookupFailed(let reason):
            return AnalyticsEventDefinition(
                name: "recall_lookup_failed",
                parameters: [.recallFailureReason(reason)]
            )
        case .recallParkAlertShown:
            return AnalyticsEventDefinition(name: "recall_park_alert_shown")
        case .vehicleAdded(let vehicleCount):
            return AnalyticsEventDefinition(
                name: "vehicle_added",
                parameters: [.vehicleCount(max(0, vehicleCount))]
            )
        case .vehicleSwitched:
            return AnalyticsEventDefinition(name: "vehicle_switched")
        case .vehicleDeleted:
            return AnalyticsEventDefinition(name: "vehicle_deleted")
        case .entrySaved(let entryType, let isEdit):
            return AnalyticsEventDefinition(
                name: "entry_saved",
                parameters: [.entryType(entryType), .isEdit(isEdit)]
            )
        case .entryDeleted(let entryType):
            return AnalyticsEventDefinition(
                name: "entry_deleted",
                parameters: [.entryType(entryType)]
            )
        case .screenViewed(let screen):
            return AnalyticsEventDefinition(
                name: "screen_viewed",
                parameters: [.screen(screen)]
            )
        case .receiptCaptureStarted(let source):
            return AnalyticsEventDefinition(
                name: "receipt_capture_started",
                parameters: [.receiptCaptureSource(source)]
            )
        case .receiptProposalSucceeded(let entryType):
            return AnalyticsEventDefinition(
                name: "receipt_proposal_succeeded",
                parameters: [.entryType(entryType)]
            )
        case .receiptProposalFailed(let reason):
            return AnalyticsEventDefinition(
                name: "receipt_proposal_failed",
                parameters: [.receiptFailureReason(reason)]
            )
        case .receiptQuotaDenied(let reason):
            return AnalyticsEventDefinition(
                name: "receipt_quota_denied",
                parameters: [.receiptQuotaDeniedReason(reason)]
            )
        case .receiptEntryConfirmed:
            return AnalyticsEventDefinition(name: "receipt_entry_confirmed")
        case .receiptFieldOutcome(let field, let edited):
            return AnalyticsEventDefinition(
                name: "receipt_field_outcome",
                parameters: [.receiptPrefillField(field), .edited(edited)]
            )
        case .receiptConfirmSyncFailed:
            return AnalyticsEventDefinition(name: "receipt_confirm_sync_failed")
        }
    }
}
