#!/usr/bin/env python3
"""consensus.py — the cortex's deterministic resolver (Organ I).

Pure, domain-free 2/3-majority resolver for multi-LLM decisions, plus an
append-only ledger writer. No I/O except the explicit ledger append.

Resolution law (the brain's Law 1 — no veto):
  * unanimous                     — every voter agrees.
  * majority                      — > n/2 voters agree; a high-confidence
                                    dissenter CANNOT override (no veto).
  * highest_confidence_no_majority— no group reaches majority (e.g. 1/1/1);
                                    pick the highest-confidence position
                                    deterministically and flag a second round.

Vote canonicalization (landmine #7): decisions are grouped by a hash of a
*normalized structure*, never a raw string join — so delimiter characters in a
label can never collide two distinct decisions into one group.

CLI:
  python3 consensus.py resolve  --positions positions.json [--ledger PATH] [--topic ...] [--timestamp ISO]
  python3 consensus.py selftest

A "position" is: {"agent": str, "decision": str|obj, "reasoning": str, "confidence": float in [0,1]}
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from typing import Any, Dict, List, Optional, Tuple

LEDGER_DEFAULT = "DECISION_LEDGER.jsonl"


# ---------------------------------------------------------------------------
# Canonicalization
# ---------------------------------------------------------------------------
def canonical_key(decision: Any) -> str:
    """Return an injective canonical group key for a decision.

    We JSON-serialize a *normalized structure* with sorted keys and hash it.
    Strings are lowercased and whitespace-collapsed first so that "Option A"
    and "option   a" group together, while structured decisions hash on their
    full shape — never on a delimiter-joined string (landmine #7).
    """
    if isinstance(decision, str):
        norm: Any = " ".join(decision.strip().lower().split())
    elif isinstance(decision, (int, float, bool)) or decision is None:
        norm = decision
    else:
        # dict / list — normalize recursively, then canonical-JSON it.
        norm = _normalize_structure(decision)
    blob = json.dumps(norm, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:16]


def _normalize_structure(obj: Any) -> Any:
    if isinstance(obj, str):
        return " ".join(obj.strip().lower().split())
    if isinstance(obj, dict):
        return {k: _normalize_structure(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_normalize_structure(v) for v in obj]
    return obj


def _clamp_conf(c: Any) -> float:
    try:
        c = float(c)
    except (TypeError, ValueError):
        return 0.0
    return max(0.0, min(1.0, c))


# ---------------------------------------------------------------------------
# Resolver
# ---------------------------------------------------------------------------
def resolve_majority(positions: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Resolve a list of voter positions into a single decision.

    Returns a resolution dict (see DECISION_LEDGER schema). Pure: no I/O.
    """
    if not positions:
        raise ValueError("resolve_majority requires at least one position")

    n = len(positions)
    # Group positions by canonical decision key.
    groups: Dict[str, Dict[str, Any]] = {}
    for p in positions:
        key = canonical_key(p.get("decision"))
        g = groups.setdefault(
            key, {"key": key, "label": p.get("decision"), "votes": [], "conf_sum": 0.0}
        )
        g["votes"].append(p)
        g["conf_sum"] += _clamp_conf(p.get("confidence"))

    # Rank groups: vote count desc, then summed confidence desc, then key (stable, deterministic).
    ranked = sorted(
        groups.values(),
        key=lambda g: (len(g["votes"]), g["conf_sum"], g["key"]),
        reverse=True,
    )
    top = ranked[0]
    top_votes = len(top["votes"])
    majority_threshold = n // 2 + 1  # strict majority (> n/2)

    has_majority = top_votes >= majority_threshold
    is_unanimous = top_votes == n

    if is_unanimous:
        rule = "unanimous"
        needs_second_round = False
    elif has_majority:
        rule = "majority"
        needs_second_round = False
    else:
        # No majority (e.g. 1/1/1). Deterministic highest-confidence fallback.
        rule = "highest_confidence_no_majority"
        needs_second_round = True
        # Re-pick the single highest-confidence individual position.
        best = max(
            positions,
            key=lambda p: (_clamp_conf(p.get("confidence")), canonical_key(p.get("decision"))),
        )
        top = {
            "key": canonical_key(best.get("decision")),
            "label": best.get("decision"),
            "votes": [best],
            "conf_sum": _clamp_conf(best.get("confidence")),
        }
        top_votes = 1

    winner = top["votes"][0]
    confidences = {p.get("agent", f"voter{i}"): _clamp_conf(p.get("confidence"))
                   for i, p in enumerate(positions)}

    return {
        "winner_agent": winner.get("agent"),
        "decision": top["label"],
        "rule": rule,
        "vote_count": top_votes,
        "n_agents": n,
        "has_majority": has_majority,
        "group_key": top["key"],
        "confidences": confidences,
        "needs_second_round": needs_second_round,
    }


# ---------------------------------------------------------------------------
# Ledger
# ---------------------------------------------------------------------------
def append_ledger_majority(
    positions: List[Dict[str, Any]],
    topic: str,
    timestamp: str,
    ledger_path: str = LEDGER_DEFAULT,
    protocol: str = "tri_agent_majority",
    extra: Optional[Dict[str, Any]] = None,
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    """Resolve and append one line to the decision ledger. Returns (row, resolution).

    `timestamp` is required and must be passed by the caller (landmine #6 — never
    a null/auto timestamp; explicit timestamps also enable deterministic resume).
    """
    if not timestamp:
        raise ValueError("append_ledger_majority requires an explicit ISO8601 timestamp")
    resolution = resolve_majority(positions)
    row = {
        "timestamp": timestamp,
        "topic": topic,
        "protocol": protocol,
        "resolution": resolution,
        "positions": [
            {
                "agent": p.get("agent"),
                "decision": p.get("decision"),
                "reasoning": p.get("reasoning", ""),
                "confidence": _clamp_conf(p.get("confidence")),
            }
            for p in positions
        ],
        "extra": extra or {},
    }
    with open(ledger_path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False) + "\n")
    return row, resolution


# ---------------------------------------------------------------------------
# Self-test (no external deps; doubles as the unit suite)
# ---------------------------------------------------------------------------
def _selftest() -> int:
    failures = []

    def check(name, cond):
        if not cond:
            failures.append(name)
            print(f"  FAIL  {name}")
        else:
            print(f"  ok    {name}")

    # 1. Unanimous 3/3.
    r = resolve_majority([
        {"agent": "claude", "decision": "A", "confidence": 0.9},
        {"agent": "codex", "decision": "A", "confidence": 0.8},
        {"agent": "gemini", "decision": "A", "confidence": 0.7},
    ])
    check("unanimous rule", r["rule"] == "unanimous")
    check("unanimous has_majority", r["has_majority"] is True)
    check("unanimous decision A", r["decision"] == "A")
    check("unanimous no second round", r["needs_second_round"] is False)

    # 2. Majority 2/3 — high-confidence dissenter CANNOT veto.
    r = resolve_majority([
        {"agent": "claude", "decision": "A", "confidence": 0.51},
        {"agent": "codex", "decision": "A", "confidence": 0.52},
        {"agent": "gemini", "decision": "B", "confidence": 0.99},  # loud dissenter
    ])
    check("majority rule", r["rule"] == "majority")
    check("majority beats veto (decision A)", r["decision"] == "A")
    check("majority vote_count 2", r["vote_count"] == 2)
    check("majority no second round", r["needs_second_round"] is False)

    # 3. No majority 1/1/1 — deterministic highest-confidence fallback + flag.
    r = resolve_majority([
        {"agent": "claude", "decision": "A", "confidence": 0.4},
        {"agent": "codex", "decision": "B", "confidence": 0.7},
        {"agent": "gemini", "decision": "C", "confidence": 0.6},
    ])
    check("no-majority rule", r["rule"] == "highest_confidence_no_majority")
    check("no-majority picks highest conf (B)", r["decision"] == "B")
    check("no-majority flags second round", r["needs_second_round"] is True)
    check("no-majority has_majority False", r["has_majority"] is False)

    # 4. Canonicalization: normalized strings group; delimiters never collide.
    check("canonical normalizes case/space",
          canonical_key("Option A") == canonical_key("option   a"))
    check("canonical distinct labels differ",
          canonical_key("A|B") != canonical_key("A") )
    r = resolve_majority([
        {"agent": "a", "decision": "Ship It", "confidence": 0.6},
        {"agent": "b", "decision": "ship   it", "confidence": 0.6},
        {"agent": "c", "decision": "Hold", "confidence": 0.9},
    ])
    check("normalized variants form a majority", r["rule"] == "majority" and r["vote_count"] == 2)

    # 5. Determinism: same input → same group_key across runs.
    k1 = canonical_key({"x": 1, "y": [2, 3]})
    k2 = canonical_key({"y": [2, 3], "x": 1})
    check("structured canonical is order-independent", k1 == k2)

    # 6. Ledger requires explicit timestamp.
    try:
        append_ledger_majority([{"agent": "a", "decision": "A", "confidence": 1}], "t", "")
        check("ledger rejects empty timestamp", False)
    except ValueError:
        check("ledger rejects empty timestamp", True)

    print()
    if failures:
        print(f"SELFTEST FAILED: {len(failures)} failure(s)")
        return 1
    print("SELFTEST PASSED")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Pure 2/3-majority consensus resolver + ledger.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    rp = sub.add_parser("resolve", help="Resolve positions; optionally append to the ledger.")
    rp.add_argument("--positions", required=True, help="Path to JSON array of positions.")
    rp.add_argument("--topic", default="(unspecified)")
    rp.add_argument("--timestamp", default="", help="ISO8601; required to append to the ledger.")
    rp.add_argument("--ledger", default=LEDGER_DEFAULT)
    rp.add_argument("--no-append", action="store_true", help="Resolve only; do not write the ledger.")

    sub.add_parser("selftest", help="Run the built-in unit suite.")

    args = ap.parse_args(argv)

    if args.cmd == "selftest":
        return _selftest()

    if args.cmd == "resolve":
        with open(args.positions, encoding="utf-8") as fh:
            positions = json.load(fh)
        if args.no_append or not args.timestamp:
            resolution = resolve_majority(positions)
            print(json.dumps(resolution, indent=2, ensure_ascii=False))
            if not args.timestamp and not args.no_append:
                print("# (no --timestamp given; resolved only, not appended)", file=sys.stderr)
            return 0
        row, resolution = append_ledger_majority(
            positions, topic=args.topic, timestamp=args.timestamp, ledger_path=args.ledger
        )
        print(json.dumps(resolution, indent=2, ensure_ascii=False))
        print(f"# appended to {args.ledger}", file=sys.stderr)
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
