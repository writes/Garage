# Pre-registered validation spec — True Cost of Ownership layer on Stats

- **assay:** `docs/research-assay/audit/tier-a/2026-08-02_true-cost-of-ownership-dashboard.md`
  (Tier A, composite 11, 2026-08-02)
- **status:** PRE-REGISTERED — written before build. Amendments after data starts flowing are
  protocol violations unless logged with reasons before unblinding.
- **scope:** v1 core ONLY — whole-garage total spend, 12-month spend trajectory, per-vehicle
  comparison, full-history-correct totals. **Keep-vs-replace / depreciation is OUT of scope**
  (requires a fresh Law-4 intake with a lawful licensed valuation source).

## Hypothesis

Adding a garage-wide TCO layer to the Pro Stats surface — and naming cost-truth in the free
user's Stats gate copy — increases free→Pro conversion from the Stats gate and increases Pro
engagement with Stats, because owners demonstrably want the total-money answer (G2 AUTOsist
reviews request it verbatim; Bankrate 2025: $6,894/yr of surprise costs) and Garage already
holds the data to compute it.

## Metrics

1. **Primary — Stats-gate conversion:** purchases attributed to paywall source
   `subscription(.stats)` ÷ unique free users who viewed the Stats gate, per arm.
   (Consent-gated analytics; verify no pre-`applyProfile` event drops before trusting counts —
   analytics-consent-gate-trap.)
2. **Secondary — Pro Stats engagement:** share of Pro users with ≥2 Stats visits in a rolling
   4-week window, per arm.

## Method

A/B via the Option-A experimentation stack (PR #23; install-scoped sticky assignment, frozen
hash), one experiment, two arms:

- **CONTROL:** current Stats + current gate copy.
- **TCO:** Stats + TCO section (garage-wide total via Firestore server-side `sum()`
  aggregation, 12-month monthly-spend trajectory chart, per-vehicle cost comparison,
  full-history totals reconciled with the 100-entry view) + gate copy naming cost-truth
  (e.g., "See what every car really costs — total, per mile, per month, across your whole
  garage.").

Build guards: pure calculator functions unit-tested first (extend the `nonisolated`
`OwnershipCostCalculator` pattern); check `FirestoreIndexes.json` for any new composite index
before shipping (firestore-index-blind-spot); the on-screen garage total and per-vehicle total
must be arithmetically consistent or the feature ships a trust bug.

## Death condition (kills the idea)

After **8 weeks** of live A/B **or ≥400 unique free gate-viewers per arm** (whichever first):

- Primary lift **< 10% relative** (or negative) on Stats-gate conversion, **AND**
- no statistically credible lift on Pro Stats engagement,

⇒ **TCO is frozen as-shipped**: no further ownership-economics investment, and the
keep-vs-replace/depreciation extension is dead without a fresh intake carrying licensed-data
evidence. Record the verdict as a status note on the assay report — never a fresh assay.

**Underpowered fallback:** if traffic cannot reach the sample floor by 12 weeks post-launch,
decide on the engagement metric alone, record the verdict as UNDERPOWERED, and do not use the
shortfall to keep the idea alive indefinitely.

## Budget

- Build: ≤1 sprint (calculator + one Stats section + aggregation wiring + experiment arm +
  tests). No new infra or external-data spend. Implementation routes per MODEL ROUTING v3;
  scheduling/adoption requires the Law-1 tri-vote — this spec authorizes the validation, not
  the roadmap slot.
