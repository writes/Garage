# Pre-registered validation — Warranty-Proof Pack (Tier A, assay 2026-08-02_warranty-proof-pack)

- **Assay:** `docs/research-assay/audit/tier-a/2026-08-02_warranty-proof-pack.md`
- **Status:** ARMED (pre-registered before any build beyond the fake-door)
- **Owner gate:** scheduling the real build + SKU choice requires a Law-1 tri-vote; this spec
  authorizes only the experiment below.

## Hypothesis

Warranty-protection positioning ("claim-ready proof of maintenance — protect your active
warranty") is a materially stronger conversion lever for Garage's paid tier than the existing
resale-oriented export positioning, because claim denial is an urgent, dollar-quantified,
during-ownership pain rather than an end-of-ownership one.

## Method (cheapest honest test — no engine work)

Two simultaneous probes, ~1 week of wiring on the existing Option-A A/B stack (PR #23,
install-scoped sticky assignment) + a fake door:

1. **Positioning A/B (paywall):** Arm R = current resale/export pitch; Arm W = warranty-proof
   pitch. Same price, same feature set behind the wall. Metric: paywall-view → trial/purchase
   conversion per arm.
2. **Fake-door preset:** add a "Warranty-Proof Pack" preset tile on the export screen (renders
   the existing sections via a preset; free users see it Pro-locked). Metrics: tile tap-through
   as a share of export-screen visitors; Pro conversions attributed to the tile.

Implementation notes (binding):
- Consent-gate trap: any event fired before `applyProfile` is silently dropped — wire the
  experiment exposure/conversion events AFTER profile application (memory
  `analytics-consent-gate-trap`).
- Copy in both probes uses "organized for warranty claims" language only — no acceptance
  guarantees (liability/App Review constraint recorded in the assay).

## Sample / time budget

Run until **≥400 paywall exposures per arm** or **30 days**, whichever comes first. No
peeking-based early stop except a guardrail halt (crash or review-risk complaint).

## Death condition (pre-registered — the result that kills it)

At budget end, **Arm W conversion ≤ Arm R conversion (no lift)** AND **fake-door tap-through
< 3% of export-screen visitors** → the dedicated Warranty-Proof Pack is DEAD as a standalone
feature/SKU. Disposition on death: fold nothing beyond a trivial section-preset into the
Wave-3 iOS-7 dossier; append a status note to the assay report (never a fresh assay).

Partial outcomes:
- W lift but weak tap-through → positioning wins, preset doesn't: adopt the *language* on the
  existing export/paywall; no dedicated pack.
- Tap-through ≥3% but no W lift → intent exists inside the installed base but doesn't sell the
  wall: candidate Pro-bundled retention feature, NOT a standalone SKU; tri-vote before build.
- Both pass → tri-vote the build + SKU form (Pro-bundled vs one-time), sprint scope per assay
  (preset, contract cover page, user-configured interval-compliance only, disclaimer copy).
