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
from gemini_consult import _extract_json, consult as gemini_consult  # noqa: E402

CLAUDE_MODEL = os.environ.get("BRAIN_CLAUDE_MODEL", "claude-fable-5")
CODEX_STRATEGY_MODEL = os.environ.get("BRAIN_CODEX_STRATEGY_MODEL", "gpt-5.6-sol")
GEMINI_MODEL = os.environ.get("BRAIN_GEMINI_MODEL", "Gemini 3.1 Pro (High)")
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
        "--allow-degraded",
        action="store_true",
        help="Permit a documented 2-voter ledger append when a pinned voter is dead; otherwise non-dry-run appends require all three.",
    )
    args = ap.parse_args(argv)

    prompt = build_prompt(args.question, args.options)
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
    if degraded:
        extra["degradation_note"] = (
            f"only {len(live)}/{len(PINNED_VOTERS)} pinned voters were live and schema-valid; resolved with documented caveat")

    if args.dry_run:
        resolution = consensus.resolve_majority(live)
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
        ledger_path=args.ledger, extra=extra,
    )
    print(json.dumps({"resolution": resolution, "positions": live, "extra": extra},
                     indent=2, ensure_ascii=False))
    sys.stderr.write(f"# appended resolved decision to {args.ledger}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
