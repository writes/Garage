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
- **Eligible binary/build:** `________` (record at enrollment). SQL commit: `49ee3b9`
  (`arm_composite.sql` as merged in PR #74; re-pin here if the SQL changes before enrollment).
- **Rollout start:** `________` · **Exposure cutoff:** `________` · **Observation cutoff:**
  `________` (7-day maturity) · **Calendar decision date (UTC):** `________` ·
  **Data-lag allowance:** `________` · **Operator:** `________`.
- **No-decision outcome:** if the decision date arrives without the eligibility bar met, the
  epoch CLOSES with "no decision — control remains default"; re-running requires epoch 3.

## Frozen primary composite (amended from epoch 1)

Components (Beta(1,1) posterior, 20,000 deterministic draws, mean-of-P(best) composite —
mechanics unchanged): activation rate · D7 return rate · **paywall REACH (intent-to-treat:
mature exposed installations viewing the paywall / all mature exposed installations —
replaces the epoch-1 CTR whose denominator was post-treatment; Sol B6)**.

**Purchase-rate weight: DEMOTED to descriptive tiebreaker** — the pre-registered conditional
fired on evidence (2026-08-12): the checked-in OC simulation
(`docs/research/2026-08-12_OC_SIMULATION_design_megatest.md`, merged `0984cf1`) shows that at
purchase baselines 0.02–0.05 a +15% relative lift yields mean P(best) ≈ 0.648 at N=1000
(~20 conversions/arm; the posterior cannot separate), dragging the expected composite by
≈ 0.064 points and making 80% detection unreachable at every tested N (71.8% max at 3000).
The primary composite is therefore the **mean of THREE** per-component P(best) values
(activation · D7 return · ITT paywall reach), per the 2026-07-30 metrics plan's original
tiebreaker designation. Purchase rate is still computed, reported, and used descriptively;
`experiment_report.py` implements exactly this rule (`PRIMARY_COMPOSITE_METRICS`,
selftest-pinned — aligned in the same PR as this correction). Analytic null false-positive
rate of the 3-component rule (Irwin–Hall, P(sum of three uniforms ≥ 2.7) = 0.3³/3!):
**≈ 0.45% per arm (~0.9% either arm)**, independent of N — far under the 5% bar.
*(Correction 2026-08-12, tri-review finding: an earlier fill of this blank misquoted the
4-component tail figures — 1.07%/2.1% — for the 3-component rule.)*

**Interpretation constraint (from the OC simulation):** the composite detects BROAD
multi-component movement only. Even a single-component lift detected with CERTAINTY fires
the 3-component rule at only P(sum of two uniforms ≥ 1.7) = 0.3²/2! = **4.5%** — near the
rule's chance level at every N (the OC counterfactual's activation +20% row plateaus at
3.3–5.2%, matching) — so the epoch-2 result must never be quoted as a verdict on any
individual metric. Registered detectable effect class: all components +15% relative.

## Sample floor & OC simulation (replaces the unjustified 500)

- **REQUIREMENT MET (2026-08-12):** the checked-in simulation (`scripts/analytics/oc_simulation.py`,
  PR #78, merged `0984cf1`; selftest-pinned bit-identical to `experiment_report.summarize`;
  Gemini 3.1 Pro (High) cross-checked) characterizes the frozen rule over 36 plausible baseline
  points × 14 effect scenarios × 5 per-arm Ns × 400 replicates. Null FPR ≈ 0.2% at every N on
  the 4-component rule (Irwin–Hall analytic ≈ 0.107%/arm); the floor is detection-driven, not
  FPR-driven. Note: the frozen rule contains no expected-loss term, so the simulation
  characterizes threshold power/FPR only — the "expected-loss ceiling" wording in the original
  requirement is void by construction.
- **Per-arm floor: 1800 mature installations, with a pre-registered extension rule**
  (Law-1 vote 2026-08-12T18:06:13Z, group `9674af0cd9208c94`, unanimous 3/3): when each arm
  reaches 1800 mature installations, compute the POOLED (arms-combined, never arm-split — a
  nuisance-parameter check, not an outcome peek) observed baseline rates; if pooled activation
  ≤ 0.30 or pooled D7 return ≤ 0.10 (the unfavourable grid corner), the floor extends to 3000.
  Power for the registered effect class ("all +15%", 3-component rule): 84.0% pooled at 1800
  (worst grid point 63.2%); 86.8% worst-point at 3000. The inherited 500 detects the same
  effect 38.1% of the time and is REJECTED.

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
