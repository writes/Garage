#!/usr/bin/env python3
"""session_handoff.py — thin cross-agent state CLI (Organ III).

HANDOFF.md is the read-first / written-last surface that makes session death a
non-event. This tool rewrites ONLY the marker-delimited regions, so the static
pointer sections a human maintains are never clobbered. The LOG is trimmed to
the most recent ~12 entries (history lives in the deep-state surfaces it points to).

Commands:
  session_handoff.py --status                 print HANDOFF.md (what the SessionStart hook shows)
  session_handoff.py --init                   create HANDOFF.md from template if absent
  session_handoff.py update --by AGENT --summary "..." --next "..." \\
       [--blocked "..."] [--contention "..."] [--runtime "..."] [--inflight "..."]
"""
from __future__ import annotations

import argparse
import datetime
import os
import re
import subprocess
import sys

_FALLBACK_ROOT = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
try:
    _root_probe = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=10
    )
except (subprocess.TimeoutExpired, OSError):
    ROOT = _FALLBACK_ROOT
else:
    ROOT = _root_probe.stdout.strip() if _root_probe.returncode == 0 else _FALLBACK_ROOT
ROOT = ROOT or _FALLBACK_ROOT
HANDOFF = os.path.join(ROOT, "HANDOFF.md")

CUR_START, CUR_END = "<!--CURRENT:START-->", "<!--CURRENT:END-->"
LOG_START, LOG_END = "<!--LOG:START-->", "<!--LOG:END-->"
MAX_LOG = 12

TEMPLATE = f"""# HANDOFF — cross-agent session state (read first; update before ending)

{CUR_START}
## CURRENT STATE
- updated: (uninitialized)
- runtime: (unknown)
- last session did: (none)
- in-flight (uncommitted/partial): none
- BLOCKED / operator-gated: none
- ⚠ contention / landmines: none
- ▶ **NEXT ACTION**: (set me)
{CUR_END}

## WHERE THE DEEP STATE LIVES (pointers — do not duplicate content here)
- Doctrine + compact state: `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`
- Living blueprint: `docs/ai/MACHINE_BRAIN_BLUEPRINT.md`
- Verdict/kill DB: `docs/research-assay/audit/REGISTRY.md`
- Cross-session memory: `~/.claude/projects/-Users-jt-Code-AppDev/memory/MEMORY.md`
- Decision votes: `DECISION_LEDGER.jsonl`

## LOG (newest first; keep ~12)
{LOG_START}
{LOG_END}
"""


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _git(*args: str) -> str:
    """Run a bounded git read command and return stdout or raise RuntimeError."""
    try:
        proc = subprocess.run(
            ["git", *args], capture_output=True, text=True, cwd=ROOT, timeout=30
        )
    except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
        raise RuntimeError(f"git {' '.join(args[:2])}: {exc}") from exc
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip()
        raise RuntimeError(f"git {' '.join(args[:2])} failed: {detail}")
    return proc.stdout.strip()


def _read() -> str:
    if not os.path.exists(HANDOFF):
        return TEMPLATE
    with open(HANDOFF, encoding="utf-8") as fh:
        return fh.read()


def _write(text: str) -> None:
    with open(HANDOFF, "w", encoding="utf-8") as fh:
        fh.write(text)


def _replace_block(text: str, start: str, end: str, body: str) -> str:
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.DOTALL)
    repl = f"{start}\n{body}\n{end}"
    if pattern.search(text):
        return pattern.sub(lambda _: repl, text, count=1)
    return text + "\n" + repl + "\n"


def cmd_status() -> int:
    sys.stdout.write(_read())
    return 0


def cmd_init() -> int:
    if os.path.exists(HANDOFF):
        sys.stderr.write(f"HANDOFF.md already exists at {HANDOFF}; left untouched.\n")
        return 0
    _write(TEMPLATE)
    sys.stderr.write(f"created {HANDOFF}\n")
    return 0


def cmd_update(args) -> int:
    text = _read()
    branch = _git("rev-parse", "--abbrev-ref", "HEAD") or "?"
    sha = _git("rev-parse", "--short", "HEAD") or "?"
    now = _now()

    current = (
        "## CURRENT STATE\n"
        f"- updated: {now} by **{args.by}** on `{branch}` @ `{sha}`\n"
        f"- runtime: {args.runtime or '(unchanged)'}\n"
        f"- last session did: {args.summary}\n"
        f"- in-flight (uncommitted/partial): {args.inflight or 'none'}\n"
        f"- BLOCKED / operator-gated: {args.blocked or 'none'}\n"
        f"- ⚠ contention / landmines: {args.contention or 'none'}\n"
        f"- ▶ **NEXT ACTION**: {args.next}"
    )
    text = _replace_block(text, CUR_START, CUR_END, current)

    # Prepend a LOG line, then trim to MAX_LOG.
    m = re.search(re.escape(LOG_START) + r"(.*?)" + re.escape(LOG_END), text, re.DOTALL)
    existing = [ln for ln in (m.group(1).strip().splitlines() if m else []) if ln.strip()]
    new_line = f"- {now} **{args.by}** @`{sha}`: {args.summary}  — NEXT: {args.next}"
    lines = [new_line] + existing
    lines = lines[:MAX_LOG]
    text = _replace_block(text, LOG_START, LOG_END, "\n".join(lines))

    _write(text)
    sys.stderr.write(f"updated {HANDOFF} (LOG kept {len(lines)} entries)\n")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Thin cross-agent HANDOFF state CLI.")
    ap.add_argument("--status", action="store_true")
    ap.add_argument("--init", action="store_true")
    sub = ap.add_subparsers(dest="cmd")
    up = sub.add_parser("update")
    up.add_argument("--by", required=True)
    up.add_argument("--summary", required=True)
    up.add_argument("--next", required=True)
    up.add_argument("--blocked", default="")
    up.add_argument("--contention", default="")
    up.add_argument("--runtime", default="")
    up.add_argument("--inflight", default="")
    args = ap.parse_args(argv)

    if args.status:
        return cmd_status()
    if args.init:
        return cmd_init()
    if args.cmd == "update":
        if not os.path.exists(HANDOFF):
            cmd_init()
        return cmd_update(args)
    ap.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
