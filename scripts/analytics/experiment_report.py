#!/usr/bin/env python3
"""Summarize arm_composite SQL output with deterministic Beta posteriors."""

import argparse
import csv
import json
import math
from pathlib import Path
import random
import subprocess
import sys


DRAW_COUNT = 20_000
RNG_SEED = 42
BINARY_METRICS = (
    ("activation_rate", "activation_numerator", "activation_denominator"),
    ("d7_return_rate", "d7_return_numerator", "d7_return_denominator"),
    ("paywall_reach", "paywall_reach_numerator", "paywall_reach_denominator"),
    ("purchase_rate", "purchase_numerator", "purchase_denominator"),
)
CORE_METRIC = ("core_actions_per_active_day", "core_actions_numerator", "core_actions_denominator")


def regularized_gamma_q(shape, value):
    """Return Q(shape, value) using a stable series or continued fraction."""
    if shape <= 0 or value < 0:
        raise ValueError("regularized gamma requires shape > 0 and value >= 0")
    if value == 0:
        return 1.0
    if value < shape + 1.0:
        term = 1.0 / shape
        total = term
        current = shape
        for _ in range(1, 10_001):
            current += 1.0
            term *= value / current
            total += term
            if abs(term) <= abs(total) * 1e-14:
                return max(0.0, min(1.0, 1.0 - total * math.exp(-value + shape * math.log(value) - math.lgamma(shape))))
        raise RuntimeError("gamma series did not converge")

    tiny = 1e-300
    b = value + 1.0 - shape
    c = 1.0 / tiny
    d = 1.0 / max(b, tiny)
    fraction = d
    for iteration in range(1, 10_001):
        coefficient = -iteration * (iteration - shape)
        b += 2.0
        d = coefficient * d + b
        if abs(d) < tiny:
            d = tiny
        c = b + coefficient / c
        if abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        delta = d * c
        fraction *= delta
        if abs(delta - 1.0) <= 1e-14:
            return max(0.0, min(1.0, math.exp(-value + shape * math.log(value) - math.lgamma(shape)) * fraction))
    raise RuntimeError("gamma continued fraction did not converge")


def chi_square_srm(exposures):
    """Equal-allocation chi-square test; returns (chi_square, degrees, p_value)."""
    if len(exposures) < 2:
        return 0.0, 0, 1.0
    total = sum(exposures)
    if total == 0:
        return 0.0, len(exposures) - 1, 1.0
    expected = total / len(exposures)
    chi_square = sum((observed - expected) ** 2 / expected for observed in exposures)
    degrees = len(exposures) - 1
    return chi_square, degrees, regularized_gamma_q(degrees / 2.0, chi_square / 2.0)


def integer(row, column, arm):
    try:
        value = int(row[column])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError(f"arm {arm!r} has invalid integer {column!r}") from error
    if value < 0:
        raise ValueError(f"arm {arm!r} has negative {column!r}")
    return value


def read_csv_text(text):
    rows = list(csv.DictReader(text.splitlines()))
    if not rows:
        raise ValueError("CSV contains no arm rows")
    required = {"design_arm", "n_exposed"}
    for _, numerator, denominator in BINARY_METRICS + (CORE_METRIC,):
        required.update((numerator, denominator))
    missing = sorted(required - set(rows[0]))
    if missing:
        raise ValueError("CSV is missing required columns: " + ", ".join(missing))
    arms = [row["design_arm"].strip() for row in rows]
    if any(not arm for arm in arms) or len(set(arms)) != len(arms):
        raise ValueError("design_arm must be non-empty and unique")
    return rows


def summarize(rows, draws=DRAW_COUNT, seed=RNG_SEED):
    arms = [row["design_arm"].strip() for row in rows]
    exposure_counts = [integer(row, "n_exposed", arm) for row, arm in zip(rows, arms)]
    chi_square, degrees, p_value = chi_square_srm(exposure_counts)
    metrics = []
    composite = {arm: [] for arm in arms}

    for label, numerator_column, denominator_column in BINARY_METRICS:
        numerators = [integer(row, numerator_column, arm) for row, arm in zip(rows, arms)]
        denominators = [integer(row, denominator_column, arm) for row, arm in zip(rows, arms)]
        for arm, numerator, denominator in zip(arms, numerators, denominators):
            if numerator > denominator:
                raise ValueError(
                    f"{label}: arm {arm!r} has numerator {numerator} greater than denominator {denominator}; "
                    "Beta-binomial reporting requires a binary numerator."
                )
        rng = random.Random(seed)
        samples = [
            [rng.betavariate(numerator + 1, denominator - numerator + 1) for _ in range(draws)]
            for numerator, denominator in zip(numerators, denominators)
        ]
        wins = [0.0] * len(arms)
        losses = [0.0] * len(arms)
        for draw_index in range(draws):
            best = max(sample[draw_index] for sample in samples)
            winners = [index for index, sample in enumerate(samples) if sample[draw_index] == best]
            for index in winners:
                wins[index] += 1.0 / len(winners)
            for index, sample in enumerate(samples):
                losses[index] += best - sample[draw_index]
        arm_results = []
        for arm, numerator, denominator, win_count, loss in zip(
            arms, numerators, denominators, wins, losses
        ):
            p_best = win_count / draws
            composite[arm].append(p_best)
            arm_results.append({
                "arm": arm,
                "numerator": numerator,
                "denominator": denominator,
                "observed_rate": numerator / denominator if denominator else None,
                "posterior_mean": (numerator + 1) / (denominator + 2),
                "probability_best": p_best,
                "expected_loss_vs_best": loss / draws,
            })
        metrics.append({"metric": label, "arms": arm_results})

    core_label, core_numerator_column, core_denominator_column = CORE_METRIC
    core = []
    for row, arm in zip(rows, arms):
        numerator = integer(row, core_numerator_column, arm)
        denominator = integer(row, core_denominator_column, arm)
        core.append({
            "arm": arm,
            "numerator": numerator,
            "denominator": denominator,
            "observed_rate": numerator / denominator if denominator else None,
        })

    return {
        "draw_count": draws,
        "rng_seed": seed,
        "metrics": metrics,
        "core_actions_per_active_day": core,
        "composite_probability_best": [
            {"arm": arm, "mean_probability_best": sum(composite[arm]) / len(composite[arm])}
            for arm in arms
        ],
        "srm": {
            "assumption": "equal allocation across arms",
            "n_exposed": dict(zip(arms, exposure_counts)),
            "chi_square": chi_square,
            "degrees_of_freedom": degrees,
            "p_value": p_value,
            "warning": p_value < 0.001,
            "method": "chi-square survival probability via regularized incomplete gamma Q",
        },
    }


def percent(value):
    return "n/a" if value is None else f"{100.0 * value:6.2f}%"


def ratio(value):
    return "n/a" if value is None else f"{value:.4f}"


def print_table(report):
    print(f"Experiment report — {report['draw_count']:,} Beta draws, seed {report['rng_seed']}")
    srm = report["srm"]
    print(
        "SRM (equal allocation): "
        f"chi2={srm['chi_square']:.4f}, df={srm['degrees_of_freedom']}, p={srm['p_value']:.6g}"
        + ("  WARNING: p < 0.001" if srm["warning"] else "")
    )
    print()
    for metric in report["metrics"]:
        print(metric["metric"])
        print("  arm                 numerator/denominator  observed  posterior  P(best)  expected loss")
        for arm in metric["arms"]:
            print(
                f"  {arm['arm']:<19} {arm['numerator']:>8}/{arm['denominator']:<10} "
                f"{percent(arm['observed_rate']):>8} {percent(arm['posterior_mean']):>9} "
                f"{percent(arm['probability_best']):>8} {percent(arm['expected_loss_vs_best']):>14}"
            )
        print()
    print("core_actions_per_active_day (descriptive; excluded from Beta composite)")
    print("  arm                 actions/active-days    observed")
    for arm in report["core_actions_per_active_day"]:
        print(
            f"  {arm['arm']:<19} {arm['numerator']:>8}/{arm['denominator']:<10} "
            f"{ratio(arm['observed_rate'])}"
        )
    print()
    print("Composite = mean P(best) across activation, D7 return, paywall reach (ITT), and purchase rate")
    for arm in report["composite_probability_best"]:
        print(f"  {arm['arm']:<19} {percent(arm['mean_probability_best'])}")


def run_bq(sql_path, timeout_seconds):
    sql = sql_path.read_text(encoding="utf-8")
    try:
        completed = subprocess.run(
            ["bq", "query", "--use_legacy_sql=false", "--format=csv"],
            input=sql,
            text=True,
            capture_output=True,
            timeout=timeout_seconds,
            check=False,
        )
    except FileNotFoundError as error:
        raise RuntimeError("bq CLI was not found on PATH; use --csv or install/configure Google Cloud CLI") from error
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"bq query exceeded the explicit {timeout_seconds}s timeout") from error
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "no diagnostic output"
        raise RuntimeError(f"bq query failed (exit {completed.returncode}): {detail}")
    return completed.stdout


def selftest():
    fixture = """design_arm,n_exposed,activation_numerator,activation_denominator,d7_return_numerator,d7_return_denominator,core_actions_numerator,core_actions_denominator,paywall_reach_numerator,paywall_reach_denominator,purchase_numerator,purchase_denominator
control,100,20,100,30,100,130,100,10,40,5,100
variant_a,100,60,100,65,100,180,100,28,40,30,100
"""
    report = summarize(read_csv_text(fixture), draws=DRAW_COUNT, seed=RNG_SEED)
    activation = report["metrics"][0]["arms"]
    assert abs(activation[0]["posterior_mean"] - 21 / 102) < 1e-12
    assert activation[1]["probability_best"] > 0.999
    assert activation[0]["expected_loss_vs_best"] > 0.0
    assert report["srm"]["p_value"] == 1.0
    assert abs(regularized_gamma_q(0.5, 5.0) - 0.001565402258) < 1e-9
    assert report["core_actions_per_active_day"][1]["observed_rate"] == 1.8
    assert report["composite_probability_best"][1]["mean_probability_best"] > 0.99
    print("SELFTEST PASS: Beta posteriors, Monte Carlo P(best)/loss, composite, and chi-square SRM gamma math verified.")


def parse_args():
    default_sql = Path(__file__).resolve().parent / "sql" / "arm_composite.sql"
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--csv", type=Path, help="CSV exported from arm_composite.sql")
    source.add_argument("--bq", action="store_true", help="execute --sql through bq query")
    parser.add_argument("--sql", type=Path, default=default_sql, help="SQL used with --bq")
    parser.add_argument("--timeout-seconds", type=int, default=120, help="explicit bq timeout (default: 120)")
    parser.add_argument("--json", dest="json_path", type=Path, help="write full report JSON to this path")
    parser.add_argument("--selftest", action="store_true", help="run embedded deterministic math fixture")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.selftest:
        if args.csv or args.bq:
            raise ValueError("--selftest cannot be combined with --csv or --bq")
        selftest()
        return
    if not args.csv and not args.bq:
        raise ValueError("choose exactly one input source: --csv PATH or --bq")
    if args.timeout_seconds <= 0:
        raise ValueError("--timeout-seconds must be positive")
    text = args.csv.read_text(encoding="utf-8") if args.csv else run_bq(args.sql, args.timeout_seconds)
    report = summarize(read_csv_text(text))
    print_table(report)
    if args.json_path:
        args.json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nWrote JSON: {args.json_path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(2)
