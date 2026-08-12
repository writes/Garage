#!/usr/bin/env python3
"""Operating-characteristic simulation for the frozen design_megatest decision rule.

The epoch-2 pre-registration addendum inherited a 500-per-arm floor and a
``P(best) >= 0.90`` firing rule from epoch 1 without justifying either (Sol finding
B13). This program supplies that justification, or the corrected floor, by replaying
the EXACT scoring rule ``experiment_report.py`` implements against simulated
experiments whose truth is known.

The scored rule is not re-derived here. For every component metric an arm's posterior
is Beta(1, 1) updated by its raw numerator/denominator, ``random.Random(42)`` takes
20,000 draws, P(best) is the tie-split share of draws an arm leads, and the composite
is the arithmetic mean of the four component P(best) values. A decision fires for an
arm when its composite reaches 0.90.

Two properties of the frozen rule make an otherwise intractable grid cheap enough to
run, and both are exact rather than approximate:

1. ``summarize`` re-seeds ``random.Random(42)`` for EVERY component, so a component's
   P(best) is a pure function of that component's own (numerator, denominator) pair
   per arm. Components can therefore be simulated independently and averaged
   afterwards; the composite is bit-identical to scoring whole experiments.
2. With two arms the tie-split wins sum exactly to the draw count, so one scored win count
   per component per replicate recovers both arms' P(best) — each by its own division,
   the way ``summarize`` does it. A false flip is the control composite reaching 0.90.

``selftest`` pins both properties against ``experiment_report.summarize`` itself, so a
drift in the scoring machinery fails here rather than silently invalidating the floor.

Denominators. ``sql/arm_composite.sql`` emits ``COUNTIF(is_mature)`` as the denominator
of all four components — activation, D7 return, paywall reach and purchase are all
intent-to-treat over the same mature exposed installations. The simulation therefore
uses one per-arm N as the denominator of every component, which is what "per-arm
sample floor" means in the addendum.

Baseline sourcing. The grids below are PRE-LAUNCH GUESSES, deliberately wide, chosen
so the answer is a sensitivity statement rather than a point claim:

* activation 0.30 / 0.45 / 0.60 — activation is the conjunction of first vehicle, first
  entry and one AI-feature start within seven days of first open; published onboarding
  completion for utility apps spans roughly a third to two thirds of installs, and no
  Garage cohort has ever been measured.
* D7 return 0.10 / 0.20 / 0.30 — mobile day-7 retention for non-social utility apps
  clusters in the low tens of percent; 0.30 is the optimistic edge.
* paywall reach (ITT) 0.15 / 0.30 — the share of mature installs that see a paywall at
  all is driven by upsell surfacing, which the design arms change directly.
* purchase 0.02 / 0.05 — trial-or-purchase per mature install; low single digits is the
  ordinary range for a paid utility subscription.

Rerun this program with observed rates once epoch 2 has real exposure data; the floor
it recommends is only as good as the grid above.

Runtime. The full grid is 250 component cells x 400 replicates = 100,000 scored
component evaluations at roughly 36 ms each, parallelised across the machine's CPUs;
measured wall clock is reported at the end of every run and recorded in the generated
document. ``--fast`` cuts replicates to 100 for CI and smoke runs.
"""

import argparse
import multiprocessing
import os
from pathlib import Path
import random
import sys
import time


DRAW_COUNT = 20_000
RNG_SEED = 42
DECISION_THRESHOLD = 0.90
REPLICATE_SEED = 4242
FULL_REPLICATES = 400
FAST_REPLICATES = 100

COMPONENTS = ("activation_rate", "d7_return_rate", "paywall_reach", "purchase_rate")
COMPONENT_LABELS = {
    "activation_rate": "activation",
    "d7_return_rate": "d7_return",
    "paywall_reach": "paywall_reach",
    "purchase_rate": "purchase",
}
BASELINE_GRIDS = {
    "activation_rate": (0.30, 0.45, 0.60),
    "d7_return_rate": (0.10, 0.20, 0.30),
    "paywall_reach": (0.15, 0.30),
    "purchase_rate": (0.02, 0.05),
}
SAMPLE_SIZES = (250, 500, 1000, 1800, 3000)
SINGLE_COMPONENT_LIFTS = (0.10, 0.20, 0.50)
ALL_COMPONENT_LIFT = 0.15


def build_scenarios():
    """Return ordered (name, {component: relative lift}) effect scenarios."""
    scenarios = [("null", {component: 0.0 for component in COMPONENTS})]
    for component in COMPONENTS:
        for lift in SINGLE_COMPONENT_LIFTS:
            lifts = {other: 0.0 for other in COMPONENTS}
            lifts[component] = lift
            scenarios.append((f"{COMPONENT_LABELS[component]} +{int(round(lift * 100))}%", lifts))
    scenarios.append((
        f"all +{int(round(ALL_COMPONENT_LIFT * 100))}%",
        {component: ALL_COMPONENT_LIFT for component in COMPONENTS},
    ))
    return scenarios


SCENARIOS = build_scenarios()


def build_baseline_points():
    """Return every combination of the per-component baseline grids."""
    points = [{}]
    for component in COMPONENTS:
        points = [
            dict(point, **{component: baseline})
            for point in points
            for baseline in BASELINE_GRIDS[component]
        ]
    return points


BASELINE_POINTS = build_baseline_points()


def variant_rate(baseline, lift):
    """Apply a relative lift and clamp into the open unit interval."""
    if lift == 0.0:
        return baseline
    return min(1.0, baseline * (1.0 + lift))


def variant_wins(control_numerator, variant_numerator, denominator,
                 draws=DRAW_COUNT, seed=RNG_SEED):
    """Return the variant's tie-split win count, the quantity summarize divides by draws.

    The generation order matters: the control arm consumes the first ``draws``
    betavariates from ``random.Random(seed)`` and the variant consumes the next
    ``draws``, matching the row order of ``arm_composite.sql`` output.

    The raw count rather than the probability is returned because the two arms' P(best)
    values must be recovered the way ``summarize`` recovers them — each as its own
    ``wins / draws`` division. ``1 - variant_probability`` differs from the control's
    ``(draws - wins) / draws`` in the last bit, which is enough to change a decision that
    lands exactly on the threshold.
    """
    rng = random.Random(seed)
    control = [
        rng.betavariate(control_numerator + 1, denominator - control_numerator + 1)
        for _ in range(draws)
    ]
    variant = [
        rng.betavariate(variant_numerator + 1, denominator - variant_numerator + 1)
        for _ in range(draws)
    ]
    wins = 0.0
    for control_draw, variant_draw in zip(control, variant):
        if variant_draw > control_draw:
            wins += 1.0
        elif variant_draw == control_draw:
            wins += 0.5
    return wins


def probability_best_variant(control_numerator, variant_numerator, denominator,
                             draws=DRAW_COUNT, seed=RNG_SEED):
    """Return the variant's P(best) exactly as experiment_report.summarize reports it."""
    return variant_wins(control_numerator, variant_numerator, denominator, draws, seed) / draws


def binomial(rng, trials, probability):
    """Draw one Binomial(trials, probability) with an explicit stdlib Bernoulli loop."""
    if probability <= 0.0:
        return 0
    if probability >= 1.0:
        return trials
    successes = 0
    for _ in range(trials):
        if rng.random() < probability:
            successes += 1
    return successes


def simulate_cell(job):
    """Score one (component, baseline, lift, N) cell; returns its per-replicate win counts.

    ``job`` is ``(key, cell_seed, baseline, lift, sample_size, replicates)``. The seed
    is drawn from the single replicate RNG in canonical cell order, so the result is
    independent of how the cells are scheduled across worker processes. The memo is a
    pure cache — the scored value is a deterministic function of the count pair — so it
    changes runtime and nothing else.
    """
    key, cell_seed, baseline, lift, sample_size, replicates = job
    rng = random.Random(cell_seed)
    treated = variant_rate(baseline, lift)
    memo = {}
    values = []
    for _ in range(replicates):
        control_numerator = binomial(rng, sample_size, baseline)
        variant_numerator = binomial(rng, sample_size, treated)
        pair = (control_numerator, variant_numerator)
        wins = memo.get(pair)
        if wins is None:
            wins = variant_wins(control_numerator, variant_numerator, sample_size)
            memo[pair] = wins
        values.append(wins)
    return key, values


def build_jobs(replicates):
    """Enumerate the distinct component cells the whole grid needs, seeded in order."""
    lifts = sorted({0.0, ALL_COMPONENT_LIFT} | set(SINGLE_COMPONENT_LIFTS))
    master = random.Random(REPLICATE_SEED)
    jobs = []
    for component in COMPONENTS:
        for baseline in BASELINE_GRIDS[component]:
            for lift in lifts:
                for sample_size in SAMPLE_SIZES:
                    key = (component, baseline, lift, sample_size)
                    jobs.append((key, master.getrandbits(64), baseline, lift, sample_size, replicates))
    return jobs


def run_cells(jobs, processes):
    """Evaluate every cell, in parallel when more than one process is available."""
    if processes <= 1:
        return dict(simulate_cell(job) for job in jobs)
    # Longest-processing-time-first: cells are scored in descending per-arm N so the
    # slowest cells start first and the pool drains evenly. Seeds were already bound to
    # keys in canonical order, so scheduling cannot change any result.
    ordered = sorted(jobs, key=lambda job: -job[4])
    with multiprocessing.Pool(processes) as pool:
        return dict(pool.map(simulate_cell, ordered, chunksize=1))


def mean(values):
    return sum(values) / len(values)


def combine(cells, baseline_point, lifts, sample_size, replicates, components=COMPONENTS):
    """Average the component P(best) vectors into one experiment's outcome row.

    ``components`` exists so the counterfactual composite that demotes purchase rate to
    a descriptive tiebreaker can be scored from the same cells.
    """
    vectors = [
        cells[(component, baseline_point[component], lifts[component], sample_size)]
        for component in components
    ]
    fire_variant = 0
    fire_control = 0
    composites = []
    for index in range(replicates):
        composite = sum(vector[index] / DRAW_COUNT for vector in vectors) / len(vectors)
        control_composite = sum(
            (DRAW_COUNT - vector[index]) / DRAW_COUNT for vector in vectors
        ) / len(vectors)
        composites.append(composite)
        if composite >= DECISION_THRESHOLD:
            fire_variant += 1
        elif control_composite >= DECISION_THRESHOLD:
            fire_control += 1
    return {
        "fire_variant": fire_variant / replicates,
        "fire_control": fire_control / replicates,
        "no_decision": (replicates - fire_variant - fire_control) / replicates,
        "expected_composite": mean(composites),
    }


def baseline_label(baseline_point):
    return "/".join(f"{baseline_point[component]:.2f}" for component in COMPONENTS)


def build_rows(cells, replicates):
    """Produce one result row per (baseline point x scenario x per-arm N)."""
    rows = []
    for baseline_point in BASELINE_POINTS:
        for scenario_name, lifts in SCENARIOS:
            for sample_size in SAMPLE_SIZES:
                outcome = combine(cells, baseline_point, lifts, sample_size, replicates)
                rows.append({
                    "baselines": baseline_label(baseline_point),
                    "baseline_point": baseline_point,
                    "scenario": scenario_name,
                    "n_per_arm": sample_size,
                    **outcome,
                })
    return rows


def percent(value):
    return f"{100.0 * value:.1f}%"


def results_table(rows):
    lines = [
        "| baselines act/d7/reach/purch | scenario | N per arm | P(fire variant) | P(fire control) | P(no decision) | E[composite] |",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            f"| {row['baselines']} | {row['scenario']} | {row['n_per_arm']} | "
            f"{percent(row['fire_variant'])} | {percent(row['fire_control'])} | "
            f"{percent(row['no_decision'])} | {row['expected_composite']:.4f} |"
        )
    return "\n".join(lines)


def null_false_positive(rows):
    """Pooled and worst-case P(either arm fires) under the null, per per-arm N."""
    summary = {}
    for sample_size in SAMPLE_SIZES:
        null_rows = [
            row for row in rows
            if row["scenario"] == "null" and row["n_per_arm"] == sample_size
        ]
        rates = [row["fire_variant"] + row["fire_control"] for row in null_rows]
        summary[sample_size] = {
            "pooled": mean(rates),
            "worst": max(rates),
            "variant_only": mean([row["fire_variant"] for row in null_rows]),
            "grid_points": len(null_rows),
        }
    return summary


def power_profile(rows, scenario):
    """Pooled, worst and best P(fire for variant) per per-arm N for one scenario."""
    profile = {}
    for sample_size in SAMPLE_SIZES:
        matched = [
            row for row in rows
            if row["scenario"] == scenario and row["n_per_arm"] == sample_size
        ]
        fires = [row["fire_variant"] for row in matched]
        profile[sample_size] = {"pooled": mean(fires), "worst": min(fires), "best": max(fires)}
    return profile


def smallest_n_at_least(profile, target, field):
    """Smallest tested per-arm N whose ``field`` reaches ``target`` (None if never)."""
    for sample_size in SAMPLE_SIZES:
        if profile[sample_size][field] >= target:
            return sample_size
    return None


def smallest_n_at_most(profile, target, field):
    """Smallest tested per-arm N whose ``field`` falls to ``target`` (None if never)."""
    for sample_size in SAMPLE_SIZES:
        if profile[sample_size][field] <= target:
            return sample_size
    return None


def component_profile(cells):
    """Per-component mean P(best) by per-arm N, for the null and each lift simulated."""
    lifts = sorted({0.0, ALL_COMPONENT_LIFT} | set(SINGLE_COMPONENT_LIFTS))
    profile = {}
    for component in COMPONENTS:
        for lift in lifts:
            for sample_size in SAMPLE_SIZES:
                values = []
                alone = 0
                for baseline in BASELINE_GRIDS[component]:
                    vector = [wins / DRAW_COUNT for wins in cells[(component, baseline, lift, sample_size)]]
                    values.extend(vector)
                    alone += sum(1 for value in vector if value >= DECISION_THRESHOLD)
                profile[(component, lift, sample_size)] = {
                    "mean": mean(values),
                    "reaches_threshold_alone": alone / len(values),
                }
    return profile


def required_partner_mean(purchase_mean):
    """Mean P(best) the other three components must hit to clear 0.90 with purchase."""
    return (4.0 * DECISION_THRESHOLD - purchase_mean) / 3.0


def subset_power(cells, scenario_name, components, replicates):
    """P(fire for variant) per per-arm N for a scenario scored on a component subset."""
    lifts = dict(SCENARIOS)[scenario_name]
    profile = {}
    for sample_size in SAMPLE_SIZES:
        fires = [
            combine(cells, baseline_point, lifts, sample_size, replicates, components)["fire_variant"]
            for baseline_point in BASELINE_POINTS
        ]
        profile[sample_size] = {"pooled": mean(fires), "worst": min(fires), "best": max(fires)}
    return profile


def profile_row(label, profile, field="pooled"):
    cells_text = " | ".join(percent(profile[size][field]) for size in SAMPLE_SIZES)
    return f"| {label} | {cells_text} |"


def size_header(first_column):
    header = " | ".join(str(size) for size in SAMPLE_SIZES)
    rule = "|---" + "|---:" * len(SAMPLE_SIZES) + "|"
    return f"| {first_column} | {header} |\n{rule}"


def describe(sample_size, fallback):
    return str(sample_size) if sample_size is not None else fallback


def build_summary(rows, cells, replicates, runtime_seconds, processes):
    """Render the SUMMARY section; every number is computed, never transcribed."""
    null_summary = null_false_positive(rows)
    activation_20 = power_profile(rows, "activation +20%")
    all_15 = power_profile(rows, "all +15%")
    three = tuple(component for component in COMPONENTS if component != "purchase_rate")
    activation_20_three = subset_power(cells, "activation +20%", three, replicates)
    all_15_three = subset_power(cells, "all +15%", three, replicates)
    components = component_profile(cells)

    fpr_500 = null_summary[500]
    fpr_floor = smallest_n_at_most(null_summary, 0.05, "worst")
    act_floor = smallest_n_at_least(activation_20, 0.80, "pooled")
    act_floor_worst = smallest_n_at_least(activation_20, 0.80, "worst")
    all_floor = smallest_n_at_least(all_15, 0.80, "pooled")
    all_floor_worst = smallest_n_at_least(all_15, 0.80, "worst")
    act_floor_three = smallest_n_at_least(activation_20_three, 0.80, "pooled")
    all_floor_three = smallest_n_at_least(all_15_three, 0.80, "pooled")

    purchase_50_1000 = components[("purchase_rate", 0.50, 1000)]["mean"]
    purchase_15_1000 = components[("purchase_rate", 0.15, 1000)]["mean"]
    purchase_50_3000 = components[("purchase_rate", 0.50, 3000)]["mean"]
    purchase_alone_1000 = components[("purchase_rate", 0.50, 1000)]["reaches_threshold_alone"]

    all_floor_three_worst = smallest_n_at_least(all_15_three, 0.80, "worst")
    if all_floor is not None:
        recommendation = (
            f"**{all_floor} mature installations per arm** on the frozen four-component composite, "
            f"pooled over the baseline grid; **{describe(all_floor_worst, 'no tested N')}** to hold "
            f"80% detection at the least favourable baseline point in the grid."
        )
    elif all_floor_three is not None:
        recommendation = (
            f"**{all_floor_three} mature installations per arm, and only if purchase rate is demoted "
            f"to a descriptive tiebreaker.** No tested per-arm N up to {SAMPLE_SIZES[-1]} reaches 80% "
            f"detection for \"all +15%\" while purchase rate carries equal weight. That "
            f"{all_floor_three} is the figure pooled over the baseline grid; holding 80% detection at "
            f"the **least favourable** baseline point needs "
            f"**{describe(all_floor_three_worst, f'more than {SAMPLE_SIZES[-1]}')}** per arm. If the "
            f"true baselines land at the pessimistic end — low activation, low D7 return — "
            f"{all_floor_three} per arm is not enough."
        )
    else:
        recommendation = (
            f"**no tested per-arm N up to {SAMPLE_SIZES[-1]} powers this rule**, on either the "
            f"four-component or the three-component composite; the honest options are a larger "
            f"minimum detectable effect, a lower threshold, or no experiment."
        )

    lines = []
    lines.append("## SUMMARY — the numbers the addendum blank needs")
    lines.append("")
    lines.append("### 1. Null false-positive rate (either arm reaching 0.90)")
    lines.append("")
    lines.append(size_header("null FPR, per-arm N"))
    lines.append(profile_row("pooled over the 36 baseline points", null_summary, "pooled"))
    lines.append(profile_row("worst single baseline point", null_summary, "worst"))
    lines.append(profile_row("variant arm only", null_summary, "variant_only"))
    lines.append("")
    lines.append(
        f"At **N = 500 per arm the null false-positive rate is {percent(fpr_500['pooled'])}** pooled "
        f"over {fpr_500['grid_points']} baseline points x {replicates} replicates "
        f"({fpr_500['grid_points'] * replicates:,} null experiments), worst single point "
        f"{percent(fpr_500['worst'])}."
    )
    lines.append("")
    lines.append(
        f"The smallest tested per-arm N with a null false-positive rate at or below 5% is "
        f"**{describe(fpr_floor, 'none of the tested sizes')}** — including the worst single "
        f"baseline point."
    )
    lines.append("")
    lines.append(
        "The 0.90 mean-of-P(best) rule is far more conservative than a 0.90 threshold sounds. "
        "Under the null each component's P(best) is approximately uniform on (0, 1), so the "
        "composite is the mean of four near-uniform variables; its density above 0.90 is tiny "
        "(analytically about 0.107% per arm, 0.21% for either arm, independent of N). "
        "**The sample floor is therefore not driven by false positives at all — it is driven "
        "entirely by detection.**"
    )
    lines.append("")
    lines.append("### 2. Smallest per-arm N reaching 80% detection")
    lines.append("")
    lines.append(size_header("P(fire for variant), per-arm N"))
    lines.append(profile_row("activation +20% — pooled", activation_20, "pooled"))
    lines.append(profile_row("activation +20% — worst baseline point", activation_20, "worst"))
    lines.append(profile_row("all +15% — pooled", all_15, "pooled"))
    lines.append(profile_row("all +15% — worst baseline point", all_15, "worst"))
    lines.append("")
    lines.append(
        f"- **activation +20%:** smallest N at 80% pooled = "
        f"**{describe(act_floor, 'not reached at any tested N')}**; at 80% for the worst baseline "
        f"point = **{describe(act_floor_worst, 'not reached at any tested N')}**."
    )
    lines.append(
        f"- **all +15%:** smallest N at 80% pooled = "
        f"**{describe(all_floor, 'not reached at any tested N')}**; at 80% for the worst baseline "
        f"point = **{describe(all_floor_worst, 'not reached at any tested N')}**."
    )
    lines.append("")
    lines.append(
        "**A single-component lift cannot meaningfully fire this rule at any sample size — "
        "detection plateaus at chance level, and that is arithmetic rather than power.** The three "
        "untouched components sit at P(best) = 0.5 in expectation, so even a component detected "
        "with total certainty puts the expected composite at (1.0 + 3 x 0.5) / 4 = 0.625 — well "
        "below 0.90. Firing then requires all three quiet components to drift high together: under "
        "the null each quiet component's P(best) stays approximately Uniform(0, 1) at every N "
        "(only its expectation is 0.5 — larger samples do not concentrate it), so the composite "
        "reaches 0.90 only when three uniforms sum to at least 2.6, which happens with probability "
        "0.4^3 / 3! = 1.1% regardless of N — chance, not detection, and exactly the plateau the "
        "activation +20% row shows. Dropping to three components only raises the expected ceiling "
        "to (1.0 + 2 x 0.5) / 3 = 0.667. The frozen composite is, by construction, a test of broad "
        "multi-component movement — it cannot be read as a test of any single metric."
    )
    lines.append("")
    lines.append("### 3. Can purchase rate move the composite at these sample sizes?")
    lines.append("")
    lines.append(size_header("mean component P(best), per-arm N"))
    for component in COMPONENTS:
        for lift in (0.0, ALL_COMPONENT_LIFT, 0.50):
            label = f"{COMPONENT_LABELS[component]} " + ("null" if lift == 0.0 else f"+{int(round(lift * 100))}%")
            row = {size: components[(component, lift, size)] for size in SAMPLE_SIZES}
            lines.append(profile_row(label, row, "mean"))
    lines.append("")
    lines.append(
        f"**No.** Purchase rate is the weakest component by a wide margin at every tested size. "
        f"Even a **+50% relative lift** on purchase — 0.02 to 0.03, or 0.05 to 0.075 — yields a mean "
        f"purchase P(best) of only **{purchase_50_1000:.3f} at N = 1000** and "
        f"**{purchase_50_3000:.3f} at N = 3000**; the +15% lift used in the \"all\" scenario yields "
        f"**{purchase_15_1000:.3f} at N = 1000**, barely distinguishable from the 0.5 of a coin flip. "
        f"Purchase reaches 0.90 on its own in {percent(purchase_alone_1000)} of replicates at "
        f"N = 1000 even under the +50% lift."
    )
    lines.append("")
    partners_15_1000 = mean([
        components[(component, ALL_COMPONENT_LIFT, 1000)]["mean"]
        for component in three
    ])
    four_15_1000 = (3.0 * partners_15_1000 + purchase_15_1000) / 4.0
    lines.append(
        f"The consequence is mechanical: with purchase contributing about {purchase_15_1000:.3f}, the "
        f"other three components must average **{required_partner_mean(purchase_15_1000):.3f}** for the "
        f"composite to reach 0.90. Under \"all +15%\" at N = 1000 those three actually average "
        f"{partners_15_1000:.3f}, so including purchase pulls the expected composite from "
        f"{partners_15_1000:.3f} down to {four_15_1000:.3f} — **a drag of "
        f"{partners_15_1000 - four_15_1000:.3f} composite points that the real signals have to pay "
        f"for, against a threshold they are already short of**. The reason is the event count, not "
        f"the rule: at a 0.02 baseline, N = 1000 per arm produces about 20 conversions per arm, and a "
        f"Beta(21, 981) posterior is far too wide for a 15% relative difference to separate."
    )
    lines.append("")
    lines.append("Counterfactual — the same grid scored with purchase demoted to a descriptive tiebreaker:")
    lines.append("")
    lines.append(size_header("P(fire for variant), 3-component composite"))
    lines.append(profile_row("activation +20% — pooled", activation_20_three, "pooled"))
    lines.append(profile_row("all +15% — pooled", all_15_three, "pooled"))
    lines.append(profile_row("all +15% — worst baseline point", all_15_three, "worst"))
    lines.append("")
    lines.append(
        f"Demoting purchase moves the \"all +15%\" 80% floor from "
        f"**{describe(all_floor, 'unreachable')}** to **{describe(all_floor_three, 'still unreachable')}** "
        f"and the \"activation +20%\" floor from **{describe(act_floor, 'unreachable')}** to "
        f"**{describe(act_floor_three, 'still unreachable')}**. This is the evidence the addendum's "
        f"purchase-rate weight clause asks for."
    )
    lines.append("")
    lines.append("### 4. Recommended per-arm floor")
    lines.append("")
    lines.append(f"Per-arm mature-installation floor: {recommendation}")
    lines.append("")
    lines.append(
        "That floor is only meaningful for the effect the rule can actually see. It is the sample "
        "at which a **broad** improvement — every component up together — is detected 80% of the "
        "time. No sample size in this grid makes a single-component improvement detectable, so the "
        "floor must not be quoted as power for activation, D7 return, paywall reach or purchase "
        "individually."
    )
    lines.append("")
    lines.append(
        f"The inherited 500 is **not** defensible as a detection floor: at N = 500 the frozen "
        f"four-component rule fires for a genuine \"all +15%\" improvement only "
        f"{percent(all_15[500]['pooled'])} of the time (pooled) and for a genuine activation +20% "
        f"improvement only {percent(activation_20[500]['pooled'])} of the time. It is, however, "
        f"perfectly safe against false positives ({percent(fpr_500['pooled'])}). **The inherited "
        f"floor buys safety the rule already had, and buys no power at all.**"
    )
    lines.append("")
    lines.append(
        f"Run parameters: {replicates} replicates per cell, {DRAW_COUNT:,} Beta draws at seed "
        f"{RNG_SEED} per component, replicate seed {REPLICATE_SEED}, decision threshold "
        f"{DECISION_THRESHOLD:.2f}, {len(BASELINE_POINTS)} baseline points x {len(SCENARIOS)} "
        f"scenarios x {len(SAMPLE_SIZES)} sample sizes = {len(rows):,} result rows. Wall clock "
        f"{runtime_seconds:.1f}s on {processes} worker process(es)."
    )
    return "\n".join(lines)


LIMITS = """## LIMITS — read before quoting any number above

1. **The baseline rates are guesses.** Garage has never measured activation, D7 return,
   paywall reach or purchase rate on a real cohort. The grids are deliberately wide so the
   conclusions are shape statements ("purchase cannot move this composite", "single-component
   lifts cannot fire this rule"), not point estimates. **Rerun this program with the observed
   epoch-2 rates as soon as the first mature cohort lands, and treat any floor quoted before
   that as provisional.**
2. **Independence across components is assumed.** Real installations that activate are far more
   likely to return on day 7 and to reach a paywall. Positive correlation makes the four
   component P(best) values move together, which *raises* the variance of the composite: it
   makes both firing and false flipping more likely than reported here. The null false-positive
   figure is therefore a floor, not a ceiling, and the detection figures are optimistic for
   correlated components.
3. **The effect model is a clean relative lift with no heterogeneity, no novelty decay and no
   time trend.** A design change whose effect fades over the seven-day maturity window will be
   detected less often than this simulation says.
4. **Replicate resolution.** Each reported probability is the share of a finite number of
   replicates per baseline point, so single-point figures carry a binomial standard error of up
   to 2.5 percentage points at 400 replicates. Pooled figures over the whole baseline grid are
   correspondingly tighter. Small differences between adjacent sample sizes are noise.
5. **Only the composite decision rule is simulated.** SRM, crash-free guardrails, the exposure
   cutoff and the data-lag allowance are separate gates in the addendum and are not modelled.
6. **The per-arm N is *mature* installations, not enrolled installations.** Enrollment must
   exceed the floor by the seven-day maturity loss and any exposure that arrives after the
   cutoff. Do not fill the addendum blank with a raw enrollment target.
7. **This simulation cannot make an underpowered experiment informative.** If the recommended
   floor is out of reach for the epoch-2 traffic, the honest responses are a larger minimum
   detectable effect, a smaller component set, an explicitly lower threshold with its own
   false-positive budget, or declining to run the experiment — not enrolling anyway and reading
   the result as if it were powered."""


DOCUMENT_PATH = Path(__file__).resolve().parents[2] / "docs" / "research" / "2026-08-12_OC_SIMULATION_design_megatest.md"


def build_document(rows, summary, replicates, runtime_seconds, processes):
    """Assemble the generated research document: header, table, summary, limits."""
    header = [
        "# Operating-characteristic simulation — design_megatest epoch 2",
        "",
        "> GENERATED FILE. Produced by `scripts/analytics/oc_simulation.py`; do not hand-edit.",
        "> Regenerate with `python3 scripts/analytics/oc_simulation.py`.",
        "",
        "Required by the epoch-2 pre-registration addendum",
        "(`docs/research/2026-08-11_EXPERIMENT_design_megatest_epoch2_ADDENDUM.md`), which inherited a",
        "500-per-arm floor and a `P(best) >= 0.90` firing rule from epoch 1 without justifying either",
        "(Sol finding B13). The addendum's per-arm floor blank and its purchase-rate weight clause MUST",
        "be filled from the SUMMARY below.",
        "",
        "The decision rule is not re-derived here: it is the rule `scripts/analytics/experiment_report.py`",
        "already implements — Beta(1, 1) posteriors per arm and component, "
        f"{DRAW_COUNT:,} `random.Random({RNG_SEED})` draws,",
        "per-component P(best) with ties split, composite = arithmetic mean of the four component",
        f"P(best) values, decision fires at composite >= {DECISION_THRESHOLD:.2f}. The simulation's own",
        f"replicate data comes from a single RNG seeded {REPLICATE_SEED}.",
        "",
        f"Run: {replicates} replicates per component cell, {len(BASELINE_POINTS)} baseline points x "
        f"{len(SCENARIOS)} scenarios x {len(SAMPLE_SIZES)} per-arm sample sizes = {len(rows):,} rows; "
        f"{runtime_seconds:.1f}s wall clock on {processes} worker process(es).",
        "",
    ]
    return "\n".join(header + [
        summary,
        "",
        "## Full results",
        "",
        "Baselines are listed in component order: activation / D7 return / paywall reach / purchase.",
        "`P(fire control)` is the false flip — the control arm reaching 0.90 — which under a positive",
        "scenario means the simulation declared the wrong winner.",
        "",
        results_table(rows),
        "",
        LIMITS,
        "",
    ])


def selftest():
    """Deterministic fixture: proves scorer equivalence and pins the composite rule."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import experiment_report

    fixture = (
        "design_arm,n_exposed,activation_numerator,activation_denominator,d7_return_numerator,"
        "d7_return_denominator,core_actions_numerator,core_actions_denominator,"
        "paywall_reach_numerator,paywall_reach_denominator,purchase_numerator,purchase_denominator\n"
        "control,200,60,200,20,200,240,200,30,200,4,200\n"
        "variant_a,200,78,200,23,200,250,200,35,200,5,200\n"
    )
    report = experiment_report.summarize(experiment_report.read_csv_text(fixture))

    # 1. Scorer equivalence: the fast per-component scorer must reproduce summarize exactly,
    #    including the complement identity that lets the control arm be tested as 1 - variant.
    pairs = ((60, 78), (20, 23), (30, 35), (4, 5))
    reproduced = []
    for metric, (control_numerator, variant_numerator) in zip(report["metrics"], pairs):
        wins = variant_wins(control_numerator, variant_numerator, 200)
        assert wins / DRAW_COUNT == metric["arms"][1]["probability_best"], metric["metric"]
        assert (DRAW_COUNT - wins) / DRAW_COUNT == metric["arms"][0]["probability_best"], metric["metric"]
        reproduced.append(wins / DRAW_COUNT)

    # 2. Exact pinned values — any drift in draw count, seed, generation order or tie handling
    #    changes these.
    assert reproduced == [0.97145, 0.6855, 0.7504, 0.6245], reproduced

    # 3. The composite summarize reports is the arithmetic mean over the REGISTERED primary
    #    components — purchase_rate is demoted to a descriptive tiebreaker (epoch-2 addendum,
    #    the conditional the OC evidence fired). This simulation's grid still scores the
    #    historical 4-way rule alongside the registered 3-way counterfactual, so its tables
    #    remain valid for both; only this equivalence pin follows the executable rule.
    composite = report["composite_probability_best"][1]["mean_probability_best"]
    labels = [metric["metric"] for metric in report["metrics"]]
    primary = [
        value for label, value in zip(labels, reproduced)
        if label in experiment_report.PRIMARY_COMPOSITE_METRICS
    ]
    assert len(primary) == 3, labels
    assert composite == sum(primary) / 3.0, composite
    assert abs(composite - 0.80245) < 1e-12, composite
    assert composite < DECISION_THRESHOLD

    def wins_of(*probabilities):
        return [probability * DRAW_COUNT for probability in probabilities]

    #    Five hand-built replicates, one per behaviour the rule has to exhibit:
    #      r0 mean 0.90000 exactly  -> fires for the variant (the boundary is >=, not >)
    #      r1 mean 0.89875          -> just short, no decision
    #      r2 mean 0.10000          -> control composite hits 0.90, a false flip
    #      r3 mean 0.60000          -> no decision
    #      r4 mean 0.61250          -> no decision, but ONE component is at 0.95; a rule that
    #                                  took the best component instead of the mean would fire
    cells = {
        ("activation_rate", 0.30, 0.0, 200): wins_of(1.000, 0.900, 0.00, 0.60, 0.95),
        ("d7_return_rate", 0.10, 0.0, 200): wins_of(0.900, 0.900, 0.10, 0.60, 0.50),
        ("paywall_reach", 0.15, 0.0, 200): wins_of(0.800, 0.900, 0.20, 0.60, 0.50),
        ("purchase_rate", 0.02, 0.0, 200): wins_of(0.900, 0.895, 0.10, 0.60, 0.50),
    }
    baseline_point = {
        "activation_rate": 0.30, "d7_return_rate": 0.10,
        "paywall_reach": 0.15, "purchase_rate": 0.02,
    }
    outcome = combine(cells, baseline_point, {component: 0.0 for component in COMPONENTS}, 200, 5)
    assert outcome["fire_variant"] == 0.2, outcome
    assert outcome["fire_control"] == 0.2, outcome
    assert outcome["no_decision"] == 0.6, outcome
    assert abs(outcome["expected_composite"] - 0.62225) < 1e-12, outcome

    # 4. Replicate data is reproducible from the single seeded RNG, and cell seeds do not
    #    depend on scheduling order.
    jobs = build_jobs(2)
    lift_count = len({0.0, ALL_COMPONENT_LIFT} | set(SINGLE_COMPONENT_LIFTS))
    baseline_count = sum(len(BASELINE_GRIDS[component]) for component in COMPONENTS)
    assert len(jobs) == baseline_count * lift_count * len(SAMPLE_SIZES) == 250, len(jobs)
    assert build_jobs(2)[7][1] == jobs[7][1]
    key, values = simulate_cell((("probe",), 4242, 0.30, 0.20, 100, 2))
    assert key == ("probe",)
    assert [wins / DRAW_COUNT for wins in values] == [0.9452, 0.99285], values

    print(
        "SELFTEST PASS: per-component scorer is bit-identical to experiment_report.summarize "
        "(Beta(1,1), 20,000 draws, seed 42, tie-split P(best)), the reported composite is the "
        "mean of the registered 3 primary components (purchase demoted), the 0.90/0.10 decision "
        "boundaries are exact, and replicate seeding is reproducible."
    )


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fast", action="store_true",
                        help=f"use {FAST_REPLICATES} replicates per cell instead of {FULL_REPLICATES}")
    parser.add_argument("--selftest", action="store_true",
                        help="run the deterministic fixture that pins the frozen rule")
    parser.add_argument("--processes", type=int, default=0,
                        help="worker processes (default: one per CPU; 1 forces serial)")
    parser.add_argument("--out", type=Path, default=DOCUMENT_PATH,
                        help="markdown document to write (default: the epoch-2 research doc)")
    parser.add_argument("--no-write", action="store_true",
                        help="print the document to stdout without writing it")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.selftest:
        if args.fast:
            raise ValueError("--selftest cannot be combined with --fast")
        selftest()
        return
    replicates = FAST_REPLICATES if args.fast else FULL_REPLICATES
    processes = args.processes if args.processes > 0 else (os.cpu_count() or 1)
    if args.processes < 0:
        raise ValueError("--processes must be zero (auto) or positive")

    started = time.time()
    jobs = build_jobs(replicates)
    cells = run_cells(jobs, processes)
    rows = build_rows(cells, replicates)
    runtime_seconds = time.time() - started

    summary = build_summary(rows, cells, replicates, runtime_seconds, processes)
    document = build_document(rows, summary, replicates, runtime_seconds, processes)
    print(document)
    if not args.no_write:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(document, encoding="utf-8")
        print(f"Wrote {args.out} ({len(rows):,} rows, {runtime_seconds:.1f}s)", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(2)
