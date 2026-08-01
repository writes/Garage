import FirebaseAnalytics
import Foundation

@MainActor
protocol AnalyticsTracking: AnyObject {
    func track(_ event: AnalyticsEvent)
    /// Sets a Firebase user property from the closed `UserProperty` set. Consent-gated exactly
    /// like events: pre-consent sets are HELD (latest value per property wins) and applied only
    /// when consent enables collection — a property set at launch must not reach Firebase for a
    /// user who later declines.
    func setUserProperty(_ property: UserProperty)
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
    func setUserProperty(_: UserProperty) {}

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

    // MARK: Receipt-capture funnel (additive, 2026-07-28) — see ANALYTICS_CONTRACT.md §5.2

    /// A receipt scan was started from a given source. Mirrors `voiceCaptureStarted`.
    case receiptCaptureStarted(source: ReceiptCaptureSource)
    case receiptProposalSucceeded(entryType: EntryType)
    case receiptProposalFailed(reason: ReceiptFailureReason)
    /// Quota denials keep their own event (the oil-analysis convention) rather than folding into
    /// `receiptProposalFailed`.
    case receiptQuotaDenied(reason: ReceiptQuotaDeniedReason)
    /// A receipt-prefilled form was actually SAVED, fired via `wasReceiptSeeded` — mutually
    /// exclusive with `voiceEntryConfirmed` (a form is seeded by at most one AI source).
    case receiptEntryConfirmed
    /// One privacy-safe quality label per effective receipt-prefilled field, emitted on save.
    case receiptFieldOutcome(field: ReceiptPrefillField, edited: Bool)
    /// The entry saved locally but its best-effort server confirmation did not complete.
    case receiptConfirmSyncFailed

    // MARK: Experimentation batch (additive, 2026-07-30) — see ANALYTICS_CONTRACT.md §5.3

    /// Fired once per user per experiment EPOCH on the first eligible render. Exposure, not
    /// assignment, defines the analysis population — an assigned-but-never-launched user must
    /// not dilute an arm.
    case experimentExposure(experiment: ExperimentID, arm: ExperimentArm, epoch: Int)
    /// An upsell AFFORDANCE rendered (locked row/button). `paywall_viewed` alone has no
    /// impressions denominator, so a rarely-seen-but-potent surface is indistinguishable from a
    /// spammy weak one. Only surfaces with a persistent locked affordance emit this; sources
    /// whose paywall opens directly from a gated action are documented as exposure == view.
    case upsellExposure(source: PaywallSource)
    /// Weekly-usage signal for the features that have NO existing event; everything already
    /// instrumented is derived in SQL instead (double-emitting would double-count).
    case featureUsed(feature: UninstrumentedFeature)
    /// `notif_scheduled`, deliberately not "delivered": a client cannot honestly observe
    /// background delivery of a local notification, and claiming delivery would corrupt the
    /// funnel's denominator.
    case notifScheduled(category: NotificationCategory)
    case notifOpened(category: NotificationCategory)
    /// The assisted task actually happened within the attribution window after an open —
    /// opens are vanity; this is the metric the notification exists for.
    case notifTaskCompleted(category: NotificationCategory)
    /// In-app design survey. Scores are 1–5, clamped at definition time; no free text ever.
    case surveySubmitted(survey: SurveyKind, easeScore: Int, visualScore: Int, wouldSwitch: Bool)
    case surveyDismissed(survey: SurveyKind)

    // MARK: Receipt-credits funnel (additive, 2026-07-31) — see ANALYTICS_CONTRACT.md §5.4

    case receiptCreditsOfferShown(scope: ReceiptCreditsOfferScope)
    case receiptCreditsPurchaseStarted
    /// StoreKit success only; the GRANT is server-side and reports separately below.
    case receiptCreditsPurchaseSucceeded
    case receiptCreditsPurchaseFailed(reason: ReceiptCreditsPurchaseFailureReason)
    /// Ask-to-Buy/SCA deferral — may still convert later via the next status refresh.
    case receiptCreditsPurchasePending
    /// The server ledger reported `granted` for this client's transaction — the real outcome.
    case receiptCreditsGrantConfirmed
    /// Poll window elapsed without a grant; reconcile follows. succeeded-without-confirmed is
    /// the lost-webhook ops alert query.
    case receiptCreditsGrantDelayed
    case receiptCreditsGrantMissing
    case receiptCreditsRefundObserved
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

    func setUserProperty(_ property: UserProperty) {
        apply(gate.setUserProperty(property))
    }

    func setEnabled(_ enabled: Bool) {
        let (releasedEvents, releasedProperties) = gate.setEnabledReleasingHeld(enabled)
        Analytics.setAnalyticsCollectionEnabled(gate.isEnabled)
        // Order matters twice over: collection must be enabled with Firebase before anything
        // held is flushed, and properties must land before events so the released events carry
        // the released properties.
        apply(releasedProperties)
        send(releasedEvents)
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

    private func apply(_ properties: [UserProperty]) {
        for property in properties {
            Analytics.setUserProperty(property.value, forName: property.name)
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
