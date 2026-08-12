# A/B testing + user metrics — implementation plan (2026-07-30, rev 1 — Fable draft)

> Operator directive 2026-07-30: build the plan for (1) understanding how UI elements
> convert to Pro subscribers, (2) what long-time subscribers actually use, (3) purposeful
> assistance-first notifications, (4) which products provide the most value, (5) a first
> experiment testing MULTIPLE full app designs at once incl. per-design unique
> interactions. Constraints from the operator: **A/B testing is an indefinite,
> permanent capability**; the multi-design test specifically runs ONLY during the
> review/TestFlight phase with a select user group, and a single design is decided by
> production release. Two complete options: A = budget-minded, B = enterprise-grade /
> highest performance. Group-splitting policy delegated to Fable — answered in §3.
>
> Routing note: this is a Fable strategy draft; Sol co-review is required before
> execution (Routing v3). Any NEW analytics/experimentation SDK must pass the Law-4
> intake ritual (research-assay + graveyard) before adoption — both options below are
> designed so the default path needs NO new SDK.

---

## 1. What we already have (build on it, don't duplicate it)

- **Consent-gated analytics core**: the 4-step `AnalyticsEvent` pattern +
  `ANALYTICS_CONTRACT.md` governance + the applyProfile consent gate (events fired
  pre-consent are silently dropped — every new surface must respect this; it is the
  #1 recurring trap).
- **`PaywallSource` enum** (10 sources already: settings, garage, exportPDF, stats,
  themePicker, attachments, voiceQuickAdd, oilAnalysis, vehicleLimit, receiptScan) —
  this IS the "which UI element converts" attribution key; it already flows through
  `paywallDidAppear/Dismiss(source:)`.
- **RevenueCat webhook → Firestore mirror** (`users/{uid}.subscription`) — the
  server-side conversion + renewal truth. Client analytics report intent; the webhook
  reports money. All conversion metrics join on uid against this, never against
  client events alone.
- **Theme/design seam**: the in-Pro theming core (one `@MainActor` computed
  `Theme.Colors.primary` driving 7 call sites) — the reactivity spine a multi-design
  system extends rather than forks.
- **A recall/reminder engine** — the natural home of assistance-first notifications.
- **Firebase**: Analytics, Crashlytics, FCM, and (to enable) the free BigQuery export.

## 2. Measurement foundation (shared by both options — build once)

### 2.1 Event taxonomy v2 (extends the existing contract; ~25 new events)
Four funnels + one matrix. Every event carries user properties: `design_arm`,
`entitlement` (free/pro), `cohort_week` (first-seen ISO week), `experiment_epoch`.

1. **Activation funnel**: `first_vehicle_added` → `first_entry_saved` →
   `first_ai_feature_used{feature}` → `activation_complete` (all three within 7 days).
2. **Conversion funnel** (UI element → Pro): `upsell_exposure{source}` (an upsell
   surface RENDERED — cheap impressions denominator) → existing
   `paywall_view{source}` → `paywall_package_selected{product}` →
   `purchase_started` → client `purchase_succeeded` → **server-confirmed conversion**
   (RC webhook, joined offline). Attribution: last-touch `source` on the purchase +
   first-touch stored as a user property — both reported; last-touch is the default
   decision metric.
3. **Retention/feature-usage matrix**: one `feature_used{feature}` event with a
   closed enum (log_entry, receipt_scan, voice_add, oil_analysis, pdf_export,
   csv_export, reminders, recalls, warranty, stats, dossier, gallery, wear,
   theming). Rolled up weekly per user offline. NO values, NO content — names only
   (contract + privacy manifest unchanged in kind).
4. **Notification funnel**: `notif_delivered{category}` → `notif_opened{category}` →
   `notif_task_completed{category}` (the assist actually happened — opens are
   vanity; task completion is the metric) + a permanent 10% holdout for
   incrementality.
5. **Experiment exposure**: `experiment_exposure{experiment_id, arm, epoch}` fired
   once per user per experiment on first eligible render (post-consent). Exposure,
   not assignment, defines the analysis population.

### 2.2 Pipeline
Enable Firebase Analytics → BigQuery export (free tier) now — history only exists
from the day it is switched on. Conversion/renewal joins read the Firestore mirror
(scheduled export or the webhook's event records). Dashboards read BigQuery, never
the app.

### 2.3 Governance
Every new event lands via the existing 4-step pattern + `ANALYTICS_CONTRACT.md`
update in the same PR + the consent gate. Closed enums everywhere; no free-form
strings. This section is identical in both options — the options differ ABOVE the
foundation, not in it.

## 3. Group splitting — the delegated design decisions (Fable's answers)

**Unit of assignment: the persisted install-scoped UUID** — CORRECTED 2026-08-11: the shipped
implementation (`ExperimentStore.swift`) assigns per-install, not per-uid, and the analysis SQL
is keyed to `user_pseudo_id` to match (Sol B5; Law-1 ratification queued in the design-plan vote
session). ~~the Firebase uid~~ (not device, not session). Stable across
reinstalls, joins cleanly to RC and Firestore.

**Mechanism: deterministic hashing.** `bucket = sha256(experimentId + ":" + uid)`
→ uniform [0,1) → arm by pre-registered allocation ranges. No server round-trip on
the hot path, offline-correct, reproducible in SQL for analysis. Assignment is
also WRITTEN to the user's analytics properties and (Option B) to Firestore for
audit.

**Does a user see one design forever until we decide? YES — sticky per experiment.**
A user keeps exactly one design for the life of the design test. Switching designs
mid-test destroys the thing you are measuring (learning curves, habit formation,
retention are all within-design effects), confuses testers, and makes every metric
attribution ambiguous. The only sanctioned switch is an **epoch boundary** (below),
and a switched user's clock restarts: they are analyzed as a fresh exposure in the
new arm, their pre-switch data excluded from the new arm's metrics.

**Adding designs while the test runs: epochs, not live insertion.** A new design
never dilutes a running comparison. Policy:
- Each design-roster change bumps `experiment_epoch`.
- Existing users KEEP their arm if it survives; users of a killed arm are
  re-hashed across surviving+new arms (flagged as re-exposed).
- New users hash across the full current roster.
- At review-phase cohort sizes, prefer **successive elimination (tournament)**
  over an ever-growing k-arm test: wave 1 runs designs A/B/C two-three weeks →
  kill the worst on the pre-registered composite + surveys → wave 2 admits design
  D against the survivors. Statistically this is vastly more tractable with small
  n than 5+ simultaneous arms, and it converges to one winner by the production
  deadline by construction.

**Honest power math (decision-grade, not aspirational).** Subscription conversion
as a primary metric needs high-hundreds-to-thousands per arm to detect realistic
lifts (e.g., 5%→7% needs ≈1,800/arm at 80% power). A select TestFlight group will
not deliver that. Therefore, for the design megatest:
- **Primary decision metric = a pre-registered composite engagement index**:
  activation_complete rate, day-7 return rate, core-action completion
  (entries+scans per active day), and paywall CTR from exposure. These move with
  10–50× the event volume of purchases.
- **Plus structured tester preference**: after ≥1 week in an arm, an in-app
  3-question survey (task ease, visual preference 1–5, "would you switch?"), and
  for a small crossover subset a final week in the runner-up design with a forced
  A-vs-B preference. Within-subject preference at small n is worth more than
  underpowered between-subject conversion deltas.
- **Subscription conversion is tracked and reported but is a tiebreaker, not the
  significance gate**, until production-scale traffic exists (the indefinite
  post-launch program inherits it as primary once n supports it).
- **Analysis: Bayesian** (posterior probability each arm is best + expected loss),
  reviewed on a fixed weekly cadence — no daily peeking. Decision rule and
  decision DATE (production release) pre-registered in the experiment doc before
  wave 1 starts.

**Post-launch (indefinite program):** same machinery, but experiments become
scoped (one surface at a time — paywall copy, upsell placement, notification
timing), one active experiment per surface layer to avoid interaction effects
(Option B adds formal mutually-exclusive layers). Full-app-design tests do not
recur in production; component-level design tests do.

## 4. First experiment: the multi-design megatest

### 4.1 Architecture — all designs in ONE binary (iOS has no code-push)
- **`DesignPack` protocol**: tokens (palette, type scale, spacing, shape),
  component variants (navigation style: tab bar vs floating dock; list vs card
  density; entry-form layout), interaction variants (sheet-first vs push-first
  flows, gesture affordances, celebration moments), and copy accents. Injected at
  the root via SwiftUI environment (`\.designPack`), selected once at launch from
  the assignment — extends the existing Theme reactivity core (the theming-p1
  seam), it does not fork views wholesale. Shared business logic, ViewModels, and
  services are ARM-INVARIANT by construction; only presentation varies.
- **Per-design unique interactions**: legal and encouraged, but each unique
  interaction is a NAMED variant in the pack (`interaction_id` namespaced per
  pack) and every relevant event carries it — that is what makes "the user
  interactions unique to each one" analyzable rather than anecdotal.
- **Guardrails per arm** (all pre-registered): the 22 UI journeys must pass
  parameterized over every arm (run per-arm on a nightly lane, not per-PR — CI
  minutes); accessibility AA in every arm; paywall/IAP flows functional in every
  arm (App Review tests the shipped binary in whatever arm it hashes into);
  Crashlytics crash-free rate per arm as an automatic kill trigger.
- **Kill switch**: server config (`app_config/experiments`) can force any arm to
  the control design without a new build.

### 4.2 Rollout
TestFlight select group (grow it deliberately — see honesty note: recruit toward
≥50/arm minimum, ideally 100+/arm; below ~30/arm only the survey/crossover
evidence is decision-grade). Wave cadence 2–3 weeks; final decision locked by the
production-release date; the winning pack becomes THE design and the pack
machinery stays for future component tests.

## 5. UI-element → Pro conversion (permanent program)
The conversion funnel of §2 segmented by `PaywallSource` answers "which UI
elements convert" continuously: exposure→view→purchase rates per source, per
design arm, per entitlement state. Add the two missing pieces:
`upsell_exposure{source}` (denominator — today only paywall VIEWS are counted, so
a rarely-seen-but-potent surface is indistinguishable from a spammy weak one) and
first-touch source memory. Server-confirmed conversions only (RC webhook join).

## 6. Long-time member value (what do subscribers actually use)
- Definition: **long-time member = active Pro ≥90 days or ≥3 renewal events**
  (from the webhook's own event records — already stored).
- Weekly feature-usage share matrix (from `feature_used`) segmented: new-Pro
  (first 30d) vs long-time. The delta IS the answer to "what do they use most
  when they become long-time members".
- Week-1 feature adoption vs 90-day survival correlation (simple cohort table
  first; survival modeling only in Option B) → identifies the features that
  PREDICT retention → those get onboarding priority and notification support.
- Quarterly output: a one-page "feature value matrix" — usage share × retention
  correlation × conversion attribution (which sources fed conversions) × IAP
  attach (credits, once live). This is also the §8 "which products provide the
  most value" answer, refreshed quarterly rather than answered once.

## 7. Notifications — engagement with purpose (assistance-first doctrine)
Principle, pinned: a notification exists to help the owner maintain their vehicle,
never to farm opens. No streaks, no "we miss you", no dark-pattern re-engagement.
Catalog (each: trigger → deep link → completion metric):
1. Service reminder due/approaching (exists — becomes the flagship): due date or
   mileage projection → reminder detail → entry logged within 7d.
2. Mileage-based service forecast ("~500 mi to your next oil change" from
   odometer trend) → quick-add prefilled.
3. Recall alert (safety — already built server-side; highest priority, exempt
   from frequency caps) → recall detail viewed.
4. Warranty expiring (30d out) → warranty screen.
5. Seasonal prep (2×/year, regional: winter/summer checklist) → checklist.
6. Annual cost summary ready (ownership-cost recap, 1×/year) → stats.
7. Receipt-scan nudge ONLY as assistance: after a paper-receipt photo lands in
   gallery unprocessed (if detectable) — never a naked quota upsell.
Rules: global cap ≤2/week (recalls exempt), per-category opt-in (Settings),
quiet hours, all local-first where the data is on-device (reminders/mileage),
FCM only for server-side knowledge (recalls). Measurement: the §2 notification
funnel with task-completion as success + the permanent 10% holdout so
"notifications keep members engaged" is measured as INCREMENTAL retention, not
correlation. Category-level A/B (timing, copy) joins the indefinite program.

## 8. Which products provide the most value
Answered by the §6 quarterly feature value matrix. Concretely expected early
signals worth confirming: receipt scanning + voice quick-add drive conversion
(they gate on Pro at the moment of real need); PDF dossier/export drives
RETENTION and resale-moment word-of-mouth; recalls/reminders drive trust and
notification permission. The matrix replaces intuition with the same four columns
every quarter.

---

## 9. OPTION A — budget-minded (≈$0 incremental infra; ~1–2 weeks build)

| Layer | Choice |
|---|---|
| Assignment | Client-side deterministic hash; experiment registry = one server-editable Firestore doc (`app_config/experiments`, server-write-only, read via a tiny cached fetch) with allocations, epoch, kill switches. No new SDK — no Law-4 intake needed. |
| Exposure/events | Existing Firebase Analytics through the existing consent-gated pattern. |
| Warehouse | Firebase → BigQuery free-tier export + 3–5 scheduled SQL queries (funnels, retention matrix, per-arm composite). |
| Dashboards | Looker Studio (free) on those queries; weekly review ritual against the pre-registered decision doc. |
| Stats | Bayesian composite comparison in a checked-in Python script (`scripts/analytics/experiment_report.py`) run weekly — reproducible, versioned, no vendor. |
| Conversion truth | RC webhook mirror join in SQL (already exists). |
| Notifications | Local notifications for on-device triggers (reminders/mileage/seasonal) + manual FCM for recalls (exists); holdout via the same hash; no journey engine. |
| Surveys | In-app 3-question sheet writing one consented analytics event. |

Build order: (1) BigQuery export ON + taxonomy v2 events, (2) assignment lib +
registry + exposure event, (3) DesignPack seam + 2–3 packs, (4) SQL + report
script + decision doc, (5) survey sheet, (6) notification funnel + holdout.
Limitations accepted: manual weekly stats (no auto-stopping), discipline-based
experiment isolation (one per surface), no SRM alerting (the report script prints
a sample-ratio check instead), dashboard latency = daily export cadence.

## 10. OPTION B — enterprise-grade / highest performance (~4–8 weeks phased)

Everything in A, upgraded at the analysis/orchestration layers (the foundation is
identical — A is a strict subset, so A→B is an upgrade, not a rewrite):

| Layer | Choice |
|---|---|
| Assignment | Server-driven Experiment Service: Cloud Function assignment endpoint + Firestore-persisted per-uid assignments (audit trail, forced-arm overrides for QA, re-balance without client logic), mutually-exclusive experiment LAYERS (design / paywall / notifications) so concurrent experiments never interact; exposure logged server-side too. |
| Stats engine | Automated sequential Bayesian engine with pre-registered priors, auto-stop on expected-loss threshold, CUPED variance reduction (pre-exposure activity as covariate — critical at small n), automatic SRM (sample-ratio mismatch) alerts. Candidate accelerator: GrowthBook (open-source, self-hosted, BigQuery-native) — **requires Law-4 intake before adoption**; the in-house engine is the default if intake tiers it below A. |
| Pipeline | Streaming BigQuery export + dbt models (funnel/retention/feature marts, tested), Crashlytics BigQuery export joined for per-arm guardrails. |
| Product analytics | Self-hosted PostHog OR Amplitude (both require Law-4 intake; BigQuery+Looker remains the no-new-vendor fallback) for ad-hoc path/cohort exploration. |
| Notifications | Orchestration engine: per-user notification state machine in Firestore + scheduled functions, per-category frequency capping enforced server-side, holdout + uplift reporting automated, send-time optimization as a category-level experiment. |
| Governance | Event schema registry with CI contract tests (extends ANALYTICS_CONTRACT.md into an enforced check), privacy checklist per event, experiment pre-registration template mandatory, quarterly metrics-quality audit (orphan events, consent leaks, SRM history). |
| Performance | Assignment resolution <1 frame (local cache, server reconcile async); zero added launch latency vs A. |

Cost: engineering time dominates; infra $0 (self-hosted/BigQuery tiers) to
low-$hundreds/mo (managed PostHog/Amplitude).

## 11. Recommendation and sequence
**Start with Option A immediately** — it fully serves the review-phase megatest
and all five operator questions at current scale — but build it ON the Option-B
shapes (the registry doc, the taxonomy, the exposure event, and the report
script are identical in both), so B is a layered upgrade triggered when (a) the
app has production traffic that supports conversion-primary experiments, or (b)
experiment cadence exceeds ~2 concurrent. The DesignPack seam, taxonomy, and
decision protocol are permanent either way.

Execution protocol per doctrine: Sol co-review of this plan → tri-vote any
contested substantive choice (assignment policy §3 and the composite decision
metric are the two vote-worthy candidates if Sol dissents) → Terra implements
behind the CI gate → instrument-audit before the TestFlight build that carries
wave 1.
