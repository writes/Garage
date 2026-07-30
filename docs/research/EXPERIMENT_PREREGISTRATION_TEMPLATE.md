# Experiment preregistration template

Use one immutable copy of this template for every production experiment. Fill
the fields before enrollment begins; if a material definition changes, close
the current epoch and create a new preregistration rather than editing history.

## Identity

- **Experiment id:**
- **Owner:**
- **Preregistered at (UTC):**
- **Repository commit / build range:**
- **BigQuery query version / commit:**

## Hypothesis

- **Primary hypothesis:**
- **User population and eligibility:**
- **Why this is worth the exposure:**

## Arms and allocation

| Arm | Product treatment | Planned allocation | Assignment property |
|---|---|---:|---|
| `control` | | | `design_arm` |
| `variant_a` | | | `design_arm` |

- **Experiment epoch:**
- **Exposure event:** `experiment_exposure(experiment, arm, epoch)`
- **Allocation/SRM expectation:** equal unless explicitly changed here.

## Frozen primary composite

- **Primary report:** `scripts/analytics/sql/arm_composite.sql`
- **Frozen cohort and observation window:**
- **Binary components:** activation rate, D7 return rate, paywall CTR, purchase
  rate. For each arm and component, use Beta(1,1) updated with its raw
  numerator/denominator and 20,000 deterministic draws (`random.Random(42)`).
- **Composite:** arithmetic mean of per-component P(best). This is a decision
  summary, not a claim that the component outcomes are independent.
- **Descriptive companion:** core actions per active day; report it but do not
  insert it into a Beta composite without a separately preregistered count model.
- **SRM:** equal-allocation chi-square, investigate `p < 0.001` before
  interpreting a winner.

## Guardrails

| Guardrail | Threshold | Source | Action on breach |
|---|---:|---|---|
| Crash-free rate | | Crashlytics / App Store diagnostics | Pause exposure and investigate |
| Release/CI gate | Must pass | `scripts/ci/*` and release evidence | Stop promotion |
| Other | | | |

## Decision commitment

- **Minimum mature exposure per arm:**
- **Decision date (UTC):**
- **Decision rule:** promote the eligible arm only when its frozen composite
  P(best) is at least `0.90`, or record an explicit operator call at the
  deadline with rationale and evidence.
- **Peeking policy:** weekly review only. Weekly reads are descriptive; do not
  change allocation, endpoints, or the primary composite between scheduled
  reviews without ending the epoch.
- **Kill criteria:**
- **Rollback / disable path:**

## Results record (fill after decision)

- **Actual exposure by arm:**
- **SRM result:**
- **Primary metric table / report artifact:**
- **Guardrail result:**
- **Decision and operator:**
- **Follow-up / next epoch:**

