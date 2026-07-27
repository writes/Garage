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

## P0 — Measurement (you cannot optimise what you do not record)

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

### 📋 Onboarding step events
Drop-off between install and first vehicle is invisible. Blocked on there being an onboarding
flow to instrument (below).

---

## P1 — Activation (Day 0 decides the business)

**Evidence:** 90% of trial starts and 44.5% of all purchases occur on **Day 0**. 84% of
short-trial cancellations happen by Day 1. More than 90% of users churn within 30 days.

### 📋 There is no onboarding flow — at all
Zero references to onboarding, welcome, or first-run anywhere in 193 Swift files. A new user
signs in and lands in an empty app with no guidance toward the one action that predicts
retention: **adding a vehicle and logging the first record**.

This is the single largest activation gap in the product. Everything else in this document is an
optimisation; this is a missing feature, and it sits precisely where the evidence says the
business is won or lost.

**Done means:** a short first-run flow that ends with a vehicle created and one record logged,
instrumented at each step so drop-off becomes visible.

---

## P2 — Conversion (money-path; operator-gated per Law 1)

### ⏸ The paywall buries its own offer
Current render order in `SubscriptionView`:

1. Title + feature sentence
2. **`PrimaryButton("Refresh Plans")`** ← the most visually prominent control on the paywall
3. `Restore Purchases`
4. Policy links
5. Disclosure copy
6. Activity indicator
7. **The actual plans** — last, in whatever order RevenueCat returned them

The single strongest element on a purchase screen is a maintenance affordance, and the offer is
below the fold. `Refresh Plans` is a legitimate retry for a failed load (the `.task` already loads
offerings automatically), but it should not outrank the purchase CTA.

**Evidence for the fix:** annual plans generate ~2× the revenue per install of monthly
(D60 $0.46 vs $0.24), yet the utility/productivity segment under-uses annual-default framing.
There is currently no annual-forward ordering, no savings callout, and no trial emphasis.

**Why this is ⏸ and not 🔨:** this is money-path UI. Under the repo's trust boundary it should be
planned, implemented with tests, adversarially reviewed, and operator-gated — not changed
unilaterally mid-loop.

### ⏸ Trial length 7 → 14 days
Trial-to-paid by length: ≤4 days 25.5% · **5–9 days 37.4%** (current) · 17–32 days 42.5%.
Longer trials convert better but cancel more, so the net is genuinely uncertain — which makes it
a good A/B, not a unilateral change. Configured in App Store Connect, not in code.

### ⏸ Paywall placement
Onboarding paywalls with a trial convert at 1.35% vs 0.89% post-onboarding — a ~52% relative
lift (Adapty, vendor-published). Depends on the onboarding flow existing first.

---

## P3 — Quality

### ⏸ Light-mode WCAG-AA failures
Pre-existing, and fixing them visibly changes brand colour, so it is an operator decision.
Measured replacements, hue and saturation preserved:

| Token | Now | AA-passing | Contrast |
|---|---|---|---|
| `Accent` | `#D97D4A` | `#A95324` | 2.66 → 4.50:1 |
| `Warning` | `#E78A2A` | `#9F5A12` | 2.34 → 4.51:1 |
| `Success` | `#248861` | `#207957` | 3.80 → 4.54:1 |
| `BrandSecondary` | `#8A96A1` | `#616D79` | 2.69 → 4.51:1 |

Dark mode already clears AA on every pairing (≥5.38:1).

### 📋 ASO fields
Name ≤30 chars, subtitle ≤30, keywords ≤100 with no cross-field duplication. **Blocked on the
name.**

### 📋 iOS 18 dark/tinted app-icon variants
Unverified against Apple's spec. Note the trap: testing an alternate icon requires the variants
to already ship inside the published binary, so this is gated on a release cycle.

---

## Toolchain note

`.tools/bin/xcodegen` is **2.45.3**; the PATH binary is **2.45.4**. The CI regenerate-equality gate
uses the pinned one. Regenerating with the PATH binary can fail the gate spuriously — always use
`.tools/bin/xcodegen generate` before committing a project change.
