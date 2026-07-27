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

### ⏸ Crashlytics dSYM upload times out — PROTECTED surface, operator only
The `Upload dSYMs to Crashlytics` build phase timed out on **4 of 5** full gate runs this session:

```
warning: Crashlytics dSYM upload timed out after 90s; symbolicate manually with upload-symbols.
```

The phase itself is correctly designed — Release-only, fail-soft, and bounded by a 90 s watchdog
that exists precisely because the upload tool hangs forever without network/auth (landmine #14).
Failing soft is right: a network blip must not fail an archive.

**But the consequence is a production blind spot.** If this also times out on the real release
archive, dSYMs never reach Crashlytics and every production crash arrives as unsymbolicated hex —
which is the exact moment you most need a readable stack.

Most likely an artifact of this sandboxed build environment having no outbound network for the
upload, rather than a defect. That is a hypothesis, not a verified finding.

**Cannot be fixed by an agent:** the phase lives in `project.yml`, a PROTECTED surface.

Suggested operator actions:
1. Confirm whether the upload succeeds on a real release archive (network present, Firebase
   authed) before relying on Crashlytics.
2. Consider raising the 90 s watchdog for Release archives — a large dSYM upload can legitimately
   exceed it.
3. Add a post-archive dSYM verification step to `scripts/release/testflight_build.sh`, and record
   the manual fallback command in the runbook:
   `upload-symbols -gsp <GoogleService-Info.plist> -p ios <path-to-dSYMs>`

---

## Tech debt: the 250-line file limit is being hit repeatedly

`AppState.swift` and `SubscriptionCommitRelay.swift` now sit at **exactly 250 lines**, and
`AnalyticsService.swift`/`SubscriptionModels.swift` both had to be split this session to stay
under it. Three of those four are coordinator types whose dependencies are `private` (file-scoped),
so they cannot be extended from another file without widening access — which means the only
options left are shaving comments or weakening encapsulation. Neither is a good trade.

The next change to either 250-line file WILL fail the gate. Worth deciding deliberately: either
decompose those coordinators properly (changing the `private` deps to `internal` so extensions can
live in sibling files), or raise the limit for coordinator types. Shaving comments to fit is not a
third option — this session already lost real rationale that way.

---

## Toolchain note

`.tools/bin/xcodegen` is **2.45.3**; the PATH binary is **2.45.4**. The CI regenerate-equality gate
uses the pinned one. Regenerating with the PATH binary can fail the gate spuriously — always use
`.tools/bin/xcodegen generate` before committing a project change.
