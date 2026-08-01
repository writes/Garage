# Analytics contract

> The complete set of product events the app emits, why each exists, and the rules any new event
> must follow. Source of truth: `Garage/Core/Services/Analytics/AnalyticsService.swift`.
> Name stability is enforced by tests — changing a name is a breaking change to every saved
> funnel, dashboard, and audience in Firebase.

---

## 1. Non-negotiable rules

**Parameters are closed enums or numbers. Never strings from a caller.**
`AnalyticsParameter` accepts only `Int` or a `RawRepresentable` enum defined in this codebase.
This is deliberate and structural: it makes it *impossible* for a call site to pass a UID, email,
VIN, registration, file name, or provider error message into Analytics. It is not a convention
that reviewers must police — the type system refuses.

**Every event carries `schema_version`.** Injected by `AnalyticsEventDefinition.init`, so it
cannot be forgotten. Currently `1`.

**Event names are frozen.** `v1Names` and `activationFunnelNames` are asserted verbatim in tests.
Renaming an event silently breaks historical continuity in Firebase — old and new names do not
join, and every funnel built on the old name reports zero without erroring.

**Consent is authoritative and fails closed.** `AppState.applyProfile` drives both Analytics and
Crashlytics from `profile.analyticsOptOut`. If persistence cannot confirm a revocation,
`suppressCollectionForCurrentSession()` disables collection for the rest of the session.

**Client revenue events are not revenue truth.** `purchase_completed` is a client signal only.
Revenue reconciliation is server-side, via the RevenueCat webhook.

---

## 2. Event reference

### Activation

| Event | Parameters | Purpose |
|---|---|---|
| `form_opened` | `form` | Intent. Pairs with the `first_*` events to give an open → complete rate. |
| `first_vehicle_added` | — | First real value moment. Per-account-per-device approximation (post-insert `count == 1`). |
| `first_entry_added` | `entry_type` | The activation event — a vehicle with no records is not an activated user. |

**`form_opened` reports what actually opened, not what was requested.** `AppRouter.present`
redirects entry sheets to vehicle creation on a zero-vehicle account (a previously-fixed
activation dead end). Attributing that open to `entry` would claim the user saw a form they never
saw — and it would do so at exactly the Day-0 moment that matters most. The paywall is excluded
from this event because it already reports `paywall_viewed`; emitting both would double-count one
impression.

### Sign-in funnel

| Event | Parameters | Purpose |
|---|---|---|
| `sign_in_started` | `provider` | Fired on button tap — real user intent. |
| `sign_in_completed` | `provider` | `started → completed` is a true completion rate. |
| `sign_in_failed` | `provider`, `failure_reason` | Separates "changed their mind" from "app is broken". |

**Why this is instrumented in `AuthViewModel`, not `AuthService`:** the Sign in with Apple flow
completes Apple's own UI *before* `AuthService.signInWithApple` is ever called. Instrumenting
deeper would miss every abandonment inside Apple's sheet — the largest drop-off in the funnel.
`AuthViewModel.perform(provider:)` is the single choke point both providers pass through.

`failure_reason` is produced by `SignInFailureClassifier`, a pure `Error -> enum` function. It
exists so a cause can be reported without ever sending provider error text, which routinely
embeds the account email or a token fragment. **`cancelled` is the expected majority and is not a
defect** — only `configuration` reliably indicates a real bug.

### Monetisation

| Event | Parameters | Purpose |
|---|---|---|
| `paywall_viewed` | `source` | Funnel entry, attributed to the surface that triggered it. |
| `paywall_dismissed` | `source` | Funnel exit. |

**One source per surface — `settings` used to be three surfaces.** Voice Quick-Add
(`VoiceQuickAddView`) and the oil-analysis PDF import (`OilAnalysisFormView`) both presented
`.subscription(.settings)`, so their impressions landed in the same bucket as the genuine Settings
upsell. With three surfaces sharing a source, per-surface conversion is not merely noisy — it is
uncomputable, and "the voice upsell converts, the oil one does not" is indistinguishable from the
reverse. They now report `voice_quick_add` and `oil_analysis`. `vehicle_limit` was added at the
same time for the free 1-vehicle cap, which previously showed no paywall at all.

The current sources are `settings`, `garage`, `export_pdf`, `stats`, `theme_picker`,
`attachments`, `voice_quick_add`, `oil_analysis`, `vehicle_limit`, `receipt_scan` — one per
presentation site (`reminders` was removed 2026-07-28: reminders are not Pro-gated and no surface
ever fired it), and
`everyPaywallSource_hasAMatchingDismissedEvent` iterates `allCases`, so a new source is covered the
moment it is declared.
| `purchase_completed` | `product_id` | Money actually committed. Client signal; server is revenue truth. |
| `trial_started` | `product_id` | A purchase that opened a free trial rather than charging. |
| `purchase_restored` | — | Restore path reachability. |

**`purchase_completed` and `trial_started` are mutually exclusive.** A purchase that begins a free
trial emits `trial_started` and *not* `purchase_completed`. Emitting both would leave the paid
count inflated by trials that may never convert — the exact defect this split exists to remove. A
test asserts exactly one fires for every billing phase.

The decision is made in `PurchaseServiceState` from `EntitlementSnapshot.period`, which carries
RevenueCat's `PeriodType` mapped at the SDK boundary in `RevenueCatValueMapper.period`. `prepaid`
(Play Store only) and any future SDK case map to `.unknown`, never `.normal`, so an unmapped
phase can never be silently counted as a paid purchase.

**Trial-to-paid conversion is a server-side join, not a client event.** When a trial converts,
StoreKit renews silently — no further client purchase event fires. The client can measure
*trial-start rate*; conversion itself comes from RevenueCat.

**Why `paywall_dismissed` had to exist.** With only `paywall_viewed`, "viewed and left" is
indistinguishable from "viewed and is still deciding" — the funnel has no denominator exit, so
paywall conversion is not merely inaccurate, it is *uncomputable*. It deliberately carries no
outcome flag; abandonment is derived by joining against `purchase_completed` in the same session.
Coupling the view's teardown to purchase state would introduce a race at exactly the moment the
purchase is settling.

### Export and AI

| Event | Parameters |
|---|---|
| `export_csv` / `export_pdf` | `entry_count` (clamped `>= 0`) |
| `oil_analysis_requested` / `oil_analysis_succeeded` | — |
| `oil_analysis_quota_denied` | `reason` |

---

## 3. Consent gating and the pre-consent buffer

Consent is not knowable until the user profile loads, and the profile cannot load until the user
has signed in. Under a plain `guard isEnabled` gate that makes the **entire sign-in funnel
unobservable** — every `sign_in_*` event fires while the gate is still closed. That is exactly
what shipped on 2026-07-27 and had to be repaired.

`AnalyticsConsentGate` resolves it by holding pre-consent events rather than dropping them:

| Transition | Held events |
|---|---|
| `track` while enabled | sent immediately |
| `track` while consent unknown | **held** (capped at 32, oldest dropped) |
| `setEnabled(true)` — the only affirmative consent signal | **released, in order** |
| `setEnabled(false)` — consent merely *unknown* | **retained**, still unsent, still on device |
| `discardPendingEvents()` — identity gone | **dropped** |
| `suppressCollectionForCurrentSession()` | **dropped**, and nothing accumulates afterwards |

**Why `setEnabled(false)` does not discard.** It is overloaded in this app: app start, bootstrap,
and every auth-state change all call it, and at those moments consent is simply *not yet known*.
Discarding there is what broke the funnel.

**Why identity changes must discard explicitly.** Sign-out and a profile/uid mismatch mean the
held events belong to an identity that is gone. Retaining them would let one account's
pre-consent events flush into the *next* account's consent grant — a privacy defect strictly
worse than the missing funnel it would fix. `AuthService.signOut` and the `applyProfile`
identity-mismatch branch both call `discardPendingEvents()`.

Nothing ever leaves the device before consent is affirmatively granted, in any path.

**Why the gate is a pure value type.** The original defect survived a green test run because the
gate lived only inside `FirebaseAnalyticsService`, which no unit test exercises, while the test
spies recorded unconditionally. `AnalyticsConsentGate` is directly unit tested — including a
replay of the exact production sequence that used to release nothing.

> ⚠️ **Test spies do not model the gate.** `AnalyticsSpy` and `NoopAnalyticsService` record or
> discard unconditionally. They are correct for asserting *"the view model called track"*, but a
> passing spy assertion is **not** evidence that an event reaches Firebase. For anything that
> fires early in the lifecycle, assert against `AnalyticsConsentGate` as well.

---

## 4. Known gaps

**No onboarding step events.** Drop-off between install and first vehicle is invisible — and there
is currently no onboarding flow to instrument. See
`docs/research/2026-07-27_OPTIMIZATION_BACKLOG.md`.

**No session-level first-open event.** Day-0 cohorting currently relies on Firebase's automatic
`first_open`, which cannot be joined to in-app funnel steps as precisely as an owned event would
allow.

---

## 5. Adding an event

1. Add a case to `AnalyticsEvent`.
2. Add its mapping in `definition` — name plus typed parameters.
3. Add the name to `activationFunnelNames` (or a new named group). Never mutate `v1Names`.
4. If it needs a new parameter, add a case to `AnalyticsParameter` with a closed enum payload.
   **If you find yourself wanting a `String` payload, stop** — that is the leak this design
   prevents. Model the values as an enum instead.
5. Extend the name-stability test.
6. Fire it from the narrowest choke point that still sees the whole user intent.

---

## 5.1 Depth batch (additive, 2026-07-28)

Twenty events closing the coverage gaps a full-surface inventory found (voice was a PAID
feature with no funnel; purchases had success-only telemetry; reminders, recalls, and the
Dashboard tab had zero events). Names live in `AnalyticsEvent.depthNames`; all parameters are
closed enums or clamped ints, unchanged rules.

| Group | Events | Choke point |
|---|---|---|
| Voice funnel | `voice_capture_started`, `voice_proposal_succeeded`, `voice_proposal_failed(reason)`, `voice_entry_confirmed` | `VoiceQuickAddViewModel` (start/outcome); `EntryFormViewModel.finishSaveTracking` (confirmed, via the `wasVoiceSeeded` flag) |
| Purchase funnel | `purchase_attempted(product_id)`, `purchase_failed(reason)` | `SubscriptionViewModel` — attempted fires only when the store call is actually made; `busy` taps are neither attempts nor failures. Success stays with the commit relay's `purchase_completed`/`trial_started`. |
| Oil analysis | `oil_analysis_failed(reason: preflight/service)` | `OilAnalysisImportCoordinator`; quota denials keep their own event. Cancellation is deliberately untracked (the cancel path also runs on teardown/deinit); abandonment = requested − (succeeded + failed + quota_denied) |
| Reminders | `reminder_created/completed/deleted`, `notification_permission_denied` | `ReminderConfigViewModel`, success paths only |
| Recalls | `recall_lookup_succeeded(recall_count)`, `recall_lookup_failed(reason)`, `recall_park_alert_shown` | `RecallLookupService` — park-alert fires at result time when any recall carries `parkIt`/`parkOutside` |
| Vehicles | `vehicle_added(vehicle_count)`, `vehicle_switched`, `vehicle_deleted` | `VehicleFormViewModel` (post-insert count closes the vehicle-limit paywall's back half); `AppState.selectVehicle`/`deleteVehicle` |
| Entries | `entry_saved(entry_type, is_edit)`, `entry_deleted(entry_type)` | `EntryFormViewModel.save` / `EntryService.deleteEntry` (same single-choke-point rule as the attachment cascade) |
| Tabs | `screen_viewed(screen)` | `AppState.selectedTab.didSet` + `reportInitialScreen()`; sheets are excluded — they already report `form_opened`/`paywall_viewed` |

The four failure-reason parameters share the wire name `reason` (one key to group on in
BigQuery); they remain distinct closed enums in code.

---

## 5.2 Receipt-capture funnel (additive, 2026-07-30)

Seven events instrument the receipt/invoice-scan feature. Names live in
`AnalyticsEvent.receiptFunnelNames`, separate from `depthNames` because this is one product funnel.
Pattern lineage is the voice funnel above — same closed-enum/no-PII rules, with `reason` retained
only for proposal failures and quota denials.

| Event | Parameters | Choke point |
|---|---|---|
| `receipt_capture_started` | `source` (`camera`/`library`/`pdf`) | `ReceiptCaptureViewModel`, on the first page of a scan (a second page never re-fires it) |
| `receipt_proposal_succeeded` | `entry_type` | `ReceiptCaptureViewModel`, on a successful `receiptQuickAdd` response |
| `receipt_proposal_failed` | `reason` (`preflight`/`not_a_receipt`/`service_error`) | `ReceiptCaptureViewModel`; user-cancel (backing out of a picker) is never reported as a failure |
| `receipt_quota_denied` | `reason` (`free_lifetime_exhausted`/`pro_month_exhausted`) | `ReceiptCaptureViewModel` — scan-ceiling and confirmed-reservation denials share the user-facing scope; neither is folded into `receipt_proposal_failed` |
| `receipt_entry_confirmed` | — | `EntryFormViewModel.finishSaveTracking`, via `wasReceiptSeeded` — fires exactly once, and never alongside `voice_entry_confirmed` (a form is seeded by at most one AI source) |
| `receipt_field_outcome` | `field` (`date`/`odometer`/`cost`/`shop`/`diy`/`notes`), `edited` (`0`/`1`) | `EntryFormViewModel.finishSaveTracking`, after local entry acceptance; one event for each effectively seeded field, never any parsed or user-entered value |
| `receipt_confirm_sync_failed` | — | The best-effort `confirmReceiptScan` call after local acceptance threw; this does not turn a saved entry into a failed save |

**Why receipts are not Pro-gated at the entry point, unlike voice.** The quota model is a
free-lifetime allowance of **5 confirmed saves** plus a Pro allowance of **20 confirmed saves per
UTC month**, not a hard Pro fence. The capture row stays visible to free users and free-lifetime
exhaustion upsells through `PaywallSource.receiptScan`. A scan ceiling (20 free lifetime / 80 Pro
per month) bounds API spend; the server reservation model remains authoritative for both counters.

**Raw presence and effective seed are intentionally separate.** `unreadReceiptFieldsCaption` uses
only the model's raw non-nil proposal fields, including `lineItems` as notes content, to show the
single “Not read from the receipt: …” caption. `receipt_field_outcome` instead snapshots effective
form values *after* `applyReceiptPrefill` and `reconcileReceiptOdometerFloor`. Consequently, an
odometer floor correction and its derived note, or the `shop → isDiy = false` derivation, are part
of the seed and report `edited = 0` unless the user subsequently changes them. Edit-then-revert is
also `0`; unseeded fields emit nothing. This is telemetry about field quality, not receipt content.

**Save is acceptance, confirmation is retry-safe accounting.** A response token is carried from
capture to the prefilled form. Only a successful local entry save attempts `confirmReceiptScan`; an
abandoned or failed form never does. The token is cleared before the fire-and-forget call starts,
and server idempotency tolerates an accidental retry. A thrown sync call emits
`receipt_confirm_sync_failed` without exposing its error detail or weakening the saved entry.

**Attachment interplay.** A parsed receipt's original image/PDF is staged as a pending attachment
only when the user is Pro (`EntryFormViewModel.receiptAttachmentNeedsPro` surfaces the upsell hint
otherwise) — this reuses the existing attachments Pro gate rather than adding a second one, and
does not emit a separate event; it is visible in the funnel only indirectly, via
`paywall_viewed(source: attachments)` if the user acts on the hint.

---

## 5.3 Experimentation batch (additive, 2026-07-30)

Ships with the Option A experimentation stack (`docs/research/2026-07-30_AB_TESTING_AND_METRICS_PLAN.md`).
Names live in `AnalyticsEvent.experimentationNames`; closed enums in `AnalyticsTypes+Experiment.swift`.

| Event | Parameters | Purpose |
|---|---|---|
| `experiment_exposure` | `experiment`, `arm`, `epoch` | Fired once per user per experiment EPOCH at first eligible render (`ExperimentStore.recordExposureIfNeeded`). Exposure, not assignment, defines the analysis population. |
| `upsell_exposure` | `source` | An upsell AFFORDANCE rendered — the impressions denominator `paywall_viewed` never had. Emitted by `ProGateView` (stats, garage, export_pdf, theme_picker, attachments) and the Settings upsell row. Sources whose paywall opens directly from a gated action (`vehicle_limit`, `voice_quick_add`, `oil_analysis`, `receipt_scan`) are documented as exposure == view. |
| `feature_used` | `feature` | ONLY features with no existing event: `gallery`, `warranty`, `theming` (fired on persisted theme change, not the optimistic apply). `dossier`/`wear` were considered and EXCLUDED — already covered by `export_pdf` / `entry_saved`+`screen_viewed`; double-emitting corrupts the matrix. |
| `notif_scheduled` | `category` | A notification actually handed to the OS (post-authorization). Deliberately NOT "delivered" — a client cannot honestly observe background delivery of a local notification. |
| `notif_opened` | `category` | User tapped the notification (`NotificationFunnelService`, the app's first `UNUserNotificationCenterDelegate` — which also fixes foreground banners being suppressed entirely). |
| `notif_task_completed` | `category` | The assisted task happened within 7 days of an open; at most one completion per open. Opens are vanity — this is the metric the notification exists for. |
| `survey_submitted` | `survey`, `ease_score`, `visual_score`, `would_switch` | The 3-question design survey. Scores clamp 1–5 at definition time; no free text can exist structurally. |
| `survey_dismissed` | `survey` | Closed without submitting — survey fatigue vs engagement. |

**User properties** (new surface — `AnalyticsTracking.setUserProperty`, closed `UserProperty`
enum): `design_arm`, `experiment_epoch`, `notif_holdout`. Consent-gated EXACTLY like events:
`AnalyticsConsentGate` holds pre-consent property sets (latest value per property wins,
bounded by the closed name set) and releases them on enable BEFORE the held events, so flushed
events carry the properties. Identity discard and session suppression drop held properties too.

**Assignment is not an event.** The deterministic hash recipe
(`ExperimentAssigner` — SHA-256 `"v1:<experiment>:<epoch>:<unit>"`, first 8 bytes big-endian
/ nextUp(2^64)) is pinned by independently computed test vectors; changing it reshuffles every
arm and is a breaking change to every running experiment.

**Notification holdout** (`notif_holdout`, 10%) gates PROACTIVE notifications only. No
proactive category exists yet; user-created reminders are NEVER suppressed — the property
ships now so the split exists in the data from day one.

## 5.4 Receipt-credits funnel (additive, 2026-07-31)

Ships with the consumable top-up client (`docs/research/2026-07-30_IAP_TOPUP_SPEC.md` §§17–24).
Names in `AnalyticsEvent.receiptCreditsNames`; enums in `AnalyticsTypes+Reasons.swift`.

| Event | Parameters | Purpose |
|---|---|---|
| `receipt_credits_offer_shown` | `scope` | The top-up affordance rendered (once per scope per sheet). Q3-C placement: `pro_month` directly at the cap; `free_lifetime` only after ≥1 receipt-scan paywall dismissal. |
| `receipt_credits_purchase_started` | — | Buy tapped. Fires BEFORE the identity/product preconditions, so identity-rejected and product-unavailable taps are included — read it as buy_tapped, not as StoreKit-reached (tri-review Sol advisory). |
| `receipt_credits_purchase_succeeded` | — | StoreKit success ONLY — the grant is server-side and reports separately. |
| `receipt_credits_purchase_failed` | `reason` | `identity_mismatch` / `store_error` / `product_unavailable`. Cancelled and Ask-to-Buy are NOT failures. |
| `receipt_credits_purchase_pending` | — | Ask-to-Buy/SCA deferral; may convert later via a status refresh. |
| `receipt_credits_grant_confirmed` | — | The server ledger reported `granted` for this client's transaction — the real outcome. |
| `receipt_credits_grant_delayed` | — | The 2/4/8/16/30s poll window elapsed without a grant; reconcile follows. |
| `receipt_credits_grant_missing` | — | Poll AND reconcile empty, or a marker expired at its 72h TTL. |
| `receipt_credits_refund_observed` | — | The ledger reported `refunded` for a polled transaction. |

**The ops alert query for lost webhooks** is `purchase_succeeded` without a later
`grant_confirmed` for the same user-session neighborhood (analytics are consent-gated, so this
is a signal — the reconcile callable is the repair, never analytics).

**Purchase-state truth lives server-side.** Client events chart the funnel; the credits
BALANCE and every grant/claw decision come from the transaction ledger via
`receiptQuotaStatus`/`reconcileReceiptCreditPurchase`.

## 6. Why funnel instrumentation was prioritised

The launch research (`docs/research/2026-07-27_BRANDING_AND_LAUNCH_PLAN.md`) found that **90% of
trial starts and 44.5% of all purchases occur on Day 0**, and **more than 90% of users churn
within 30 days**. First-session behaviour therefore dominates the business — and none of the
sign-in funnel or paywall exit was measurable before this contract was extended. You cannot
optimise a funnel whose steps you do not record.
