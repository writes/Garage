#!/usr/bin/env python3
"""tri_agent_vote.py — run a live tri-agent consensus and append the ledger (Organ I).

Poses ONE enumerated question to three INDEPENDENT voters in parallel:
  * claude  — Fable 5 (`claude -p --model claude-fable-5`)
  * codex   — GPT-5.6 Sol on STDIN (bare `codex exec` w/o stdin HANGS — landmine #2)
  * gemini  — Gemini 3.1 Pro (High), via gemini_consult.py
               (agy only for votes; TV2 forbids Vertex/API fallback votes)

Each emits {decision, reasoning, confidence}; we resolve by 2/3 majority (no veto)
via consensus.py and append one row to DECISION_LEDGER.jsonl.

The three providers are SEPARATE rate pools, so they may run concurrently (landmine #4).

Usage:
  python3 tri_agent_vote.py --question "..." --options "A: ...|B: ..." \\
      --timestamp 2026-06-29T12:00:00Z [--timeout 150] [--voters claude,codex,gemini] \\
      [--dry-run] [--allow-degraded]
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List, Optional

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import consensus  # noqa: E402  (local sibling)
from secret_screen import redact_secret_content, secret_scan  # noqa: E402  (DS-5)
from gemini_consult import (  # noqa: E402
    ROSTER,
    _extract_json,
    consult as gemini_consult,
    roster_deviations as _shared_roster_deviations,
)

CLAUDE_MODEL = os.environ.get("BRAIN_CLAUDE_MODEL", ROSTER["claude"])
CODEX_STRATEGY_MODEL = os.environ.get("BRAIN_CODEX_STRATEGY_MODEL", ROSTER["codex-strategy"])
GEMINI_MODEL = os.environ.get("BRAIN_GEMINI_MODEL", ROSTER["gemini"])
VOTER_ROSTER_LANES = ("claude", "codex-strategy", "gemini")
PINNED_VOTERS = {
    "claude": {"model": CLAUDE_MODEL, "backend": "claude"},
    "codex": {"model": CODEX_STRATEGY_MODEL, "backend": "codex"},
    "gemini": {"model": GEMINI_MODEL, "backend": "agy"},
}

VOTER_INSTRUCTION = (
    "You are ONE of three independent LLM voters resolving a decision. Think, then reply with "
    "ONLY a single JSON object (no prose, no code fences):\n"
    '{"decision":"<one enumerated option, verbatim>","reasoning":"<=60 words, cite evidence>",'
    '"confidence":<float 0..1 calibrated to EVIDENCE strength; do not inflate>}'
)


def build_prompt(question: str, options: str) -> str:
    opts = "\n".join(f"  - {o.strip()}" for o in options.split("|") if o.strip())
    return f"{VOTER_INSTRUCTION}\n\n=== QUESTION ===\n{question}\n\n=== OPTIONS ===\n{opts}\n"


def _run(
    cmd: List[str], stdin_text: Optional[str], timeout: int, cwd: Optional[str] = None
) -> Optional[str]:
    try:
        proc = subprocess.run(
            cmd,
            input=stdin_text if stdin_text is not None else None,
            stdin=None if stdin_text is not None else subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=cwd,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return None
    if proc.returncode != 0 and not proc.stdout.strip():
        sys.stderr.write(f"# {cmd[0]} rc={proc.returncode}: {proc.stderr.strip()[:200]}\n")
        return None
    return proc.stdout


def _run_in_empty_cwd(cmd: List[str], stdin_text: Optional[str], timeout: int) -> Optional[str]:
    """Run one vote in a fresh, non-repository cwd and remove it afterwards."""
    isolated_cwd = tempfile.mkdtemp(prefix="tri-agent-vote-")
    try:
        return _run(cmd, stdin_text=stdin_text, timeout=timeout, cwd=isolated_cwd)
    finally:
        shutil.rmtree(isolated_cwd, ignore_errors=True)


def vote_claude(prompt: str, timeout: int) -> Dict:
    out = _run_in_empty_cwd(
        ["claude", "-p", "--model", CLAUDE_MODEL, "--tools", ""],
        stdin_text=prompt,
        timeout=timeout,
    )
    result = _parse("claude", out)
    result["model"] = CLAUDE_MODEL
    result["backend"] = "claude"
    return result


def vote_codex(prompt: str, timeout: int) -> Dict:
    # codex exec MUST receive the prompt on stdin (landmine #2). The empty
    # cwd deliberately contains no repository evidence, so skip trust preflight.
    out = _run_in_empty_cwd(
        [
            "codex", "exec", "--skip-git-repo-check", "-s", "read-only",
            "-m", CODEX_STRATEGY_MODEL, "-",
        ],
        stdin_text=prompt,
        timeout=timeout,
    )
    result = _parse("codex", out)
    result["model"] = CODEX_STRATEGY_MODEL
    result["backend"] = "codex"
    return result


def vote_gemini(prompt: str, timeout: int) -> Dict:
    # TV2 (unanimous): the generic consult ladder remains useful to non-vote
    # callers, but a Vertex/API fallback is a dead voter and cannot influence
    # a Law-1 ledger row. Request agy directly and still defensively reject a
    # non-agy result should this wrapper ever change.
    res = gemini_consult(prompt, timeout=timeout, backend="agy", model=GEMINI_MODEL)
    backend = res.get("backend", "none")
    model = res.get("model", "")
    if backend != "agy":
        return {
            "agent": "gemini",
            "decision": "",
            "reasoning": "",
            "confidence": 0.0,
            "backend": backend,
            "model": model,
            "error": f"gemini fallback model ({model or 'unknown'}) is not the pinned voter",
        }
    try:
        confidence = float(res.get("confidence", 0.0))
    except (TypeError, ValueError):
        confidence = 0.0
    return {
        "agent": "gemini",
        "decision": res.get("decision", ""),
        "reasoning": res.get("reasoning", ""),
        "confidence": confidence,
        "backend": backend,
        "model": model,
        "model_verified": res.get("model_verified", False),
        **({"error": res["error"]} if res.get("error") else {}),
    }


def _parse(agent: str, out: Optional[str]) -> Dict:
    if not out:
        return {"agent": agent, "decision": "", "reasoning": "", "confidence": 0.0,
                "error": "no output / CLI failed"}
    obj = _extract_json(out)
    if not obj:
        return {"agent": agent, "decision": "", "reasoning": out.strip()[:200],
                "confidence": 0.0, "error": "no JSON in reply"}
    try:
        conf = max(0.0, min(1.0, float(obj.get("confidence", 0.5))))
    except (TypeError, ValueError):
        conf = 0.5
    return {
        "agent": agent,
        "decision": str(obj.get("decision", "")).strip(),
        "reasoning": str(obj.get("reasoning", "")).strip(),
        "confidence": conf,
    }


VOTERS = {"claude": vote_claude, "codex": vote_codex, "gemini": vote_gemini}


def is_live_pinned_voter(position: Dict) -> bool:
    """Require a schema-valid response from its expected pinned voter/backend."""
    agent = position.get("agent")
    expected = PINNED_VOTERS.get(agent)
    if expected is None or position.get("error"):
        return False
    if position.get("model") != expected["model"] or position.get("backend") != expected["backend"]:
        return False
    if not isinstance(position.get("decision"), str) or not position["decision"].strip():
        return False
    if not isinstance(position.get("reasoning"), str):
        return False
    confidence = position.get("confidence")
    if isinstance(confidence, bool) or not isinstance(confidence, (int, float)):
        return False
    if not math.isfinite(float(confidence)) or not 0.0 <= float(confidence) <= 1.0:
        return False
    return agent != "gemini" or position.get("model_verified") is True


def degraded_pair_agrees(positions: List[Dict], options: Optional[List[str]] = None) -> bool:
    """Require exactly two live decisions to share consensus canonical form.

    A degraded 1-1 split cannot use the normal resolver's confidence fallback:
    that would append a single-model choice to the Law-1 ledger. Reusing the
    consensus canonical key preserves its whitespace/case normalization and
    structural collision resistance; when the enumerated option roster is
    supplied, letter-anchored grouping applies (bare "A" == "A: full text").
    """
    if len(positions) != 2:
        return False
    letters = consensus.enum_option_map(options)

    def key(p: Dict) -> str:
        letter = consensus.resolve_enum(p.get("decision"), letters)
        return f"enum:{letter}" if letter is not None else consensus.canonical_key(p.get("decision"))

    return key(positions[0]) == key(positions[1])


def effective_models() -> Dict[str, str]:
    """Return the effective tri-vote model labels using canonical lane names."""
    return {
        "claude": CLAUDE_MODEL,
        "codex-strategy": CODEX_STRATEGY_MODEL,
        "gemini": GEMINI_MODEL,
    }


def roster_deviations() -> Dict[str, Dict[str, str]]:
    """Validate each tri-vote lane against the shared canonical allowlist."""
    return _shared_roster_deviations(effective_models(), lanes=VOTER_ROSTER_LANES)


def _report_roster_deviations(
    deviations: Dict[str, Dict[str, str]], context: str
) -> None:
    print(
        f"error: effective model differs from the pinned {context} roster; "
        "use --allow-env-override to record an explicit exception",
        file=sys.stderr,
    )
    for lane, details in deviations.items():
        print(
            f"  - {lane}: expected {details['expected']!r}; "
            f"effective {details['effective']!r}",
            file=sys.stderr,
        )


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Live tri-agent consensus vote + ledger append.")
    ap.add_argument("--question", required=True)
    ap.add_argument("--options", required=True, help="Pipe-delimited enumerated options, e.g. 'A: ...|B: ...'")
    ap.add_argument("--timestamp", required=True, help="ISO8601 (required; landmine #6).")
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("--voters", default="claude,codex,gemini")
    ap.add_argument("--ledger", default="DECISION_LEDGER.jsonl")
    ap.add_argument("--dry-run", action="store_true", help="Resolve + print; do NOT append the ledger.")
    ap.add_argument(
        "--allow-env-override",
        action="store_true",
        help="Allow effective BRAIN_* model overrides that differ from the pinned roster; record them in the ledger extra.",
    )
    ap.add_argument(
        "--allow-degraded",
        action="store_true",
        help="Permit a documented canonical-agreement 2-voter ledger append when a pinned voter is dead; otherwise non-dry-run appends require all three.",
    )
    args = ap.parse_args(argv)

    model_deviations = roster_deviations()
    if model_deviations and not args.allow_env_override:
        _report_roster_deviations(model_deviations, "tri-agent-vote")
        return 2

    prompt = build_prompt(args.question, args.options)
    # DS-5 fail-closed outbound screen: a vote question/options containing a
    # credential must never reach any provider (or agy's argv — landmine #14
    # sibling). Labels only; never echo matched text.
    outbound_hits = secret_scan(prompt)
    if outbound_hits:
        print(json.dumps({
            "error": "vote blocked: question/options tripped the secret screen",
            "labels": outbound_hits,
        }, indent=2))
        return 2
    chosen = [v.strip() for v in args.voters.split(",") if v.strip() in VOTERS]
    if len(chosen) < 2:
        print("error: need at least 2 voters", file=sys.stderr)
        return 2

    sys.stderr.write(f"# polling {len(chosen)} voters concurrently (separate pools)…\n")
    # Separate provider pools → safe to run concurrently (landmine #4).
    with ThreadPoolExecutor(max_workers=len(chosen)) as ex:
        futs = {ex.submit(VOTERS[v], prompt, args.timeout): v for v in chosen}
        positions = [f.result() for f in futs]

    # Order positions deterministically by voter name for stable output.
    positions.sort(key=lambda p: p["agent"])

    # DS-5 inbound redaction: provider output is untrusted and the ledger is
    # append-only — redact secret-shaped content BEFORE resolution/printing so
    # a prompt-injected credential can never be persisted. Labels are recorded
    # per voter; enum-anchored grouping is unaffected by body redaction.
    for p in positions:
        redaction_labels: List[str] = []
        for field in ("decision", "reasoning"):
            value = p.get(field)
            if isinstance(value, str) and value:
                redacted, labels = redact_secret_content(value)
                if labels:
                    p[field] = redacted
                    redaction_labels.extend(labels)
        if redaction_labels:
            p["redactions"] = sorted(set(redaction_labels))

    live = [p for p in positions if is_live_pinned_voter(p)]

    sys.stderr.write("\n# ── RAW POSITIONS ─────────────────────────────\n")
    for p in positions:
        tag = "OK " if is_live_pinned_voter(p) else "ERR"
        sys.stderr.write(f"#  [{tag}] {p['agent']:<7} conf={p.get('confidence',0):.2f} "
                         f"decision={p.get('decision','')!r} {('('+p['error']+')') if p.get('error') else ''}\n")

    if len(live) < 2:
        print(json.dumps({"error": "fewer than 2 live voters", "positions": positions}, indent=2))
        return 1

    live_names = {p["agent"] for p in live}
    dead_voters = [agent for agent in PINNED_VOTERS if agent not in live_names]
    degraded = bool(dead_voters)
    extra = {
        "degraded": degraded,
        "voters_polled": chosen,
        "voters_live": [p["agent"] for p in live],
    }
    if model_deviations:
        extra["allow_env_override"] = True
        extra["model_roster_deviations"] = model_deviations
    if degraded:
        extra["degradation_note"] = (
            f"only {len(live)}/{len(PINNED_VOTERS)} pinned voters were live and schema-valid; resolved with documented caveat")

    # A degraded pair cannot use consensus.py's normal confidence fallback:
    # without canonical agreement it would elevate one model in a 1-1 split.
    # Enforce this before dry-run too, so no mode presents that split as a
    # valid degraded resolution.
    option_roster = [o.strip() for o in args.options.split("|") if o.strip()]
    if degraded and not degraded_pair_agrees(live, options=option_roster):
        print(json.dumps({
            "error": "degraded pair disagrees - operator decision required",
            "positions": live,
            "extra": extra,
        }, indent=2, ensure_ascii=False))
        sys.stderr.write("# degraded pair disagrees - operator decision required\n")
        return 1

    if args.dry_run:
        resolution = consensus.resolve_majority(live, options=option_roster)
        print(json.dumps({"resolution": resolution, "positions": live, "extra": extra},
                         indent=2, ensure_ascii=False))
        sys.stderr.write("# DRY RUN — ledger NOT written\n")
        return 0

    # TV1 (2/3): a Law-1 vote is not ledger-eligible unless all three pinned
    # voters are live and schema-valid. The explicit degradation switch retains
    # the older 2-voter resolution only with durable caveat metadata.
    if degraded and not args.allow_degraded:
        print(json.dumps({
            "error": "ledger append requires all three pinned voters live and schema-valid",
            "positions": positions,
            "dead_voters": dead_voters,
        }, indent=2, ensure_ascii=False))
        sys.stderr.write("# ledger NOT written — pass --allow-degraded to append a documented degraded vote\n")
        return 1
    if degraded:
        extra["allow_degraded"] = True
        extra["dead_voters"] = dead_voters

    row, resolution = consensus.append_ledger_majority(
        live, topic=args.question, timestamp=args.timestamp,
        ledger_path=args.ledger, extra=extra, options=option_roster,
    )
    print(json.dumps({"resolution": resolution, "positions": live, "extra": extra},
                     indent=2, ensure_ascii=False))
    sys.stderr.write(f"# appended resolved decision to {args.ledger}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
