# Optimization backlog — evidence to code

> Translates `2026-07-27_BRANDING_AND_LAUNCH_PLAN.md` into concrete engineering work, ranked by
> measured leverage. Every item states the evidence, the current code state, and what "done" means.
> Items are marked ✅ done · 🔨 in progress · ⏸ blocked on an operator decision · 📋 queued.

---

## Findings from the codebase audit (2026-07-27)

Three things that the raw metrics got **wrong**, recorded so nobody re-opens them:

- **Crash-hardening is not a gap.** 0 force-unwraps, 0 `try!`, 0 `fatalError`, 0 `as!` across
  15,200 LOC. Stability work should not start here.
- **Dynamic Type already works.** Every `Theme.Typography` entry is a semantic text style that
  scales; the only fixed `.font(.system(size:))` calls are on icons, which is correct. The absence
  of `dynamicTypeSize` modifiers is *right* — it means no artificial cap is imposed.
- **Accessibility labels are adequate.** "13 labels / 72 buttons" is a false alarm: text-labelled
  buttons need no explicit label, and every genuinely icon-only control already has one.

And two things that are **real**, found by reading the flows rather than counting symbols.

---

## P0 — SHIPPED-BLOCKER: plan identifiers did not match App Store Connect

Found 2026-07-27 while the operator was wiring the RevenueCat entitlement. `Constants` carried
`garage_pro_monthly` / `garage_pro_annual`; App Store Connect only ever had
`com.writes.harrysplayhouse.pro.monthly` and `...pro.yearly` (note **yearly**, not annual).

**The failure mode is silent.** The offerings pipeline filters every package through
`AnalyticsProductID(storeProductIdentifier:)`, drops anything unrecognised into
`omittedUnknownProductIDs`, and renders an **empty paywall** — no error, no crash, nothing to buy.
RevenueCat's own product list showed both hardcoded IDs as **"Not found"** and the app never
noticed. Every tester would have hit a paywall with zero plans.

Fixed, plus `PlanIdentifierTests` asserting the invariants that would have caught it: store IDs
are reverse-DNS under the bundle prefix (a bare `garage_pro_monthly` cannot be a StoreKit product
for this app), the real IDs round-trip through the analytics mapping, and the stale IDs must NOT
resolve. Analytics raw values are deliberately left alone — they are stable Firebase labels, not
store SKUs.

**Operator action:** the two "Not found" products (`garage_pro_annual`, `garage_pro_monthly`,
created Jul 24) are dead entries pointing at nothing. Detach them from the `pro` entitlement and
delete them, or they will keep muddying the catalogue.

---

## P0 — Measurement (you cannot optimise what you do not record)

### ✅ Pre-consent buffering — repairs the sign-in funnel
Shipped. The sign-in funnel as first written emitted **nothing**: the consent gate is still closed
when `sign_in_*` fires, because consent is unknowable until the profile loads and the profile
cannot load until sign-in completes. `AnalyticsConsentGate` now holds pre-consent events and
releases them only on affirmative consent, while identity changes (sign-out, profile/uid mismatch)
discard them so one account cannot flush into another's consent. Pure value type, directly tested,
including a replay of the production sequence that used to release nothing.

### ✅ Sign-in funnel + paywall exit
Shipped. `sign_in_started/completed/failed`, `paywall_dismissed`. Before this, paywall conversion
was not merely inaccurate — it was **uncomputable**, because `paywall_viewed` had no exit event.
Contract: `docs/developer/ANALYTICS_CONTRACT.md`.

### ✅ `trial_started`
Shipped. `EntitlementPeriod` now rides on `EntitlementSnapshot`, mapped from RevenueCat's
`PeriodType` at the SDK boundary. A trial-opening purchase emits `trial_started` *instead of*
`purchase_completed` — mutually exclusive, asserted by test, so the paid count is money actually
committed rather than money plus trials that may never convert. `prepaid` and any future SDK case
map to `.unknown`, never `.normal`, so an unmapped phase cannot be silently counted as paid.

Trial-to-paid conversion itself remains a server-side join: StoreKit renews a converting trial
silently, so no further client purchase event fires.

### ✅ Form-open instrumentation
Shipped. `form_opened(form:)` fires from `AppRouter.present`, the single choke point every sheet
passes through. Paired with the existing `first_vehicle_added` / `first_entry_added`, the
open → complete rate is now measurable — that is where activation drop-off actually happens.

Reports what ACTUALLY opened, not what was requested: `present` redirects entry sheets to vehicle
creation on a zero-vehicle account, and attributing that to `entry` would claim the user saw a
form they never saw. The paywall is excluded because it already reports `paywall_viewed`.

---

## P1 — Activation (Day 0 decides the business)

**Evidence:** 90% of trial starts and 44.5% of all purchases occur on **Day 0**. 84% of
short-trial cancellations happen by Day 1. More than 90% of users churn within 30 days.

### 📋 Onboarding: narrower than first reported — CORRECTION
An earlier revision of this document claimed there was "no onboarding flow at all" and that a new
user "lands in an empty app with no guidance". **That was wrong**, and it was reached by grepping
for the word `onboarding` rather than by reading the flow.

What actually exists: `DashboardView.zeroVehicleState` renders a purpose-built empty state —
title "Add Your First Vehicle", explanatory copy, and a `PrimaryButton` CTA wired directly to the
vehicle form. Activation is also already instrumented: `first_vehicle_added` and
`first_entry_added` have shipped since v1. A new user is guided to the right action on arrival.

The genuine remaining gap is narrower and worth stating precisely:

- ~~**Form abandonment is unmeasured.**~~ ✅ Closed by `form_opened` (see P0).
- **There is no multi-step guided onboarding** (value prop, permission priming, staged setup).
  Whether that beats the current single clear CTA is a **product bet, not a defect**. Building it
  speculatively would be inventing work; it should be justified by the form-abandonment numbers
  once those exist.

**Done means:** the instrumentation is now in place. The guided-onboarding decision should wait
for real open → complete numbers rather than being built on assumption.

---

## P2 — Conversion (money-path; operator-gated per Law 1)

### ✅ Paywall hierarchy — the offer now leads
Shipped. Previous render order put `PrimaryButton("Refresh Plans")` — a maintenance affordance —
as the strongest control on a purchase screen, with the actual plans rendering **last**, below
policy links and disclosure copy.

New order: feature summary → blocking state (errors/activity) → **plans** → required disclosure →
policy links → Restore → Refresh (demoted to a plain button).

- **Annual leads.** Annual generates ~2x the revenue per install of monthly (D60 $0.46 vs $0.24).
  Ordering only: no plan is hidden, monthly is one tap away, no price or term changed.
  `SubscriptionPlanOrder` is extracted from the view and unit tested — including that the order is
  *total* with a deterministic tiebreak, because Swift's sort is not stable and same-rank packages
  would otherwise be free to swap between renders.
- **The leading plan gets the PrimaryButton.** Visual emphasis only. Deliberately **no savings
  percentage**: `PackageDTO` carries localized price *strings*, not decimals, so any computed
  discount would be fabricated.
- **Blocking state moved above the offer.** A user who cannot purchase should learn why without
  scrolling past plans they cannot use.
- **All required disclosure retained**, and moved to sit directly under the plans it describes:
  renewal terms per package, the review-before-purchase caption, and policy links. Nothing was
  removed — that copy is App Review-critical.
- **Package identifiers are now product-keyed** (`subscription.package.annual`) rather than
  positional. A positional id silently repoints at a different plan the moment ordering changes.
  `subscription.refresh` and `subscription.restore` are unchanged because UI journeys key the
  sheet off them.

### ⏸ Trial length 7 → 14 days
Trial-to-paid by length: ≤4 days 25.5% · **5–9 days 37.4%** (current) · 17–32 days 42.5%.
Longer trials convert better but cancel more, so the net is genuinely uncertain — which makes it
a good A/B, not a unilateral change. Configured in App Store Connect, not in code.

### ⏸ Paywall placement
Onboarding paywalls with a trial convert at 1.35% vs 0.89% post-onboarding — a ~52% relative
lift (Adapty, vendor-published). Depends on the onboarding flow existing first.

---

## P3 — Quality

### ✅ Light-mode WCAG-AA — fixed (operator decision, 2026-07-27)
Operator chose to darken both failing tokens. Hue and saturation preserved, lightness only:

| Token | Was | Now | On background | As badge text |
|---|---|---|---|---|
| `Accent` | `#D97D4A` | `#A95324` | 2.74 → **4.85:1** | 2.66 → **4.50:1** |
| `Warning` | `#E78A2A` | `#9F5A12` | 2.37 → **4.85:1** | 2.34 → **4.51:1** |

Light variants only — dark already cleared AA on every pairing.

**`BrandSecondary` was a false alarm and is unchanged.** An earlier revision listed it at 2.69:1,
but it is used exclusively as an 18% decorative fill (`WearItemBar`, `SkeletonLoader`) and never as
text, so contrast thresholds do not govern it. Changing a brand colour for a metric that does not
apply would have been wrong.

**Guarded by test from now on.** `ColorContrastTests` resolves the COMPILED asset catalog via
`UIColor(named:compatibleWith:)` in both appearances and computes WCAG contrast — body text,
semantic colours as status text, the badge-on-own-tint pattern, `OnPrimary` on all four accent
tints, fill-vs-background separation, and surface elevation. Contrast was previously invisible to
the whole pipeline: colours compile, the app builds, UI tests pass, and text can still be
unreadable. `Accent` sat at 2.74:1 for the entire life of the palette without anything noticing.

### 📋 ASO fields
Name ≤30 chars, subtitle ≤30, keywords ≤100 with no cross-field duplication. **Blocked on the
name.**

### 📋 iOS 18 dark/tinted app-icon variants
Unverified against Apple's spec. Note the trap: testing an alternate icon requires the variants
to already ship inside the published binary, so this is gated on a release cycle.

### ✅ Crashlytics dSYM upload — moved out of the build phase
The in-build `Upload dSYMs to Crashlytics` phase has hit its 90s watchdog on **every** Release
archive observed (builds 1–3). Consequence: every shipped build's crashes would have arrived as
unsymbolicated hex — precisely when a readable stack matters most.

**Two hypotheses were tested and both were wrong**, recorded so nobody repeats them:

- *"The 76 MB dSYM is too large for 90s."* No — a manual upload completes in **~2 seconds**.
- *"Xcode user-script sandboxing blocks the phase's network."* No — the Garage target sets
  `ENABLE_USER_SCRIPT_SANDBOXING: NO`, overriding the project-level `YES`.

A remaining hypothesis is a pipe-buffer deadlock (the phase backgrounds the tool then `sleep`s
instead of draining its output, so a full stdout pipe blocks the writer forever), but it is
**unverified** and stated as such.

Rather than keep guessing at the phase, the upload now runs in `scripts/release/testflight_build.sh`
immediately after export — where it is *proven* to work. It is fail-soft (symbolication is
diagnostics; losing it must not fail an otherwise good release) and, unlike the build phase,
reports honestly whether each dSYM actually uploaded.

Build 3's dSYM was uploaded manually and is confirmed live, so its crashes will symbolicate.

**Still open:** the in-build phase remains and still burns ~90s per Release archive emitting a
misleading warning. Removing it means editing PROTECTED `project.yml`. Worth doing, but it is a
protected-surface change and belongs in a deliberate commit rather than bundled here.

---

## Toolchain note

`.tools/bin/xcodegen` is **2.45.3**; the PATH binary is **2.45.4**, and they emit DIFFERENT
pbxproj — 2.45.4 adds `BUNDLE_LOADER` and an `LD_RUNPATH_SEARCH_PATHS` block to the test target.

**Use `.tools/bin/xcodegen generate`.** `verify-ios.sh` line 7 does
`PATH="$ROOT_DIR/.tools/bin:$PATH"`, so the bare `xcodegen generate` on line 33 resolves to the
*pinned* 2.45.3 binary — not the newer one on the ambient PATH. A project regenerated with plain
`xcodegen` therefore fails the regenerate-equality gate every time, and each attempt costs a full
gate cycle. (Read line 7 before line 33: the call site alone is misleading.)

Second trap in the same gate: it compares HEAD against freshly generated output, so **any untracked
`.swift` file under a source root fails it** — an in-progress file left on disk is picked up by
xcodegen and reads as drift. Finish and commit it, or move it out of the tree before gating.

---

# Second audit sweep — 2026-07-28

A six-dimension parallel audit (activation UX, retention, monetisation, reliability, AI,
architecture) over the whole Swift tree, then an independent verification pass that dropped eight
of the eighteen raw findings. Everything below was confirmed by reading the code, not by trusting
the finder.

## The pattern that hid the two worst defects

**Demo mode masks dead write paths.** `AppRuntime.isLocalDemoMode` branches live inside the
*service* layer and return `SeedData`. Demo mode therefore exercises the read path with rich data
and never touches the write path — so a feature with a read path, a seed path, and **no write path
at all** looks complete in every manual walkthrough and every App Store screenshot.

Two shipped features were in exactly that state:

### ✅ Wear tracking was a dead pipeline
`WearService.saveSnapshots` had **zero callers**. `BrakeFormView` and `TireFormView` hardcoded
`frontPadPct`/`rearPadPct`/`frontRotorPct`/`rearRotorPct` and all four tread-depth fields to `nil`.
`TireActionType.treadDepthReading` was an offered action that recorded nothing measurable. So the
Dashboard wear section and `WearHistoryChart` were permanently empty for every real user — the
empty state added to `WearHistoryChart` earlier in this branch was treating the symptom.

Both forms now collect the readings, and `WearSnapshotFactory` maps them to snapshots. The
tread-depth scale is a **safety judgement, not arithmetic**: percentage is measured against the
usable range (10/32" new → 2/32" legal minimum), so a tire at the legal limit reads 0%, not the 20%
a naive divide-by-ten would show. An axle reports its **worst** corner, because averaging hides one
bald tire behind a healthy one — the exact case a wear display exists to catch.

### ✅ Warranty & Recalls could never hold a record
`WarrantyService.saveWarranty` and `saveRecall` had **zero callers**; `WarrantyRecallView` was
read-only. An advertised Pro feature that showed "No warranty records yet" forever. Both now have
add-forms. They deliberately collect a subset of their models' fields — `Warranty` declares 20+,
and demanding all of them to record "bumper-to-bumper until March" would be worse than not having
the feature.

## Data trust

### ✅ One corrupt entry blanked the log, stats and export
Every `EntryService` decode site used `try documents.map { try decode }`. One undecodable document
threw out of the whole fetch, emptying the Log tab, the Dashboard recent card, the Stats charts and
**both exports** — the resale dossier being the paid artifact the product exists to produce.
`VehicleService` had been explicitly hardened against this ("one corrupt doc must not blank the
garage"); entries never were, despite being more numerous and carrying a per-type `details` payload
far likelier to drift.

Now tolerant, with a Crashlytics non-fatal per skip. The cursor anchors on the last **document**
consumed, not the last decoded entry, so paging resumes past a bad row instead of looping on it.

## The core loop

### ✅ The Dashboard never reloaded after saving from the Dashboard
The FAB opens the entry form as a sheet on `ContentView`, so on save neither the vehicle id nor the
selected tab changes — and those were the only two reload triggers. A new user's very first entry
appeared to vanish. `LogView` had carried the fix (`.onChange(of: router.activeSheet)`) all along,
which is what marks this as an oversight rather than a decision. Safe on every dismissal because
`loadDashboard` is revision-gated.

`RecentEntryFeed` also rendered a bare heading over nothing when empty, while both sections above
it showed proper empty states.

## Money and measurement

### ✅ The vehicle cap was a dead end, not an offer
Free tier is **1 vehicle**, enforced only server-side. The user filled the entire form, waited for
a round trip, and got a banner whose only button was "Try Again" — for a condition retrying can
never fix. Every other Pro boundary routes to `ProGateView`. This one, the highest-intent
conversion moment in the product, offered nothing.

Now preflighted in `VehicleSwitcher`. A **Pro** user at the 5-vehicle ceiling is deliberately *not*
shown the paywall — no purchase resolves that, so it would be the same dead end with a payment
sheet attached.

### ✅ Three paywall surfaces shared one analytics source
Voice Quick-Add and the oil-analysis PDF import both reported `settings`. With three surfaces in
one bucket, per-surface conversion is not noisy — it is **uncomputable**, and that is worse than
having no data because it looks like data. Nine sites, nine sources now.

### ✅ App Store rating prompt (new)
The app never asked. For a utility app, star count is the largest single lever on impression →
install, so launching with zero ratings suppresses every other acquisition effort. The system caps
prompts at three per user per year and reports nothing back, so the design protects that budget:
weighted value moments (a finished PDF dossier counts 3, a logged entry 1), a threshold no
first-run action can reach, never twice per version, a 120-day cooldown, and full suppression for
the session after any failed save.

## Honesty

### ✅ Mileage-only reminders never fired, and never said so
`hasDueDate` defaults to **false** and "Due mileage" is the first field, so the natural path
produces a mileage-only reminder — and `ReminderNotificationCoordinator.plan` returns nil without a
`dueDate`, scheduling nothing. The form still said "Reminder saved". A user setting "Oil change at
95,000 mi" was silently promised an alert that could never arrive.

A local notification genuinely cannot fire on an odometer reading, so the fix is disclosure rather
than a fake. Predicting the date from logged mileage history is a real follow-up, not done here.

## Deliberately not done

- **Receipt/invoice parsing via Claude** (L). The attachment pipeline stores bytes and never reads
  them; extending the oil-analysis extractor to general receipts is the largest remaining AI
  opportunity, but it is a feature project, not a fix.
- **Offline entry delete** uses Firestore's ack-gated async API, which this codebase documents as
  hanging forever offline — it can orphan a Storage blob. Real, and a bigger change than anything
  in this sweep.
- **Structured outputs for the Claude functions.** Both parse free-text JSON with regex fence
  stripping. Worth doing; needs verification that strict tool-use is available on Haiku 4.5 with
  extended thinking before changing a money-adjacent path.
- **The vehicle's declared starting odometer** is discarded and can be overwritten downward by the
  first entry. Confirmed real; needs a floor and a hint, not a one-liner.
