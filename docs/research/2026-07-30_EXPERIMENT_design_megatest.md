# Experiment preregistration — design_megatest

This is a review-phase-only preregistration. It authorizes measurement and
evaluation, not autonomous release, rollout, or allocation changes.

## Identity

- **Experiment id:** `design_megatest`
- **Owner:** Garage product/release operator
- **Preregistered at (UTC):** 2026-07-30
- **Repository commit / build range:** record at review-phase enrollment
- **BigQuery query version / commit:** record the commit containing
  `scripts/analytics/sql/arm_composite.sql` before exposure begins

## Hypothesis

- **Primary hypothesis:** a carefully reviewed alternative Garage design can
  improve the frozen composite without reducing stability or passing a release
  gate only on appearance.
- **User population and eligibility:** consented Analytics users enrolled by
  the implementation's deterministic assignment; exclude users without a valid
  `experiment_exposure(design_megatest, arm, epoch)` record from outcome rates.
- **Why this is worth the exposure:** design decisions otherwise risk being
  driven by static preference instead of activation, retained usage, monetization,
  and stability evidence.

## Arms and allocation

| Arm | Product treatment | Planned allocation | Assignment property |
|---|---|---:|---|
| `control` | Current reviewed Garage design | 50% | `design_arm=control` |
| `variant_a` | Review-approved alternative design | 50% | `design_arm=variant_a` |

- **Experiment epoch:** `1`. Add future variants only through an epoch bump;
  do not mutate the enrolled arm set in place.
- **Exposure event:** `experiment_exposure(experiment="design_megatest", arm, epoch)`.
- **Allocation/SRM expectation:** equal allocation. `p < 0.001` requires an
  instrumentation/assignment investigation before any outcome claim.

## Frozen primary composite

- **Primary report:** `scripts/analytics/sql/arm_composite.sql`, summarized by
  `scripts/analytics/experiment_report.py`.
- **Frozen cohort and observation window:** first valid exposure in the selected
  date range; a seven-day maturity window. Activation is the existing three-part
  sequence within seven days of Firebase `first_open`; D7 return is a
  `session_start` on day seven after exposure.
- **Binary components:** activation rate, D7 return rate, paywall CTR, purchase
  rate. Beta(1,1) posterior per arm/component; 20,000 deterministic
  `random.Random(42)` draws.
- **Composite:** mean of per-component P(best), exactly as emitted by
  `experiment_report.py`. Core actions per active day remains a descriptive
  companion metric because its count numerator can exceed active user-days.

## Guardrails

| Guardrail | Threshold | Source | Action on breach |
|---|---:|---|---|
| Crash-free rate | Arm below 99.5% | Crashlytics, with adequate cohort context | Kill the arm; investigate before re-enrollment |
| Release/CI gate | Any required gate failure | `scripts/ci/*` and release evidence | Kill the arm; do not promote |

## Decision commitment

- **Minimum mature exposure per arm:** 500 users.
- **Decision date (UTC):** production release review; no automatic release date
  is implied by this document.
- **Decision rule:** an arm is eligible only with frozen composite P(best)
  `>= 0.90`, no unresolved SRM warning, and no guardrail breach; otherwise the
  operator makes the recorded deadline call.
- **Peeking policy:** weekly-review-only. The team may inspect the fixed report
  once per week, but may not alter allocation, outcomes, eligibility, or the
  primary composite while the epoch is open.
- **Kill criteria:** an arm crash-free rate below 99.5% or any release/CI gate
  failure. Kill means stop further review-phase exposure, preserve the evidence,
  and fix/re-preregister rather than relabeling the same epoch.
- **Rollback / disable path:** operator-controlled experiment assignment or
  release configuration; no application release is authorized by this document.

## Results record (fill after decision)

- **Actual exposure by arm:** pending review-phase enrollment.
- **SRM result:** pending.
- **Primary metric table / report artifact:** pending.
- **Guardrail result:** pending.
- **Decision and operator:** pending production release review.
- **Follow-up / next epoch:** add additional designs only via a new epoch.
