#!/usr/bin/env python3
"""dual_agent_loop.py — Organ II (Looping / Autonomy), "the motor".

This harness implements Organ II's canonical cycle:

        plan(Claude)  ->  implement(Codex)  ->  review(Claude)

repeated for N iterations, with every turn executed *inside a dedicated git
worktree* so the loop NEVER mutates the user's working tree. After each
implement step we run scope_guard.enforce() on the worktree, which silently
reverts out-of-scope writes and HALTS the loop (for human review) if any
protected file was touched.

Division of labour (and why):
  * PLAN     — `claude -p`. Claude reads the goal + the prior REVIEW.md and
               writes a concrete PLAN.md for this iteration.
  * IMPLEMENT— `codex exec -`. The plan is fed to Codex on STDIN and Codex
               edits files in the worktree.
  * ENFORCE  — scope_guard.enforce(): the domain fence. Out-of-scope writes
               are reverted; protected writes halt the loop.
  * REVIEW   — `claude -p`. Claude inspects the diff and writes REVIEW.md
               with a verdict line. "DONE" stops the loop early.
  * GATE     — optionally run scripts/ci/verify-ios.sh (the *sole promoter*,
               an immutable deterministic gate) and record pass/fail.

The loop only ever produces *candidates* in an isolated branch. It DOES NOT
auto-merge to the base branch — promotion to the user's branch is a human
gate. The CI scripts under scripts/ci/ remain the sole promoter of merit.

------------------------------------------------------------------------------
LANDMINES handled here (learned the hard way):
  * `codex exec` with no stdin HANGS forever. We ALWAYS pipe the prompt to
    stdin and bound the call with a subprocess timeout.
  * Every external process call has an explicit timeout — nothing runs
    unbounded.
  * Rate limits (HTTP 429 / "rate" text) get brief exponential backoff,
    honouring CLAUDE_CODE_MAX_RETRIES if the environment sets it.
  * Concurrency law: exactly ONE codex track runs at a time. Serial only.
    Never spawn two implement steps concurrently.
------------------------------------------------------------------------------

CLI:
  python3 dual_agent_loop.py --goal "..." [--iterations 3] [--branch-prefix brain/loop]
                             [--base <branch>] [--gate] [--dry-run]
  python3 dual_agent_loop.py --goal-file GOAL.txt ...

Cleanup (human, after inspecting the worktree):
  git worktree remove <worktree-path>
  git branch -D <branch>          # if you decide to discard the candidate
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

# Import the sibling scope guard regardless of the caller's cwd.
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)
import scope_guard  # noqa: E402  (intentional: sibling import after path tweak)

# ---------------------------------------------------------------------------
# Tunables / defaults
# ---------------------------------------------------------------------------
DEFAULT_ITERATIONS = 3
DEFAULT_BRANCH_PREFIX = "brain/loop"
SCRATCH_ROOT = os.path.join(_SCRIPT_DIR, "..", "..", ".brain-worktrees")

# Per-call timeouts (seconds). Agent calls get a generous bound; git is fast.
PLAN_TIMEOUT = 1800
IMPLEMENT_TIMEOUT = 3600
REVIEW_TIMEOUT = 1800
GATE_TIMEOUT = 3600
GIT_TIMEOUT = 120

GATE_SCRIPT = "scripts/ci/verify-ios.sh"  # the immutable promotion gate

# Default retry budget for rate-limit backoff (overridable by env).
DEFAULT_MAX_RETRIES = 4

# Verdict tokens we look for in REVIEW.md (first match wins, case-insensitive).
_DONE_RE = re.compile(r"\b(DONE|COMPLETE|SHIP\s*IT|APPROVED)\b", re.IGNORECASE)
_CONTINUE_RE = re.compile(r"\b(CONTINUE|ITERATE|NOT\s*DONE|REVISE)\b", re.IGNORECASE)
_RATE_RE = re.compile(r"\b(429|rate.?limit|too many requests|overloaded)\b", re.IGNORECASE)


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _max_retries() -> int:
    raw = os.environ.get("CLAUDE_CODE_MAX_RETRIES")
    if raw:
        try:
            return max(0, int(raw))
        except ValueError:
            pass
    return DEFAULT_MAX_RETRIES


# ---------------------------------------------------------------------------
# Subprocess helpers — every call is bounded and rate-aware.
# ---------------------------------------------------------------------------
class StepResult:
    """Outcome of one external call."""

    def __init__(self, ok: bool, stdout: str, stderr: str, code: int, note: str = ""):
        self.ok = ok
        self.stdout = stdout
        self.stderr = stderr
        self.code = code
        self.note = note

    def __repr__(self) -> str:  # pragma: no cover - debug aid
        return f"StepResult(ok={self.ok}, code={self.code}, note={self.note!r})"


def _run(
    cmd: List[str],
    *,
    cwd: Optional[str] = None,
    stdin_text: Optional[str] = None,
    timeout: int,
    label: str,
) -> StepResult:
    """Run a command with a hard timeout and rate-limit backoff.

    stdin_text, when given, is fed on STDIN (this is how we avoid the
    `codex exec` hang — there is ALWAYS something on stdin for it).
    """
    attempts = _max_retries() + 1
    last: StepResult = StepResult(False, "", "never ran", -1, "no attempts")
    for attempt in range(1, attempts + 1):
        try:
            proc = subprocess.run(
                cmd,
                cwd=cwd,
                input=stdin_text,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            return StepResult(False, "", "", -1, f"{label}: TIMEOUT after {timeout}s")
        except FileNotFoundError as exc:
            return StepResult(False, "", str(exc), -1, f"{label}: command not found ({cmd[0]})")

        combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
        rate_limited = proc.returncode != 0 and bool(_RATE_RE.search(combined))
        if rate_limited and attempt < attempts:
            backoff = min(60, 2 ** attempt)
            print(f"  [{label}] rate-limited (attempt {attempt}/{attempts}); "
                  f"backing off {backoff}s")
            time.sleep(backoff)
            last = StepResult(False, proc.stdout, proc.stderr, proc.returncode, "rate-limited")
            continue

        ok = proc.returncode == 0
        return StepResult(ok, proc.stdout, proc.stderr, proc.returncode,
                          "" if ok else f"{label}: exit {proc.returncode}")
    return last


def _git(repo: str, *args: str) -> StepResult:
    return _run(["git", "-C", repo, *args], timeout=GIT_TIMEOUT, label=f"git {args[0]}")


# ---------------------------------------------------------------------------
# Worktree lifecycle
# ---------------------------------------------------------------------------
def _current_branch(repo: str) -> str:
    res = _git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    return res.stdout.strip() if res.ok else "HEAD"


def create_worktree(repo: str, base: str, branch: str, dry_run: bool) -> str:
    """Create a fresh worktree on a new branch under the scratch root.

    Returns the absolute worktree path. In dry-run we still create it, so the
    rest of the loop (and scope_guard) is genuinely exercised.
    """
    os.makedirs(SCRATCH_ROOT, exist_ok=True)
    slug = branch.replace("/", "-")
    worktree = os.path.abspath(os.path.join(SCRATCH_ROOT, slug))
    if os.path.exists(worktree):
        # Stale path from a prior run — refuse to clobber; make it unique.
        worktree = f"{worktree}-{int(time.time())}"

    cmd = ["worktree", "add", "-b", branch, worktree, base]
    print(f"  $ git -C {repo} {' '.join(cmd)}")
    res = _git(repo, *cmd)
    if not res.ok:
        raise RuntimeError(f"git worktree add failed: {res.stderr.strip() or res.note}")
    return worktree


def cleanup_hint(repo: str, worktree: str, branch: str) -> str:
    return (
        "To clean up (after you have inspected/merged the candidate):\n"
        f"  git -C {repo} worktree remove {worktree}\n"
        f"  git -C {repo} branch -D {branch}   # only if discarding the candidate"
    )


# ---------------------------------------------------------------------------
# Prompt construction
# ---------------------------------------------------------------------------
def _plan_prompt(goal: str, prior_review: str, iteration: int) -> str:
    prior = prior_review.strip() or "(none — this is the first iteration)"
    return (
        "You are the PLAN stage of an autonomous dual-agent build loop.\n"
        f"Iteration: {iteration}\n\n"
        "GOAL:\n"
        f"{goal}\n\n"
        "PRIOR REVIEW (address every point still open):\n"
        f"{prior}\n\n"
        "Write a concrete, minimal implementation plan for THIS iteration. "
        "Stay strictly inside allowed candidate paths (Garage/Features, "
        "Garage/Design, Garage/Core, Tests/, CloudFunctions/src/). Never touch "
        "secrets, signing, CI, firebase config, or the Xcode project. Output the "
        "plan as a numbered task list with the exact files to change."
    )


def _implement_prompt(goal: str, plan: str) -> str:
    return (
        "You are the IMPLEMENT stage of an autonomous dual-agent build loop.\n"
        "Apply the following plan by editing files in this repository. Make the "
        "smallest correct change. Do NOT edit secrets, signing, CI scripts, "
        "firebase config, or the Xcode project; stay within allowed candidate "
        "paths.\n\n"
        f"GOAL:\n{goal}\n\n"
        f"PLAN:\n{plan}\n"
    )


def _review_prompt(goal: str, plan: str, diff: str) -> str:
    return (
        "You are the REVIEW stage of an autonomous dual-agent build loop.\n"
        "Judge whether the implemented diff satisfies the goal and plan, is "
        "correct, and is in scope. Then write REVIEW.md.\n\n"
        "End your review with a single verdict line, exactly one of:\n"
        "  VERDICT: DONE        (goal met; stop the loop)\n"
        "  VERDICT: CONTINUE    (more work needed; list what)\n\n"
        f"GOAL:\n{goal}\n\n"
        f"PLAN:\n{plan}\n\n"
        f"DIFF (truncated):\n{diff[:12000]}\n"
    )


# ---------------------------------------------------------------------------
# Agent stages
# ---------------------------------------------------------------------------
def _write(worktree: str, name: str, content: str) -> None:
    with open(os.path.join(worktree, name), "w", encoding="utf-8") as fh:
        fh.write(content)


def _read(worktree: str, name: str) -> str:
    path = os.path.join(worktree, name)
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def stage_plan(worktree: str, goal: str, prior_review: str, iteration: int,
               dry_run: bool) -> str:
    """PLAN — `claude -p`. Returns the plan text and writes PLAN.md."""
    prompt = _plan_prompt(goal, prior_review, iteration)
    cmd = ["claude", "-p", prompt]
    if dry_run:
        print(f"  [DRY-RUN PLAN] would run: claude -p <plan-prompt {len(prompt)} chars>")
        plan = f"# PLAN (dry-run, iter {iteration})\n\nGoal: {goal}\n\n(no agent invoked)\n"
        _write(worktree, "PLAN.md", plan)
        return plan
    res = _run(cmd, cwd=worktree, stdin_text="", timeout=PLAN_TIMEOUT, label="claude/plan")
    plan = res.stdout.strip() or f"(plan stage produced no output; note={res.note})"
    _write(worktree, "PLAN.md", plan)
    return plan


def stage_implement(worktree: str, goal: str, plan: str, dry_run: bool) -> StepResult:
    """IMPLEMENT — `codex exec -` with the plan piped on STDIN.

    CRITICAL: bare `codex exec` with no stdin HANGS. We pass the trailing '-'
    (read prompt from stdin) AND feed stdin_text, AND bound it with a timeout.
    Serial only — exactly one codex track at a time.
    """
    prompt = _implement_prompt(goal, plan)
    cmd = ["codex", "exec", "-"]
    if dry_run:
        print(f"  [DRY-RUN IMPLEMENT] would run: codex exec -  "
              f"(stdin: implement-prompt {len(prompt)} chars)")
        # Simulate a candidate write inside an allowed path so enforce() has
        # something real (and in-scope) to observe.
        feat_dir = os.path.join(worktree, "Garage", "Features", "_BrainLoopDryRun")
        os.makedirs(feat_dir, exist_ok=True)
        with open(os.path.join(feat_dir, "DryRunMarker.swift"), "w", encoding="utf-8") as fh:
            fh.write("// dual_agent_loop dry-run marker — safe to delete\n")
        return StepResult(True, "(dry-run implement)", "", 0)
    return _run(cmd, cwd=worktree, stdin_text=prompt,
                timeout=IMPLEMENT_TIMEOUT, label="codex/implement")


def stage_review(worktree: str, goal: str, plan: str, dry_run: bool) -> Tuple[str, bool]:
    """REVIEW — `claude -p`. Returns (review_text, done_flag); writes REVIEW.md."""
    diff = _git(worktree, "diff", "HEAD").stdout
    prompt = _review_prompt(goal, plan, diff)
    cmd = ["claude", "-p", prompt]
    if dry_run:
        print(f"  [DRY-RUN REVIEW] would run: claude -p <review-prompt {len(prompt)} chars>")
        review = ("# REVIEW (dry-run)\n\nNo agent invoked.\n\nVERDICT: CONTINUE\n")
        _write(worktree, "REVIEW.md", review)
        return review, _verdict_done(review)
    res = _run(cmd, cwd=worktree, stdin_text="", timeout=REVIEW_TIMEOUT, label="claude/review")
    review = res.stdout.strip() or f"(review stage produced no output; note={res.note})\nVERDICT: CONTINUE"
    _write(worktree, "REVIEW.md", review)
    return review, _verdict_done(review)


def _verdict_done(review: str) -> bool:
    """Decide whether the review says DONE.

    Prefer an explicit 'VERDICT:' line; fall back to keyword scan. CONTINUE
    tokens win ties so we never stop early on an ambiguous review.
    """
    for line in review.splitlines():
        if "VERDICT:" in line.upper():
            if _CONTINUE_RE.search(line):
                return False
            if _DONE_RE.search(line):
                return True
    if _CONTINUE_RE.search(review):
        return False
    return bool(_DONE_RE.search(review))


# ---------------------------------------------------------------------------
# Promotion gate (sole promoter — never bypassed, only recorded)
# ---------------------------------------------------------------------------
def run_gate(worktree: str, dry_run: bool) -> Optional[bool]:
    """Run the immutable CI gate; return True/False, or None if skipped."""
    gate_path = os.path.join(worktree, GATE_SCRIPT)
    if not os.path.exists(gate_path):
        print(f"  [gate] {GATE_SCRIPT} not present in worktree; skipping.")
        return None
    if dry_run:
        print(f"  [DRY-RUN GATE] would run: bash {GATE_SCRIPT}")
        return None
    res = _run(["bash", GATE_SCRIPT], cwd=worktree, stdin_text="",
               timeout=GATE_TIMEOUT, label="gate/verify-ios")
    print(f"  [gate] verify-ios.sh -> {'PASS' if res.ok else 'FAIL'}")
    return res.ok


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
def _write_state(worktree: str, state: Dict[str, object]) -> None:
    with open(os.path.join(worktree, "STATE.json"), "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2)
        fh.write("\n")


# ---------------------------------------------------------------------------
# The loop
# ---------------------------------------------------------------------------
def run_loop(
    repo: str,
    goal: str,
    iterations: int,
    branch_prefix: str,
    base: str,
    run_gate_each: bool,
    dry_run: bool,
) -> Dict[str, object]:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    branch = f"{branch_prefix}/{stamp}"
    worktree = create_worktree(repo, base, branch, dry_run)
    print(f"  worktree: {worktree}")
    print(f"  branch:   {branch}  (base: {base})")

    _write(worktree, "GOAL.md", f"# GOAL\n\n{goal}\n")

    state: Dict[str, object] = {
        "goal": goal,
        "base": base,
        "branch": branch,
        "worktree": worktree,
        "started": _now_iso(),
        "iterations_planned": iterations,
        "dry_run": dry_run,
        "iterations": [],
        "halted": False,
        "done": False,
    }

    prior_review = ""
    for i in range(1, iterations + 1):
        print(f"\n--- iteration {i}/{iterations} ---")
        rec: Dict[str, object] = {"iteration": i, "started": _now_iso()}

        # (a) PLAN
        plan = stage_plan(worktree, goal, prior_review, i, dry_run)
        rec["plan_chars"] = len(plan)

        # (b) IMPLEMENT (serial: exactly one codex track)
        impl = stage_implement(worktree, goal, plan, dry_run)
        rec["implement_ok"] = impl.ok
        rec["implement_note"] = impl.note
        if not impl.ok:
            print(f"  implement stage failed: {impl.note}")

        # (c) ENFORCE the domain fence
        enforced = scope_guard.enforce(worktree, revert=True)
        rec["reverted"] = enforced.get("reverted", [])
        rec["protected"] = enforced.get("protected", [])
        if enforced.get("halt"):
            print("  scope_guard halted the loop (protected paths changed).")
            rec["finished"] = _now_iso()
            state["iterations"].append(rec)      # type: ignore[attr-defined]
            state["halted"] = True
            _write_state(worktree, state)
            break

        # (d) REVIEW
        review, done = stage_review(worktree, goal, plan, dry_run)
        prior_review = review
        rec["review_done"] = done

        # (e) GATE (optional; sole promoter, only recorded here)
        if run_gate_each:
            gate = run_gate(worktree, dry_run)
            rec["gate_pass"] = gate

        rec["finished"] = _now_iso()
        state["iterations"].append(rec)          # type: ignore[attr-defined]
        _write_state(worktree, state)

        if done:
            print("  review verdict: DONE — stopping early.")
            state["done"] = True
            break

    state["finished"] = _now_iso()
    _write_state(worktree, state)
    return state


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _load_goal(args: argparse.Namespace) -> str:
    if args.goal_file:
        with open(args.goal_file, encoding="utf-8") as fh:
            return fh.read().strip()
    return (args.goal or "").strip()


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(
        description="Organ II dual-agent loop: plan(Claude) -> implement(Codex) "
                    "-> review(Claude), worktree-isolated and scope-fenced.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("--goal", help="The build goal (natural language).")
    ap.add_argument("--goal-file", help="Read the goal from this file instead.")
    ap.add_argument("--iterations", type=int, default=DEFAULT_ITERATIONS,
                    help="Maximum plan/implement/review cycles.")
    ap.add_argument("--branch-prefix", default=DEFAULT_BRANCH_PREFIX,
                    help="Prefix for the loop's candidate branch.")
    ap.add_argument("--base", default=None,
                    help="Base branch to fork the worktree from (default: current branch).")
    ap.add_argument("--repo", default=".", help="Repository directory.")
    ap.add_argument("--gate", action="store_true",
                    help="Run scripts/ci/verify-ios.sh after each review and record pass/fail.")
    ap.add_argument("--dry-run", action="store_true",
                    help="Print the claude/codex commands instead of running them; still "
                         "creates the worktree and runs scope_guard so it is verifiable.")

    args = ap.parse_args(argv)

    goal = _load_goal(args)
    if not goal:
        ap.error("a goal is required: pass --goal \"...\" or --goal-file PATH")

    repo = os.path.abspath(args.repo)
    base = args.base or _current_branch(repo)

    if not args.dry_run and not shutil.which("git"):
        ap.error("git not found on PATH")

    print("=" * 68)
    print("Organ II — dual-agent loop (plan/implement/review)")
    print("=" * 68)

    try:
        state = run_loop(
            repo=repo,
            goal=goal,
            iterations=args.iterations,
            branch_prefix=args.branch_prefix,
            base=base,
            run_gate_each=args.gate,
            dry_run=args.dry_run,
        )
    except RuntimeError as exc:
        print(f"FATAL: {exc}", file=sys.stderr)
        return 1

    worktree = state["worktree"]            # type: ignore[index]
    branch = state["branch"]                # type: ignore[index]

    # ---- Summary ----------------------------------------------------------
    print("\n" + "=" * 68)
    print("SUMMARY")
    print("-" * 68)
    print(f"  goal        : {goal}")
    print(f"  iterations  : {len(state['iterations'])} run "       # type: ignore[arg-type]
          f"of {args.iterations} planned")
    print(f"  done        : {state['done']}")
    print(f"  halted      : {state['halted']}")
    print(f"  branch      : {branch}")
    print(f"  worktree    : {worktree}")
    print("-" * 68)
    print("  NOT auto-merged — promotion to your branch is a human gate.")
    print("  The immutable CI scripts under scripts/ci/ are the sole promoter.")
    print("-" * 68)
    print(cleanup_hint(repo, worktree, branch))      # type: ignore[arg-type]
    print("=" * 68)

    if state["halted"]:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
