# Superseding pre-registration addendum — design_megatest EPOCH 2 (DRAFT until enrollment)

Supersedes epoch 1 of `2026-07-30_EXPERIMENT_design_megatest.md` for production use, per the
2026-08-11 master plan §6.1 (Sol B2/B13). Epoch 1 disposition: **killed server-side
2026-08-11T19:34Z by the operator** (`app_config/experiments`), never publicly enrolled; any
review-phase/leaked exposure rows are quarantined by epoch in analysis. This addendum becomes
IMMUTABLE at epoch-2 enrollment; blanks below MUST be filled before exposure begins.

## Arms (epoch 2)

| Arm | Treatment | Allocation |
|---|---|---|
| `control` | Shipped Garage design | 50% |
| `variant_a` | FULL Underhood per the frozen arm manifest (produced by the Q1 vote session; trust-wedge functionality EXCLUDED) | 50% |

Allocation is clamped in code both client- and server-side (P0.2): the open epoch accepts
exactly these weights or a kill — nothing else.

## Population & operating phase (supersedes "review-phase-only")

- **Cohort:** production installations from the first App Store build carrying the epoch-2
  registry, enrolled via the fail-closed gate (control render + no exposure until the
  effective registry resolves; exposure recorded atomically with treatment).
- **Unit:** the INSTALLATION (install-scoped UUID assignment; `user_pseudo_id` analysis key —
  P0.3, ratified 2026-08-12 UNANIMOUS, ledger group `ea4de5ac0c6fb564` @ the 2026-08-12
  vote-session timestamps — cite timestamp+group).
- **Eligible binary/build:** `________` (record at enrollment). SQL commit: `________`.
- **Rollout start:** `________` · **Exposure cutoff:** `________` · **Observation cutoff:**
  `________` (7-day maturity) · **Calendar decision date (UTC):** `________` ·
  **Data-lag allowance:** `________` · **Operator:** `________`.
- **No-decision outcome:** if the decision date arrives without the eligibility bar met, the
  epoch CLOSES with "no decision — control remains default"; re-running requires epoch 3.

## Frozen primary composite (amended from epoch 1)

Components (Beta(1,1) posterior, 20,000 deterministic draws, mean-of-P(best) composite —
mechanics unchanged): activation rate · D7 return rate · **paywall REACH (intent-to-treat:
mature exposed installations viewing the paywall / all mature exposed installations —
replaces the epoch-1 CTR whose denominator was post-treatment; Sol B6)** · purchase rate.

**Purchase-rate weight:** retained at equal weight ONLY if the operating-characteristic
simulation (below) supports it at the chosen sample floor; otherwise demoted to descriptive
tiebreaker per the 2026-07-30 metrics plan.

## Sample floor & OC simulation (replaces the unjustified 500)

- **REQUIRED before enrollment:** a checked-in simulation (`scripts/analytics/oc_simulation.py`,
  to be written in Phase 3) over plausible baseline rates establishing: minimum worthwhile
  lift per component, expected-loss ceiling, per-arm mature-installation floor, and the
  power/false-positive characteristics of the P(best) ≥ 0.90 rule at that floor.
- Per-arm floor: `________ installations` (from the simulation; 500 is the inherited
  placeholder, not the commitment).

## Guardrails

- Crash-free rate per ARM ≥ 99.5% via the Crashlytics arm/epoch custom keys (P0.5), read
  DAILY (separate from weekly outcome peeks); kill on breach.
- Release/CI gate failure → kill.
- SRM (equal-allocation chi-square) p < 0.001 → investigation before any outcome claim.

## Peeking & exploratory

Weekly-review-only for outcomes. The Underhood-unique interaction map (frozen at Phase 3;
canonical IDs via the event-name registry ritual) is EXPLORATORY: never feeds allocation or
the winner decision.

## App Review disclosure (Phase 3.5 prerequisite)

The epoch-2 binary's Review Notes disclose both designs and the server kill/allocation
controls; a documented deterministic reviewer route (demo mode) shows both worlds without
contaminating enrollment. Enrollment begins only after THAT binary is approved and on sale.
