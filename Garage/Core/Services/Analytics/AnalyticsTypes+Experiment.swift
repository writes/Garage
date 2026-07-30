import Foundation

// Closed enums for the experimentation batch (additive, 2026-07-30) — see
// ANALYTICS_CONTRACT.md §5.3. Split from AnalyticsTypes.swift for the 300-line policy cap,
// mirroring the AnalyticsTypes+Receipt.swift precedent.

/// Compile-time experiment identifiers. A dynamic/string experiment id would let a typo create
/// a phantom experiment that silently splits traffic against nothing; a closed enum makes the
/// registry, the assignment library, and the analytics parameter agree by construction.
enum ExperimentID: String, CaseIterable, Equatable, Sendable, Codable {
    case designMegatest = "design_megatest"
}

/// Generic arm slots shared by every experiment. The MEANING of each slot for a given
/// experiment is defined in its registry entry and pre-registration doc, not here — that lets
/// arms stay a closed analytics enum (contract §1: no caller strings) while experiments come
/// and go without schema churn.
enum ExperimentArm: String, CaseIterable, Equatable, Sendable, Codable {
    case control
    case variantA = "variant_a"
    case variantB = "variant_b"
    case variantC = "variant_c"
}

/// Features that have NO existing analytics event. Everything else in the weekly feature-usage
/// matrix is derived in SQL from events that already exist (`entry_saved`, `export_pdf`,
/// `voice_entry_confirmed`, …) — re-emitting those under `feature_used` would double-count the
/// same action under two names, the exact corruption the contract's form/paywall exclusions
/// exist to prevent.
/// Deliberately small: `dossier` (covered by `export_pdf`) and `wear` (covered by
/// `entry_saved` + the dashboard's `screen_viewed`) were considered and EXCLUDED — a dead or
/// double-counting source makes coverage look complete while corrupting the matrix, the same
/// reason `PaywallSource.reminders` was removed.
enum UninstrumentedFeature: String, CaseIterable, Equatable, Sendable {
    case gallery
    case warranty
    case theming
}

/// Notification categories for the assistance-first funnel. v1 ships with the only
/// notification the app actually sends (user-created reminders); the enum is the extension
/// point for the roadmap categories (mileage forecast, seasonal, recalls) so their funnels
/// join the same three events instead of inventing new ones.
enum NotificationCategory: String, CaseIterable, Equatable, Sendable {
    case reminderDue = "reminder_due"
}

/// Which in-app survey a response belongs to.
enum SurveyKind: String, CaseIterable, Equatable, Sendable {
    case designMegatest = "design_megatest"
}

/// The complete closed set of Firebase user properties the app may set. Same structural
/// PII-guarantee as `AnalyticsParameter`: values are enum raw values or bounded ints rendered
/// server-side — a call site cannot pass a uid, email, or free-form string.
enum UserProperty: Equatable, Sendable {
    case designArm(ExperimentArm)
    case experimentEpoch(Int)
    case notifHoldout(Bool)

    var name: String {
        switch self {
        case .designArm: return "design_arm"
        case .experimentEpoch: return "experiment_epoch"
        case .notifHoldout: return "notif_holdout"
        }
    }

    var value: String {
        switch self {
        case .designArm(let arm): return arm.rawValue
        case .experimentEpoch(let epoch): return String(max(0, epoch))
        case .notifHoldout(let isHeldOut): return isHeldOut ? "1" : "0"
        }
    }
}
