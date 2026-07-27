import FirebaseAnalytics
import Foundation

@MainActor
protocol AnalyticsTracking: AnyObject {
    func track(_ event: AnalyticsEvent)
    func setEnabled(_ enabled: Bool)
    /// Fails closed after a user tries to revoke consent but persistence cannot confirm it.
    /// The suppression deliberately lasts for the current app session.
    func suppressCollectionForCurrentSession()
}

extension AnalyticsTracking {
    func suppressCollectionForCurrentSession() {
        setEnabled(false)
    }
}

/// The complete v1 product-event contract.
///
/// Associated values deliberately use only closed enums and numeric counts. That makes it
/// impossible for a call site to send a UID, email address, VIN, or free-form text as an
/// Analytics parameter. The `first_*` events use a successful post-insert `count == 1`
/// check, which is a per-account-per-device approximation in v1 rather than global dedupe.
enum AnalyticsEvent: Equatable, Sendable {
    case firstVehicleAdded
    case firstEntryAdded(entryType: EntryType)
    case paywallViewed(source: PaywallSource)
    /// Closes the paywall funnel. `paywall_viewed` alone gives no denominator exit: without a
    /// dismissal event, "viewed but did not buy" is indistinguishable from "still deciding", so
    /// paywall conversion cannot be computed at all. Deliberately carries no outcome flag —
    /// pairing it with `purchase_completed` / `trial_started` on the same session yields
    /// abandonment without coupling this view to purchase state at teardown time.
    case paywallDismissed(source: PaywallSource)
    /// A non-authoritative client signal; server-side revenue joins remain the revenue truth.
    /// MUTUALLY EXCLUSIVE with `trialStarted` — a purchase that begins a free trial emits
    /// `trial_started` INSTEAD of this, so this count is money actually committed rather than
    /// money plus trials that may never convert.
    case purchaseCompleted(productID: AnalyticsProductID)
    /// A purchase that opened a free trial rather than charging immediately. Separating this from
    /// `purchase_completed` is what makes trial-start rate measurable at all; the trial-to-paid
    /// conversion itself is a server-side join, since no further client purchase event fires when
    /// a trial converts.
    case trialStarted(productID: AnalyticsProductID)
    case purchaseRestored
    case exportCSV(entryCount: Int)
    case exportPDF(entryCount: Int)
    case oilAnalysisRequested
    case oilAnalysisSucceeded
    case oilAnalysisQuotaDenied(reason: OilAnalysisQuotaDeniedReason)
    /// Sign-in funnel. Authentication is the first gate in the app — every later funnel step is
    /// conditioned on clearing it — yet drop-off here was previously invisible. `started` fires on
    /// real user intent (button tap), so started -> completed is a true completion rate.
    case signInStarted(provider: AuthProvider)
    case signInCompleted(provider: AuthProvider)
    /// `reason` is a closed enum produced by `SignInFailureClassifier`; raw error text is never
    /// sent, so a provider message containing an email or token cannot reach Analytics.
    case signInFailed(provider: AuthProvider, reason: SignInFailureReason)
    /// A create/edit sheet actually opened. `first_vehicle_added` and `first_entry_added` record
    /// completion, but nothing recorded intent — so the open -> complete rate, which is where
    /// drop-off actually happens, was invisible.
    case formOpened(form: FormKind)

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

    static var allNames: [String] { v1Names + activationFunnelNames }

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
        }
    }
}

@MainActor
final class FirebaseAnalyticsService: AnalyticsTracking {
    private var isEnabled = false
    private var isCollectionSuppressedForCurrentSession = false

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        let definition = event.definition
        Analytics.logEvent(definition.name, parameters: definition.firebaseParameters)
    }

    func setEnabled(_ enabled: Bool) {
        let effectiveEnabled = enabled && !isCollectionSuppressedForCurrentSession
        isEnabled = effectiveEnabled
        Analytics.setAnalyticsCollectionEnabled(effectiveEnabled)
    }

    func suppressCollectionForCurrentSession() {
        isCollectionSuppressedForCurrentSession = true
        setEnabled(false)
    }
}

@MainActor
final class NoopAnalyticsService: AnalyticsTracking {
    func track(_: AnalyticsEvent) {}

    func setEnabled(_: Bool) {}
}

@MainActor
enum AnalyticsService {
    static let shared: any AnalyticsTracking = {
#if DEBUG
        if AppRuntime.isLocalDemoMode || AppRuntime.isUITestMode {
            return NoopAnalyticsService()
        }
#endif
        return FirebaseAnalyticsService()
    }()
}

// WAVE-1 iOS-6L: Oil-analysis event call sites land with the typed AI wiring work.
