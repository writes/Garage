import Foundation

// The name registry and the event->definition mapping, split from AnalyticsService.swift for
// the 300-line policy cap. Cases stay in the enum declaration (Swift requires it); everything
// derived lives here.
extension AnalyticsEvent {
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
        case .experimentExposure(let experiment, let arm, let epoch):
            return AnalyticsEventDefinition(
                name: "experiment_exposure",
                parameters: [.experiment(experiment), .arm(arm), .epoch(epoch)]
            )
        case .upsellExposure(let source):
            return AnalyticsEventDefinition(
                name: "upsell_exposure",
                parameters: [.source(source)]
            )
        case .featureUsed(let feature):
            return AnalyticsEventDefinition(
                name: "feature_used",
                parameters: [.feature(feature)]
            )
        case .notifScheduled(let category):
            return AnalyticsEventDefinition(
                name: "notif_scheduled",
                parameters: [.notifCategory(category)]
            )
        case .notifOpened(let category):
            return AnalyticsEventDefinition(
                name: "notif_opened",
                parameters: [.notifCategory(category)]
            )
        case .notifTaskCompleted(let category):
            return AnalyticsEventDefinition(
                name: "notif_task_completed",
                parameters: [.notifCategory(category)]
            )
        case .surveySubmitted(let survey, let easeScore, let visualScore, let wouldSwitch):
            return AnalyticsEventDefinition(
                name: "survey_submitted",
                parameters: [
                    .survey(survey),
                    .easeScore(easeScore),
                    .visualScore(visualScore),
                    .wouldSwitch(wouldSwitch)
                ]
            )
        case .surveyDismissed(let survey):
            return AnalyticsEventDefinition(
                name: "survey_dismissed",
                parameters: [.survey(survey)]
            )
        }
    }
}
