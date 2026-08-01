import Foundation

// The frozen event-name registry, split from AnalyticsEvent+Definitions.swift for the 300-line
// policy cap. These lists are asserted verbatim by tests — never mutate an existing list; add a
// new named group per additive batch (see ANALYTICS_CONTRACT.md §1 "Event names are frozen").
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

    /// Experimentation batch (additive, 2026-07-30) — exposure, upsell impressions,
    /// uninstrumented-feature usage, the notification funnel, and the in-app design survey.
    /// See ANALYTICS_CONTRACT.md §5.3.
    static let experimentationNames = [
        "experiment_exposure",
        "upsell_exposure",
        "feature_used",
        "notif_scheduled",
        "notif_opened",
        "notif_task_completed",
        "survey_submitted",
        "survey_dismissed"
    ]

    /// Receipt-credits funnel (additive, 2026-07-31) — the consumable top-up purchase and its
    /// server-grant lifecycle. See ANALYTICS_CONTRACT.md §5.4.
    static let receiptCreditsNames = [
        "receipt_credits_offer_shown",
        "receipt_credits_purchase_started",
        "receipt_credits_purchase_succeeded",
        "receipt_credits_purchase_failed",
        "receipt_credits_purchase_pending",
        "receipt_credits_grant_confirmed",
        "receipt_credits_grant_delayed",
        "receipt_credits_grant_missing",
        "receipt_credits_refund_observed"
    ]

    static var allNames: [String] {
        v1Names + activationFunnelNames + depthNames + receiptFunnelNames + experimentationNames
            + receiptCreditsNames
    }
}
