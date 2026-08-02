# Assay: True Cost of Ownership dashboard — Tier A

- **assay_id:** `2026-08-02_true-cost-of-ownership-dashboard`
- **date:** 2026-08-02 · **source:** operator-paste (2026-08-02 feature-innovation research
  sweep) · **source_type:** operator-idea · **fetch_status:** paste-only (G2/Bankrate evidence
  supplied verbatim by the sweep; not independently fetched)
- **tier: A** · **retention:** FULL · **composite:** 11 · **doctrine_fit:** pass
- **validation spec (pre-registered):** `docs/research/2026-08-02_true-cost-of-ownership-dashboard.md`

## Claim

A True-Cost-of-Ownership layer on Stats (whole-garage total spend, 12-month spend trajectory,
per-vehicle comparison, full-history-correct totals) improves Pro conversion and engagement via
turning already-captured entry costs into the ownership-economics answer competitor users ask
for by name.

## Stage 0 — graveyard search

Keywords: cost, spend, ownership, depreciat, tco, money, dashboard, stats, insight, valuation.
No prior assay. Nearest neighbors, all distinct: `2026-07-24_garage-continuity-full-redesign`
(Tier B, buyer-facing dossier UX), `2026-07-21_generative-vehicle-identity-monetization`
(Tier B, cosmetics/certificate), `2026-08-02_ask-garage-history-aware-ai-chat` (Tier B, chat
surface — could *answer* cost questions but is a different mechanism). Genuinely new ground.

## The load-bearing audit: what Stats already ships vs. what is new

**Already shipped** (`Garage/Features/Stats/`, Pro-gated, per-vehicle, capped at the most
recent 100 entries):

- `OwnershipCostCalculator.swift` + `Views/OwnershipCostCard.swift` — **total spend,
  cost-per-mile, cost-per-month, per vehicle**. The card is literally titled "Cost of
  ownership" and leads the screen.
- `Views/CostBreakdownChart.swift` — spend by entry category.
- `Views/MPGTrendChart.swift`, `Views/WearHistoryChart.swift`.

So the intake framing ("this is the ownership-economics framing rather than activity stats")
is **half wrong**: the ownership-economics framing already began. The AUTOsist reviewer wish —
"total spent per vehicle, **and as a total**" — is already satisfied on the per-vehicle half.

**Genuinely new (the assayed v1 core):**

1. **Whole-garage rollup** — spend across all vehicles. Stats is strictly per-vehicle today
   (`VehicleSwitcher`); the "as a total" half of the stated wish is unserved.
2. **12-month spend trajectory** — there is no time dimension on cost today (MPG has a trend;
   cost has only a category breakdown and lifetime aggregates).
3. **Full-history correctness** — `StatsViewModel` fetches `limit: 100`; the shipped "Total"
   is silently a most-recent-100 total for long histories (the caption admits it). A true
   running total needs Firestore server-side `sum()` aggregation (cheap, no doc reads).
4. **Per-vehicle comparison** — which car is the money pit; only meaningful once (1) exists.

**Explicitly EXCLUDED from this Tier-A verdict: keep-vs-replace / depreciation.** A credible
signal needs market valuation data (KBB/Edmunds/Black Book — licensed, expensive, and the
profit-first blueprint's Q4 precedent already established scraping is ToS-prohibited). A crude
in-app depreciation curve produces exactly the "confident-looking lie" this codebase's own
design comments forbid (`OwnershipCostCalculator` returns nil rather than fake zeros).
Reopening that pillar requires a **fresh intake** carrying a lawful, licensed valuation source
with sustainable per-user economics.

**vs. Wave-3 dossier (iOS-7):** complementary, not redundant. The dossier is buyer-facing
evidence; TCO is owner-facing economics. Cost-per-mile even feeds the dossier ("the number a
resale buyer respects" — the card's own doc comment). No additivity collision.

## Doctrine

Pass on every gate: native SwiftUI over existing Firestore data (Swift Charts already in use),
no backend swap, no client secrets, no App Store/privacy exposure, fits the governing
profit-first ladder (free = log, Pro = insight — Stats is already the Pro insight surface).

## Scores

| axis | score | justification |
|---|---|---|
| mechanism | 2 | Real-user-value with a named causal chain: data already captured → arithmetic derivation → the exact number competitor users request verbatim. Held at 2, not 3: Stats is already Pro-gated (the conversion mechanism strengthens an existing gate rather than creating one), and the headline keep-vs-replace pillar has no sound mechanism without licensed data. |
| evidence | 2 | Two independent demand sources: G2 AUTOsist review corpus asking for per-vehicle + total spend by name; Bankrate 2025 Hidden Costs study ($6,894/yr surprise, +3.1% YoY) quantifying the emotional charge. Case-study-grade *demand* evidence, not efficacy evidence for this app; paste-only, unfetched. |
| additivity | 2 | Real but middling: per-vehicle totals/per-mile/per-month ALREADY shipped; new value = garage-wide rollup + trajectory + full-history correctness + comparison, on an existing surface. Not a new capability class. |
| capacity | 2 | Firestore server-side `sum()` aggregation scales to large histories at trivial cost; N-vehicle rollup = N small aggregations. Check `FirestoreIndexes.json` for equality+range composite indexes (firestore-index-blind-spot memory). |
| cost_survival | 2 | Zero new infra/API spend in v1; strengthens the Pro value prop. (Licensed valuation data would sink this axis — one reason depreciation is excluded.) |
| testability | 2 | Pure calculator extension of the existing `nonisolated` `OwnershipCostCalculator` pattern; the Option-A experimentation stack (PR #23) + already-instrumented `subscription(.stats)` paywall source give a cheap A/B with a clear death condition. |
| implementation_cost | −1 | A sprint for the v1 core: calculator functions, one Stats section, aggregation wiring, experiment arm, tests. Existing pattern for every piece. (With depreciation it would be −2/−3 — excluded.) |

**Composite = 11.** Tier-A gates: composite ≥ 11 ✓, mechanism ≥ 2 ✓, testability ≥ 1 ✓,
doctrine pass ✓.

## Risks

- **Biggest:** insight wallpaper on an already-sold gate — Stats already shows per-vehicle
  cost of ownership behind the Pro gate; the added layer may move no money metric (gate
  conversion, retention). The pre-registered A/B exists precisely to kill it cheaply if so.
- Scope-creep pull toward keep-vs-replace/depreciation (excluded; fresh intake required).
- Full-history `sum()` must reconcile with the 100-entry in-memory view or the screen shows
  two different "totals" — a trust bug on a trust product.
- Analytics consent gate: conversion events fired pre-`applyProfile` are silently dropped
  (analytics-consent-gate-trap memory) — validate instrumentation before trusting arm data.
- Multi-currency/partial-cost histories: nil-cost entries must stay excluded from totals but
  included in mileage denominators (the calculator already gets this right — preserve it).

## Disposition

Tier A → validation spec pre-registered at
`docs/research/2026-08-02_true-cost-of-ownership-dashboard.md` (hypothesis, metrics, death
condition, method, budget). **Intake only** — scheduling/adoption still goes through the Law-1
tri-vote and the normal wave planning; this assay authorizes the validation, not the roadmap.

## Status notes

- (none yet — next legitimate write: validation verdict per the spec's death condition.)
