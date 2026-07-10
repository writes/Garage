#!/usr/bin/env python3
"""tri_agent_vote.py — run a live tri-agent consensus and append the ledger (Organ I).

Poses ONE enumerated question to three INDEPENDENT voters in parallel:
  * claude  — Fable 5 (`claude -p --model claude-fable-5`)
  * codex   — GPT-5.6 Sol on STDIN (bare `codex exec` w/o stdin HANGS — landmine #2)
  * gemini  — Gemini 3.1 Pro (High), via gemini_consult.py
               (agy→Vertex→API — landmine #1/#3; fallbacks are visibly recorded)

Each emits {decision, reasoning, confidence}; we resolve by 2/3 majority (no veto)
via consensus.py and append one row to DECISION_LEDGER.jsonl.

The three providers are SEPARATE rate pools, so they may run concurrently (landmine #4).

Usage:
  python3 tri_agent_vote.py --question "..." --options "A: ...|B: ..." \\
      --timestamp 2026-06-29T12:00:00Z [--timeout 150] [--voters claude,codex,gemini] [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List, Optional

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import consensus  # noqa: E402  (local sibling)
from gemini_consult import _extract_json, consult as gemini_consult  # noqa: E402

CLAUDE_MODEL = os.environ.get("BRAIN_CLAUDE_MODEL", "claude-fable-5")
CODEX_STRATEGY_MODEL = os.environ.get("BRAIN_CODEX_STRATEGY_MODEL", "gpt-5.6-sol")
GEMINI_MODEL = os.environ.get("BRAIN_GEMINI_MODEL", "Gemini 3.1 Pro (High)")

VOTER_INSTRUCTION = (
    "You are ONE of three independent LLM voters resolving a decision. Think, then reply with "
    "ONLY a single JSON object (no prose, no code fences):\n"
    '{"decision":"<one enumerated option, verbatim>","reasoning":"<=60 words, cite evidence>",'
    '"confidence":<float 0..1 calibrated to EVIDENCE strength; do not inflate>}'
)


def build_prompt(question: str, options: str) -> str:
    opts = "\n".join(f"  - {o.strip()}" for o in options.split("|") if o.strip())
    return f"{VOTER_INSTRUCTION}\n\n=== QUESTION ===\n{question}\n\n=== OPTIONS ===\n{opts}\n"


def _run(cmd: List[str], stdin_text: Optional[str], timeout: int) -> Optional[str]:
    try:
        proc = subprocess.run(
            cmd,
            input=stdin_text if stdin_text is not None else None,
            stdin=None if stdin_text is not None else subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return None
    if proc.returncode != 0 and not proc.stdout.strip():
        sys.stderr.write(f"# {cmd[0]} rc={proc.returncode}: {proc.stderr.strip()[:200]}\n")
        return None
    return proc.stdout


def vote_claude(prompt: str, timeout: int) -> Dict:
    out = _run(["claude", "-p", "--model", CLAUDE_MODEL, prompt], stdin_text=None, timeout=timeout)
    result = _parse("claude", out)
    result["model"] = CLAUDE_MODEL
    result["backend"] = "claude"
    return result


def vote_codex(prompt: str, timeout: int) -> Dict:
    # codex exec MUST receive the prompt on stdin (landmine #2).
    out = _run(["codex", "exec", "-m", CODEX_STRATEGY_MODEL, "-"], stdin_text=prompt, timeout=timeout)
    result = _parse("codex", out)
    result["model"] = CODEX_STRATEGY_MODEL
    result["backend"] = "codex"
    return result


def vote_gemini(prompt: str, timeout: int) -> Dict:
    res = gemini_consult(prompt, timeout=timeout, backend="auto", model=GEMINI_MODEL)
    return {
        "agent": "gemini",
        "decision": res.get("decision", ""),
        "reasoning": res.get("reasoning", ""),
        "confidence": float(res.get("confidence", 0.0)),
        "backend": res.get("backend"),
        # A non-agy backend is a visibly distinct gemini-2.5-pro fallback,
        # never silently equated with the pinned strategic voter.
        "model": res.get("model", ""),
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


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Live tri-agent consensus vote + ledger append.")
    ap.add_argument("--question", required=True)
    ap.add_argument("--options", required=True, help="Pipe-delimited enumerated options, e.g. 'A: ...|B: ...'")
    ap.add_argument("--timestamp", required=True, help="ISO8601 (required; landmine #6).")
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("--voters", default="claude,codex,gemini")
    ap.add_argument("--ledger", default="DECISION_LEDGER.jsonl")
    ap.add_argument("--dry-run", action="store_true", help="Resolve + print; do NOT append the ledger.")
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
    live = [p for p in positions if p.get("decision") and not p.get("error")]

    sys.stderr.write("\n# ── RAW POSITIONS ─────────────────────────────\n")
    for p in positions:
        tag = "OK " if (p.get("decision") and not p.get("error")) else "ERR"
        sys.stderr.write(f"#  [{tag}] {p['agent']:<7} conf={p.get('confidence',0):.2f} "
                         f"decision={p.get('decision','')!r} {('('+p['error']+')') if p.get('error') else ''}\n")

    if len(live) < 2:
        print(json.dumps({"error": "fewer than 2 live voters", "positions": positions}, indent=2))
        return 1

    degraded = len(live) < len(chosen)
    extra = {"degraded": degraded, "voters_polled": chosen,
             "voters_live": [p["agent"] for p in live]}
    if degraded:
        extra["degradation_note"] = (
            f"only {len(live)}/{len(chosen)} voters returned; resolved with documented caveat")

    if args.dry_run:
        resolution = consensus.resolve_majority(live)
        print(json.dumps({"resolution": resolution, "positions": live, "extra": extra},
                         indent=2, ensure_ascii=False))
        sys.stderr.write("# DRY RUN — ledger NOT written\n")
        return 0

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
