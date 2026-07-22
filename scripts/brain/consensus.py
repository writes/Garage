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
import re
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


# A leading enumerated label: "A: ...", "b) ...", "C - ...", "A." or a bare "A".
# Deliberately does NOT match "A and B ..." (no separator after the letter), so
# hedged multi-option answers never silently collapse into one option's group.
_ENUM_LABEL_RE = re.compile(r"^\s*([A-Za-z])(?:\s*[:.)\-]|\s*$)")


def _enum_letter(text: Any) -> Optional[str]:
    if not isinstance(text, str):
        return None
    m = _ENUM_LABEL_RE.match(text)
    return m.group(1).lower() if m else None


def enum_option_map(options: Optional[List[str]]) -> Dict[str, str]:
    """Map enumerated option letters -> full option text (e.g. {'a': 'A: ...'})."""
    letters: Dict[str, str] = {}
    for o in options or []:
        letter = _enum_letter(o)
        if letter:
            letters[letter] = o
    return letters


def resolve_enum(decision: Any, letters: Dict[str, str]) -> Optional[str]:
    """Resolve a voter's decision to an enumerated option letter, else None.

    Handles the observed grouping failure (2026-07-11 vehicle-limit vote): one
    voter answers a bare "A" while another answers "A: <full option text>" —
    string-hash canonicalization put them in different groups, flipping a 2/3
    majority into a highest-confidence fallback (a Law-1 violation: the loud
    dissenter effectively vetoed). Matching is anchored to the option roster:
    (1) an explicit leading letter that exists in the roster wins; (2) otherwise
    a decision whose normalized text uniquely prefix/substring-matches exactly
    one option (voters sometimes echo the option body without its letter).
    Anything ambiguous falls back to plain canonical_key — never guessed.
    """
    if not letters or not isinstance(decision, str):
        return None
    letter = _enum_letter(decision)
    if letter is not None:
        return letter if letter in letters else None
    dnorm = " ".join(decision.strip().lower().split())
    if not dnorm:
        return None
    matches = []
    for letter, option in letters.items():
        onorm = " ".join(option.strip().lower().split())
        obody = onorm.split(":", 1)[1].strip() if ":" in onorm else onorm
        if (
            onorm.startswith(dnorm)
            or dnorm.startswith(onorm)
            or obody.startswith(dnorm)
            or (len(dnorm) >= 16 and dnorm in onorm)
        ):
            matches.append(letter)
    return matches[0] if len(matches) == 1 else None


def _clamp_conf(c: Any) -> float:
    try:
        c = float(c)
    except (TypeError, ValueError):
        return 0.0
    return max(0.0, min(1.0, c))


# ---------------------------------------------------------------------------
# Resolver
# ---------------------------------------------------------------------------
def resolve_majority(
    positions: List[Dict[str, Any]],
    options: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """Resolve a list of voter positions into a single decision.

    When `options` (the enumerated option strings shown to voters) is provided,
    decisions are grouped by their resolved option letter first, so "A" and
    "A: <full text>" and the echoed option body all land in one group; the
    group label is the full roster text. Returns a resolution dict (see
    DECISION_LEDGER schema). Pure: no I/O.
    """
    if not positions:
        raise ValueError("resolve_majority requires at least one position")

    n = len(positions)
    letters = enum_option_map(options)

    def _key_label(decision: Any) -> Tuple[str, Any]:
        letter = resolve_enum(decision, letters)
        if letter is not None:
            key = hashlib.sha256(f"enum:{letter}".encode("utf-8")).hexdigest()[:16]
            return key, letters[letter]
        return canonical_key(decision), decision

    # Group positions by canonical decision key.
    groups: Dict[str, Dict[str, Any]] = {}
    for p in positions:
        key, label = _key_label(p.get("decision"))
        g = groups.setdefault(
            key, {"key": key, "label": label, "votes": [], "conf_sum": 0.0}
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
            key=lambda p: (_clamp_conf(p.get("confidence")), _key_label(p.get("decision"))[0]),
        )
        best_key, best_label = _key_label(best.get("decision"))
        top = {
            "key": best_key,
            "label": best_label,
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
    options: Optional[List[str]] = None,
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    """Resolve and append one line to the decision ledger. Returns (row, resolution).

    `timestamp` is required and must be passed by the caller (landmine #6 — never
    a null/auto timestamp; explicit timestamps also enable deterministic resume).
    `options` is the enumerated option roster shown to voters; passing it enables
    letter-anchored grouping (see resolve_majority).
    """
    if not timestamp:
        raise ValueError("append_ledger_majority requires an explicit ISO8601 timestamp")
    resolution = resolve_majority(positions, options=options)
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

    # 4b. Enum-anchored grouping (regression: 2026-07-11 vehicle-limit vote —
    # bare "A" vs "A: <full text>" split a true 2/3 majority into a
    # highest-confidence fallback, letting the lone dissenter win).
    opts = [
        "A: Rules + client-maintained counter with getAfter invariants",
        "B: Cloud Function counter",
        "C: Callable-only creation",
    ]
    r = resolve_majority([
        {"agent": "claude", "decision": opts[0], "confidence": 0.75},
        {"agent": "codex", "decision": opts[2], "confidence": 0.97},
        {"agent": "gemini", "decision": "A", "confidence": 0.95},
    ], options=opts)
    check("enum: bare letter joins full-text group (majority A)",
          r["rule"] == "majority" and r["vote_count"] == 2 and r["decision"] == opts[0])
    check("enum: dissenter cannot win via confidence fallback",
          r["needs_second_round"] is False)
    r = resolve_majority([
        {"agent": "a", "decision": "b) Cloud Function counter", "confidence": 0.5},
        {"agent": "b", "decision": "B: Cloud Function counter", "confidence": 0.5},
        {"agent": "c", "decision": "A", "confidence": 0.9},
    ], options=opts)
    check("enum: letter-separator variants group", r["vote_count"] == 2 and r["decision"] == opts[1])
    r = resolve_majority([
        {"agent": "a", "decision": "Rules + client-maintained counter with getAfter invariants", "confidence": 0.5},
        {"agent": "b", "decision": "A", "confidence": 0.5},
        {"agent": "c", "decision": "C", "confidence": 0.9},
    ], options=opts)
    check("enum: echoed option body (no letter) groups with its letter",
          r["vote_count"] == 2 and r["decision"] == opts[0])
    # Hedged / out-of-roster answers must NOT be silently mapped to an option.
    check("enum: hedged 'A and B' never resolves to a letter",
          resolve_enum("A and B combined", enum_option_map(opts)) is None)
    check("enum: unknown letter never resolves",
          resolve_enum("D: something new", enum_option_map(opts)) is None)
    # Without options, behavior is byte-identical to the old path.
    r_old = resolve_majority([
        {"agent": "a", "decision": "A", "confidence": 0.4},
        {"agent": "b", "decision": "A: full text", "confidence": 0.4},
        {"agent": "c", "decision": "B", "confidence": 0.9},
    ])
    check("no-options path unchanged (documents the old limitation)",
          r_old["rule"] == "highest_confidence_no_majority")

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
