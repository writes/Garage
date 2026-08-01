import Foundation

// Supporting types for the analytics contract: the closed enums every event parameter is drawn
// from, plus the definition/parameter plumbing.
//
// Split out of AnalyticsService.swift purely for file length. The important property is that
// `AnalyticsParameter` admits only `Int` and enums declared here — a call site cannot pass a
// caller-supplied String, so a UID, email, VIN or provider error message cannot structurally
// reach Analytics. See docs/developer/ANALYTICS_CONTRACT.md.

// `reminders` was removed 2026-07-28: reminders are not Pro-gated, no surface ever presented
// `.subscription(.reminders)`, and a dead source makes per-surface conversion LOOK complete
// while measuring nothing. Re-add it only together with an actual reminders upsell.
enum PaywallSource: String, CaseIterable, Equatable, Sendable {
    case settings
    case garage
    case exportPDF = "export_pdf"
    case stats
    case themePicker = "theme_picker"
    case attachments
    /// The three below were previously reported as `settings`, which conflated genuinely distinct
    /// upsell surfaces into one bucket. Per-surface conversion was not merely inaccurate — with
    /// three surfaces sharing a source, it was uncomputable, so there was no way to tell whether
    /// the voice upsell converts and the oil-analysis one does not, or the reverse.
    case voiceQuickAdd = "voice_quick_add"
    case oilAnalysis = "oil_analysis"
    /// The free 1-vehicle cap. Highest-intent moment in the product: the user has already decided
    /// they want a second car.
    case vehicleLimit = "vehicle_limit"
    /// The free-lifetime receipt-scan teaser exhausted (§5 of the receipt-capture plan) — the
    /// highest-intent moment for that funnel, distinct from every other surface.
    case receiptScan = "receipt_scan"
}

enum AnalyticsProductID: String, CaseIterable, Equatable, Sendable {
    case monthly = "garage_pro_monthly"
    case annual = "garage_pro_annual"
    /// The receipt-credits consumable. Its purchase lifecycle reports through the dedicated
    /// `receipt_credits_*` family; this case exists so the store↔analytics identifier mapping
    /// stays one closed, test-pinned surface.
    case receiptCredits10 = "receipt_credits_10"

    init?(storeProductIdentifier: String) {
        switch storeProductIdentifier {
        case Constants.monthlyPlanIdentifier:
            self = .monthly
        case Constants.annualPlanIdentifier:
            self = .annual
        case Constants.receiptCreditsPackIdentifier:
            self = .receiptCredits10
        default:
            return nil
        }
    }
}

enum OilAnalysisQuotaDeniedReason: String, CaseIterable, Equatable, Sendable {
    case freeLifetimeExhausted = "free_lifetime_exhausted"
    case proDailyExhausted = "pro_daily_exhausted"
}

// Receipt-funnel closed enums (ReceiptCaptureSource/ReceiptFailureReason/ReceiptQuotaDeniedReason)
// live in AnalyticsTypes+Receipt.swift — split out to keep this file under the file-length cap.

struct AnalyticsEventDefinition: Equatable, Sendable {
    let name: String
    let parameters: [AnalyticsParameter]

    init(name: String, parameters: [AnalyticsParameter] = []) {
        self.name = name
        self.parameters = [.schemaVersion(1)] + parameters
    }

    var firebaseParameters: [String: Any] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.firebaseValue) })
    }
}

enum AnalyticsParameter: Equatable, Sendable {
    case schemaVersion(Int)
    case entryType(EntryType)
    case source(PaywallSource)
    case productID(AnalyticsProductID)
    case entryCount(Int)
    case reason(OilAnalysisQuotaDeniedReason)
    case provider(AuthProvider)
    case failureReason(SignInFailureReason)
    case form(FormKind)
    case voiceFailureReason(VoiceFailureReason)
    case purchaseFailureReason(PurchaseFailureReason)
    case oilAnalysisFailureReason(OilAnalysisFailureReason)
    case recallFailureReason(RecallLookupFailureReason)
    case receiptCaptureSource(ReceiptCaptureSource)
    case receiptFailureReason(ReceiptFailureReason)
    case receiptQuotaDeniedReason(ReceiptQuotaDeniedReason)
    case receiptPrefillField(ReceiptPrefillField)
    case recallCount(Int)
    case vehicleCount(Int)
    case screen(ScreenKind)
    /// Sent as 0/1 — Firebase has no boolean parameter type.
    case isEdit(Bool)
    /// Sent as 0/1 — receipt-field outcomes never contain a field value.
    case edited(Bool)
    // Experimentation batch (2026-07-30) — closed enums live in AnalyticsTypes+Experiment.swift.
    case experiment(ExperimentID)
    case arm(ExperimentArm)
    case epoch(Int)
    case feature(UninstrumentedFeature)
    case notifCategory(NotificationCategory)
    case survey(SurveyKind)
    /// Survey scores are clamped 1...5 at definition time so a UI defect cannot ship an
    /// out-of-range value into the frozen schema.
    case easeScore(Int)
    case visualScore(Int)
    /// Sent as 0/1.
    case wouldSwitch(Bool)
    // Receipt-credits funnel (2026-07-31) — enums in AnalyticsTypes+Reasons.swift.
    case creditsScope(ReceiptCreditsOfferScope)
    case creditsFailureReason(ReceiptCreditsPurchaseFailureReason)

    fileprivate var name: String {
        switch self {
        case .schemaVersion: return "schema_version"
        case .entryType: return "entry_type"
        case .source: return "source"
        case .productID: return "product_id"
        case .entryCount: return "entry_count"
        case .reason: return "reason"
        case .provider: return "provider"
        case .failureReason: return "failure_reason"
        case .form: return "form"
        case .experiment: return "experiment"
        case .arm: return "arm"
        case .epoch: return "epoch"
        case .feature: return "feature"
        case .notifCategory: return "category"
        case .survey: return "survey"
        case .easeScore: return "ease_score"
        case .visualScore: return "visual_score"
        case .wouldSwitch: return "would_switch"
        case .creditsScope: return "scope"
        case .creditsFailureReason: return "reason"
        // The failure/denial-reason parameters share the wire name "reason": each lives on a
        // different event, and one consistent key is what BigQuery queries group on.
        case .voiceFailureReason, .purchaseFailureReason,
             .oilAnalysisFailureReason, .recallFailureReason,
             .receiptFailureReason, .receiptQuotaDeniedReason:
            return "reason"
        case .receiptCaptureSource: return "source"
        case .receiptPrefillField: return "field"
        case .recallCount: return "recall_count"
        case .vehicleCount: return "vehicle_count"
        case .screen: return "screen"
        case .isEdit: return "is_edit"
        case .edited: return "edited"
        }
    }

    fileprivate var firebaseValue: Any {
        switch self {
        case .schemaVersion(let value), .entryCount(let value),
             .recallCount(let value), .vehicleCount(let value):
            return value
        case .entryType(let value): return value.rawValue
        case .source(let value): return value.rawValue
        case .productID(let value): return value.rawValue
        case .reason(let value): return value.rawValue
        case .provider(let value): return value.rawValue
        case .failureReason(let value): return value.rawValue
        case .form(let value): return value.rawValue
        case .voiceFailureReason(let value): return value.rawValue
        case .purchaseFailureReason(let value): return value.rawValue
        case .oilAnalysisFailureReason(let value): return value.rawValue
        case .recallFailureReason(let value): return value.rawValue
        case .receiptCaptureSource(let value): return value.rawValue
        case .receiptFailureReason(let value): return value.rawValue
        case .receiptQuotaDeniedReason(let value): return value.rawValue
        case .receiptPrefillField(let value): return value.rawValue
        case .screen(let value): return value.rawValue
        case .isEdit(let value), .edited(let value): return value ? 1 : 0
        case .experiment(let value): return value.rawValue
        case .arm(let value): return value.rawValue
        case .epoch(let value): return max(0, value)
        case .feature(let value): return value.rawValue
        case .notifCategory(let value): return value.rawValue
        case .survey(let value): return value.rawValue
        case .easeScore(let value), .visualScore(let value): return min(5, max(1, value))
        case .wouldSwitch(let value): return value ? 1 : 0
        case .creditsScope(let value): return value.rawValue
        case .creditsFailureReason(let value): return value.rawValue
        }
    }
}

enum AuthProvider: String, CaseIterable, Equatable, Sendable {
    case apple
    case google
}

/// Top-level surfaces for `screen_viewed`. Tabs only — sheets already report `form_opened` or
/// `paywall_viewed`, and double-reporting one impression under two names corrupts both funnels.
enum ScreenKind: String, CaseIterable, Equatable, Sendable {
    case dashboard
    case garage
    case log
    case stats
    case settings
}

/// Which sheet a `form_opened` event refers to. Records what ACTUALLY opened, not what was
/// requested — `AppRouter.present` redirects entry sheets to vehicle creation when the account
/// has no vehicles, and attributing that open to `entry` would misreport the funnel.
///
/// The paywall is deliberately absent: it already reports `paywall_viewed`, and adding it here
/// would double-count the same impression.
enum FormKind: String, CaseIterable, Equatable, Sendable {
    case vehicle
    case entryPicker = "entry_picker"
    case entry
    case voiceQuickAdd = "voice_quick_add"
    case export
    case receiptCapture = "receipt_capture"
}

/// Closed set of sign-in failure causes. Deliberately coarse: it exists to separate "the user
/// changed their mind" from "the app is broken", which are opposite signals that a single
/// `sign_in_failed` count would conflate. `cancelled` is the expected majority and is NOT an error.
enum SignInFailureReason: String, CaseIterable, Equatable, Sendable {
    /// User backed out of the provider sheet. Expected, not a defect.
    case cancelled
    /// Connectivity or provider reachability.
    case network
    /// Timed out waiting on the provider (the Apple flow enforces its own deadline).
    case timeout
    /// Missing or invalid client configuration — a build or console misconfiguration, and the one
    /// reason here that always indicates a real defect.
    case configuration
    /// Provider returned successfully but the credential was unusable.
    case credential
    case unknown
}
