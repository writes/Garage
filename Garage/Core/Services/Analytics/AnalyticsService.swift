import FirebaseAnalytics
import Foundation

@MainActor
protocol AnalyticsTracking: AnyObject {
    func track(_ event: AnalyticsEvent)
    func setEnabled(_ enabled: Bool)
    /// Fails closed after a user tries to revoke consent but persistence cannot confirm it.
    /// The suppression deliberately lasts for the current app session.
    func suppressCollectionForCurrentSession()
    /// Drop any events held awaiting a consent decision, because the identity they belong to is
    /// gone (sign-out, or a profile that does not match the signed-in uid).
    ///
    /// Distinct from `setEnabled(false)`, which only means "consent is not known yet" and
    /// deliberately keeps held events. Without this separation, one account's pre-consent events
    /// could flush into the next account's consent grant.
    func discardPendingEvents()
}

extension AnalyticsTracking {
    func suppressCollectionForCurrentSession() {
        setEnabled(false)
    }

    func discardPendingEvents() {}
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

    // MARK: Depth batch (additive, 2026-07-28) — see docs/developer/ANALYTICS_CONTRACT.md

    /// Voice funnel. Voice quick-add is a paid Pro feature whose captures, outcomes, and saves
    /// were previously invisible past the sheet opening — there was no way to tell whether it
    /// produces entries at all.
    case voiceCaptureStarted
    case voiceProposalSucceeded(entryType: EntryType)
    case voiceProposalFailed(reason: VoiceFailureReason)
    /// A voice-prefilled form was actually SAVED. This is the number the feature exists for;
    /// without it a voice save is indistinguishable from a manual one.
    case voiceEntryConfirmed(entryType: EntryType)
    /// Opens the purchase funnel. `purchase_completed` alone cannot separate "tried and failed"
    /// from "never tried" — a StoreKit decline at the buy button was invisible.
    case purchaseAttempted(productID: AnalyticsProductID)
    case purchaseFailed(reason: PurchaseFailureReason)
    /// Non-quota, non-cancellation oil-analysis endings; `succeeded/requested` alone folded
    /// every real failure into an unexplained gap.
    case oilAnalysisFailed(reason: OilAnalysisFailureReason)
    /// Reminders had zero coverage despite being a retention surface.
    case reminderCreated
    case reminderCompleted
    case reminderDeleted
    /// The OS-level denial that silently disables reminder delivery.
    case notificationPermissionDenied
    /// Recall lookups are safety-relevant: reach and failure modes both matter.
    case recallLookupSucceeded(recallCount: Int)
    case recallLookupFailed(reason: RecallLookupFailureReason)
    /// A do-not-drive / park-outside advisory was actually shown to a user.
    case recallParkAlertShown
    /// Every vehicle add (not just the first). `vehicle_count` is the post-insert total, so the
    /// vehicle-limit paywall's back half (paywall -> actual second vehicle) finally closes.
    case vehicleAdded(vehicleCount: Int)
    case vehicleSwitched
    case vehicleDeleted
    /// Every entry save. `first_entry_added` fires once per account; which of the 13 forms
    /// people keep using after that was unmeasured.
    case entrySaved(entryType: EntryType, isEdit: Bool)
    case entryDeleted(entryType: EntryType)
    /// Tab-level engagement. Sheets are excluded — they already report `form_opened`.
    case screenViewed(screen: ScreenKind)
}

/// Thin adapter over `AnalyticsConsentGate`. All gate/buffer decisions live in that value type so
/// they are unit-testable without Firebase — the original defect slipped through precisely because
/// this logic was only reachable through a class that no test exercises.
@MainActor
final class FirebaseAnalyticsService: AnalyticsTracking {
    private var gate = AnalyticsConsentGate()

    func track(_ event: AnalyticsEvent) {
        send(gate.track(event))
    }

    func setEnabled(_ enabled: Bool) {
        let released = gate.setEnabled(enabled)
        Analytics.setAnalyticsCollectionEnabled(gate.isEnabled)
        // Order matters: collection must be enabled with Firebase before the held events are
        // logged, or the flush is dropped by the SDK exactly as it was by our own gate.
        send(released)
    }

    func suppressCollectionForCurrentSession() {
        gate.suppressForSession()
        Analytics.setAnalyticsCollectionEnabled(false)
    }

    func discardPendingEvents() {
        gate.discardPending()
    }

    private func send(_ events: [AnalyticsEvent]) {
        for event in events {
            let definition = event.definition
            Analytics.logEvent(definition.name, parameters: definition.firebaseParameters)
        }
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
