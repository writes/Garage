#!/usr/bin/env python3
"""process_sentinel.py — Organ V guardrail: detect leaked long-running LLM/build processes.

WHY (operator directive 2026-07-12, landmine #14): provider CLI processes (codex exec, agy,
claude -p) and xcodebuild runners can hang silently — observed in the wild: a 44h silent
codex mine in the trading repo, a 12h48m Terra pass, stale xcodebuild PIDs restarting UI
runners, and agy invocations that produced empty output while consuming a slot. A hung LLM
process burns quota/tokens invisibly and stalls the lane it occupies. Every orchestrator
session must SWEEP at start and before/after unattended runs.

DISCIPLINE:
  - Detect and REPORT; never auto-kill by default. Cross-session processes (another live
    claude session's children) are CONTENTION, not garbage — surface them, don't touch them.
  - `--kill-orphans` kills ONLY true orphans: matched processes whose parent is dead
    (reparented to launchd, ppid==1). Everything else is report-only.
  - Thresholds are per-class defaults, env-overridable (SENTINEL_<CLASS>_MAX_MIN).

Usage:
  python3 scripts/brain/process_sentinel.py            # report; exit 1 if leaks suspected
  python3 scripts/brain/process_sentinel.py --json     # machine-readable report
  python3 scripts/brain/process_sentinel.py --kill-orphans   # also reap true orphans
  python3 scripts/brain/process_sentinel.py selftest   # unit checks (pure functions)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
from typing import Any, Dict, List, Optional

# Process classes: (name, command-regex, default max age minutes).
# Ages are deliberately generous — the sentinel flags *suspected* leaks for a human/orchestrator
# verdict; it is not a hard timeout (spawn sites must carry their own timeouts — landmine #2).
CLASSES = [
    ("codex", re.compile(r"codex (exec|proto)\b"), 180),
    ("agy", re.compile(r"\bagy\b(?!.*grep)"), 30),
    ("claude_p", re.compile(r"\bclaude\b.* (-p|--print)\b"), 60),
    ("xcodebuild", re.compile(r"\bxcodebuild\b"), 120),
    ("xctrunner", re.compile(r"xctrunner|XCTestDevices"), 120),
]

_ETIME_RE = re.compile(r"^(?:(?P<days>\d+)-)?(?:(?P<hours>\d+):)?(?P<mins>\d+):(?P<secs>\d+)$")


def parse_etime_minutes(etime: str) -> Optional[float]:
    """Parse ps etime ([[dd-]hh:]mm:ss) into minutes. Returns None on no-match."""
    m = _ETIME_RE.match(etime.strip())
    if not m:
        return None
    days = int(m.group("days") or 0)
    hours = int(m.group("hours") or 0)
    mins = int(m.group("mins"))
    secs = int(m.group("secs"))
    return days * 1440 + hours * 60 + mins + secs / 60.0


def classify(command: str) -> Optional[str]:
    """Return the first matching class name for a command line, else None."""
    for name, pattern, _ in CLASSES:
        if pattern.search(command):
            return name
    return None


def threshold_minutes(class_name: str) -> float:
    default = next(d for n, _, d in CLASSES if n == class_name)
    env = os.environ.get(f"SENTINEL_{class_name.upper()}_MAX_MIN")
    try:
        return float(env) if env else float(default)
    except ValueError:
        return float(default)


def evaluate(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Pure: classify + age-check pre-parsed process rows.

    rows: [{pid, ppid, etime, command}] -> suspected leaks with class/age/threshold/orphan.
    """
    suspects: List[Dict[str, Any]] = []
    for row in rows:
        cls = classify(row.get("command", ""))
        if cls is None:
            continue
        age = parse_etime_minutes(str(row.get("etime", "")))
        if age is None:
            continue
        limit = threshold_minutes(cls)
        if age >= limit:
            suspects.append({
                "pid": int(row["pid"]),
                "ppid": int(row["ppid"]),
                "class": cls,
                "age_minutes": round(age, 1),
                "threshold_minutes": limit,
                "orphan": int(row["ppid"]) == 1,
                "command": row.get("command", "")[:200],
            })
    return suspects


def snapshot() -> List[Dict[str, Any]]:
    out = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,etime=,command="],
        capture_output=True, text=True, timeout=15,
    ).stdout
    rows = []
    for line in out.splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) == 4:
            rows.append({"pid": parts[0], "ppid": parts[1], "etime": parts[2], "command": parts[3]})
    return rows


def _selftest() -> int:
    failures = []

    def check(name, cond):
        print(("  ok    " if cond else "  FAIL  ") + name)
        if not cond:
            failures.append(name)

    check("etime mm:ss", parse_etime_minutes("12:30") == 12.5)
    check("etime hh:mm:ss", parse_etime_minutes("01:00:00") == 60.0)
    check("etime dd-hh:mm:ss", parse_etime_minutes("1-00:00:00") == 1440.0)
    check("etime garbage -> None", parse_etime_minutes("n/a") is None)
    check("classify codex exec", classify("codex exec -m gpt-5.6-terra -") == "codex")
    check("classify agy", classify("agy -p 'x' --print-timeout 60s") == "agy")
    check("classify claude -p", classify("claude --model x -p 'hi'") == "claude_p")
    check("classify xcodebuild", classify("xcodebuild -project G.xcodeproj test") == "xcodebuild")
    check("interactive claude NOT matched", classify("claude") is None)
    check("desktop app NOT matched", classify("/Applications/Claude.app/Contents/MacOS/Claude") is None)
    suspects = evaluate([
        {"pid": "10", "ppid": "1", "etime": "13:00:00", "command": "codex exec -m gpt-5.6-terra -"},
        {"pid": "11", "ppid": "9", "etime": "02:00", "command": "codex exec -m gpt-5.6-sol -"},
        {"pid": "12", "ppid": "9", "etime": "45:00", "command": "agy -p 'vote' --print-timeout 60s"},
    ])
    check("aged codex flagged as orphan", any(s["pid"] == 10 and s["orphan"] for s in suspects))
    check("young codex not flagged", all(s["pid"] != 11 for s in suspects))
    check("aged agy flagged (30m default)", any(s["pid"] == 12 and s["class"] == "agy" for s in suspects))
    print("SELFTEST " + ("PASSED" if not failures else f"FAILED ({len(failures)})"))
    return 0 if not failures else 1


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "selftest":
        return _selftest()
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--kill-orphans", action="store_true",
                    help="SIGTERM matched processes whose parent is dead (ppid==1) — true orphans only")
    args = ap.parse_args()

    suspects = evaluate(snapshot())
    killed = []
    if args.kill_orphans:
        for s in suspects:
            if s["orphan"]:
                try:
                    os.kill(s["pid"], signal.SIGTERM)
                    killed.append(s["pid"])
                except (ProcessLookupError, PermissionError):
                    pass

    report = {"suspected_leaks": suspects, "killed_orphans": killed, "clean": not suspects}
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        if not suspects:
            print("process sentinel: CLEAN — no suspected LLM/build process leaks")
        else:
            print(f"process sentinel: {len(suspects)} SUSPECTED LEAK(S)")
            for s in suspects:
                tag = " [ORPHAN]" if s["orphan"] else " [cross-session — do NOT kill blindly]"
                print(f"  pid {s['pid']} {s['class']} age {s['age_minutes']}m "
                      f"(limit {s['threshold_minutes']}m){tag}\n    {s['command']}")
            if killed:
                print(f"  reaped orphans: {killed}")
            print("  action: verify each against its owning session (HANDOFF/contention rules) before killing.")
    return 0 if not suspects else 1


if __name__ == "__main__":
    sys.exit(main())
