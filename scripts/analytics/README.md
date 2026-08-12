# Garage analytics and experimentation tooling

This directory contains read-only GoogleSQL reports over the Firebase Analytics
BigQuery export and a local experiment-summary program. The SQL uses Standard
SQL (GoogleSQL), never Legacy SQL.

## Before running a query

1. In the Firebase console, link the Analytics property to BigQuery and enable
   the daily export. Firebase writes daily event tables named
   `analytics_<property>.events_YYYYMMDD` (and may also write an intraday table).
   These reports intentionally read the stable daily `events_*` tables only.
2. Replace `YOUR_PROJECT` and `analytics_YOUR_PROPERTY` in each SQL file with
   the BigQuery project and dataset shown by that link.
3. Set the `DECLARE` defaults at the top of the report (or copy the query to
   the BigQuery editor and edit them there). Dates are inclusive `YYYYMMDD`.
4. Confirm that the user has consented to Analytics. A missing event can be a
   valid privacy outcome, not proof that a feature was unused.

The queries use `COALESCE(user_id, user_pseudo_id)` as `analysis_user_id`.
That is a practical reporting key, not an identity merge: anonymous activity
that predates a Firebase `user_id` can remain on a different pseudo-ID.

## Run the SQL

Use the BigQuery editor, or run a local query after replacing the table
placeholder:

```sh
bq query --use_legacy_sql=false < scripts/analytics/sql/activation_funnel.sql
bq query --use_legacy_sql=false < scripts/analytics/sql/conversion_funnel.sql
bq query --use_legacy_sql=false < scripts/analytics/sql/feature_matrix.sql
bq query --use_legacy_sql=false < scripts/analytics/sql/arm_composite.sql
bq query --use_legacy_sql=false < scripts/analytics/sql/notif_funnel.sql
```

`arm_composite.sql` is the input contract for `experiment_report.py`. It emits
one row per experiment arm with raw numerator and denominator columns alongside
the displayed rates. Keep the raw columns when exporting CSV; rates alone are
not enough to recreate the posterior.

## New instrumentation expected by this branch

The reports derive historical behavior only from existing frozen Garage event
names. The following events/properties are new instrumentation required for
the experiment tooling and will not appear in pre-instrumentation data:

| Surface | Required event/property | Required parameters |
|---|---|---|
| Design assignment | user properties `design_arm`, `experiment_epoch` | string arm and epoch |
| Experiment enrollment | `experiment_exposure` | `experiment`, `arm`, `epoch` |
| Upsell funnel | `upsell_exposure` | `source` |
| Feature matrix | `feature_used` | `feature` in `gallery`, `warranty`, `theming` — `wear` and `dossier` were considered and EXCLUDED from the closed enum (already covered by `entry_saved`/`export_pdf` + `screen_viewed`; rows for them can never appear) |
| Notification funnel | `notif_scheduled`, `notif_opened`, `notif_task_completed` | `category`; user property `notif_holdout` |

Do not retrofit historical data or rename the existing event contract. Query
results before an event ships should show zero (or no rows) for that surface.

## Experiment report

The report program has no third-party dependencies and makes no remote writes.
It reads either a saved CSV or executes `bq query` with an explicit timeout.

```sh
# Validate the statistics implementation without BigQuery credentials.
python3 scripts/analytics/experiment_report.py --selftest

# Analyze an exported arm_composite.csv and also write a machine-readable file.
python3 scripts/analytics/experiment_report.py \
  --csv reports/design_megatest_arm_composite.csv \
  --json reports/design_megatest_report.json

# Execute the report SQL through bq; edit its table placeholder first.
python3 scripts/analytics/experiment_report.py \
  --bq --sql scripts/analytics/sql/arm_composite.sql \
  --timeout-seconds 300 --json reports/design_megatest_report.json
```

For the four binary decision metrics (`activation_rate`, `d7_return_rate`,
`paywall_ctr`, `purchase_rate`), each arm uses a Beta(1,1) prior updated by the
raw numerator/denominator. The program takes 20,000 deterministic draws using
`random.Random(42)`, reports probability of being best and posterior expected
loss versus the per-draw best arm, then defines the composite as the arithmetic
mean of those four P(best) values.

`core_actions_per_active_day` is intentionally descriptive: its numerator is a
count of actions and can exceed its active-day denominator, so treating it as a
Binomial/Beta rate would be mathematically invalid. It is reported with its raw
ratio but excluded from the Bayesian composite until a pre-registered count
model is added. This distinction is deliberate rather than silently applying
invalid probability math.

Sample-ratio mismatch (SRM) compares `n_exposed` across arms against equal
allocation. The p-value is the chi-square survival probability calculated with
a pure-Python regularized incomplete gamma implementation (series expansion or
continued fraction, selected by the usual numerical-stability boundary). The
report warns when `p < 0.001`; investigate assignment/exposure instrumentation
before interpreting outcomes.

## Operating-characteristic simulation

`oc_simulation.py` answers the question `experiment_report.py` cannot: **how much sample
does the frozen decision rule actually need, and what does it do when there is nothing
to find?** It replays the exact rule `experiment_report.py` implements — Beta(1, 1)
posteriors, 20,000 `random.Random(42)` draws, per-component P(best), composite = the
mean of the four, fire at `>= 0.90` — against simulated two-arm experiments whose truth
is known, over a grid of plausible baseline rates, effect scenarios and per-arm sample
sizes. For each cell it reports how often the rule fires for the variant, how often it
falsely flips to control, how often it reaches no decision, and the expected composite.

It shares no code path with the reporting program by accident: the `--selftest` fixture
asserts that its per-component scorer is bit-identical to `experiment_report.summarize`,
so a change to the scoring machinery fails the simulation rather than silently
invalidating a sample floor derived from it.

```sh
# Pin the frozen rule: scorer equivalence, composite arithmetic, decision boundaries.
python3 scripts/analytics/oc_simulation.py --selftest

# Smoke/CI run: 100 replicates per cell (~1.5 minutes on 16 cores).
python3 scripts/analytics/oc_simulation.py --fast --no-write

# Full grid: 400 replicates per cell. Writes the generated research document.
python3 scripts/analytics/oc_simulation.py
```

The full run regenerates `docs/research/2026-08-12_OC_SIMULATION_design_megatest.md`,
which is a GENERATED file — change the simulation and rerun it, never hand-edit the
document. Both the document and stdout carry the measured wall clock.

**The epoch-2 sample-floor blank MUST be filled from this output.** The pre-registration
addendum `docs/research/2026-08-11_EXPERIMENT_design_megatest_epoch2_ADDENDUM.md`
inherited a 500-per-arm floor and the `P(best) >= 0.90` rule from epoch 1 without
justifying either (Sol finding B13), and it requires this simulation to be checked in
before enrollment begins. Two of its blanks are filled from the SUMMARY section: the
**per-arm mature-installation floor**, and the **purchase-rate weight** clause, which
retains purchase at equal weight only if the operating characteristics support it and
otherwise demotes it to a descriptive tiebreaker.

The baseline rates are pre-launch guesses — Garage has never measured a real cohort on
these metrics. Rerun the simulation with observed rates as soon as epoch 2 produces a
mature cohort, and treat any floor quoted before that as provisional.

### Metric definitions and attribution limits

- Activation is all of `first_vehicle_added`, `first_entry_added`, and the
  earliest of `voice_capture_started`, `oil_analysis_requested`, or
  `receipt_capture_started` within seven days of automatic Firebase `first_open`.
- D7 return is a `session_start` on calendar day seven after experiment exposure.
- Core actions are `entry_saved`, `receipt_entry_confirmed`, and
  `voice_entry_confirmed` per `session_start` active user-day in the first seven
  calendar days after exposure.
- Paywall CTR is users with `paywall_viewed` after an `upsell_exposure`, divided
  by users with an `upsell_exposure`, in the mature seven-day window.
- Purchase rate is users with either `purchase_completed` or `trial_started`
  after experiment exposure, divided by mature exposed users. Client purchase
  events are not RevenueCat revenue truth.
- Source-level purchases cannot be uniquely attributed when a user sees several
  sources: existing purchase events deliberately have no `source` parameter.
  `conversion_funnel.sql` therefore uses a source-specific exposure/view and
  reports later purchase behavior as an attributed observational funnel.
- `paywall_dismissed` is an exit diagnostic. It is measured after a matching
  paywall view in parallel with purchase attempts, not incorrectly made a
  prerequisite to an attempt.
- The notification funnel is user/category chronological attribution. Without a
  notification instance ID in the requested schema, it cannot prove that an
  open/completion belongs to one specific scheduled notification.

