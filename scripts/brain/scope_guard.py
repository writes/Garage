#!/usr/bin/env python3
"""scope_guard.py — the loop's domain fence (Organ II support).

A standalone, stdlib-only classifier + worktree enforcer that keeps an
autonomous plan/implement/review loop inside its sandbox. It answers one
question for every changed file: may an agent have written this?

Three zones (see the repo's DOMAIN SCOPE GUARD doctrine):

  * PROTECTED   — secrets, signing, infra, CI, the Xcode project. An agent
                  must NEVER touch these. A protected change is a *human
                  review event*: we DO NOT auto-revert its content (that
                  could silently destroy a human's deliberate edit), we HALT
                  the loop loudly and hand it to a person.
  * ALLOWED     — feature/design/core code, tests, functions src, reports,
                  results, logs, research docs. Candidate writes live here.
  * PROTOCOL    — loop bookkeeping files (GOAL.md, PLAN.md, STATE.json, …).
                  Always allowed; the loop itself authors them.
  * OUT_OF_SCOPE— anything else. Reverted silently; the loop continues.

The immutable CI gate (scripts/ci/*.sh) remains the *sole promoter*; this
module only fences writes, it never promotes.

CLI:
  python3 scope_guard.py check   [repo]   # report classification of the worktree
  python3 scope_guard.py enforce [repo]   # revert out_of_scope, halt on protected
  python3 scope_guard.py selftest         # built-in unit suite
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Zone definitions (the doctrine, encoded once).
#
# All matching is prefix-based and case-sensitive, against repo-relative
# POSIX paths (forward slashes), exactly as `git status --porcelain` emits.
# ---------------------------------------------------------------------------

# A protected change halts the loop for human review (never auto-reverted).
PROTECTED_PREFIXES: Tuple[str, ...] = (
    "Configuration/Secrets.swift",
    "Garage/Resources/GoogleService-Info.plist",
    "CloudFunctions/.env",
    "firebase.firestore.rules",
    "firebase.storage.rules",
    "firebase.json",
    ".firebaserc",
    "scripts/ci/",
    "Garage.xcodeproj/",
    # project.yml generates Garage.xcodeproj (targets/signing/bundle IDs). Protecting only the
    # generated artifact would be a bypass loophole (edit yml → regenerate). Resolved PROTECTED
    # by unanimous tri-agent consensus 2026-06-29 (DECISION_LEDGER.jsonl, group d09e41f1544ac2e6).
    "project.yml",
)

# Candidate writes are permitted only under these prefixes.
ALLOWED_CANDIDATE_PREFIXES: Tuple[str, ...] = (
    "Garage/Features/",
    "Garage/Design/",
    "Garage/Core/",
    "Tests/",
    "CloudFunctions/src/",
    "reports/",
    "results/",
    "logs/",
    "docs/research/",
)

# Loop bookkeeping. Exact basenames always allowed, plus two glob suffixes.
#
# DECISION_LEDGER.jsonl is deliberately absent.  It is Law-1's durable trust
# anchor, not loop bookkeeping: its only candidate-worktree exception is an
# exact byte append, checked against HEAD by ``_ledger_change_status`` below.
PROTOCOL_FILES: Tuple[str, ...] = (
    "GOAL.md",
    "PLAN.md",
    "PLAN_REVIEW.md",
    "RESULT.md",
    "REVIEW.md",
    "CROSS_CHECK.md",
    "STATE.json",
    "DONE",
    "DECISION.md",
    "RESOLUTION.md",
)
PROTOCOL_GLOB_SUFFIXES: Tuple[str, ...] = (
    "_CASE.md",
    "_ASSESS.md",
)

DECISION_LEDGER_PATH = "DECISION_LEDGER.jsonl"


# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------
def _normalize(path: str) -> str:
    """Normalize to a clean repo-relative POSIX path for prefix matching.

    Strips surrounding quotes/whitespace, collapses backslashes to slashes,
    and drops a leading "./" so "./PLAN.md" classifies the same as "PLAN.md".
    """
    p = path.strip().strip('"')
    p = p.replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return p


def _basename(path: str) -> str:
    return path.rsplit("/", 1)[-1] if "/" in path else path


def classify_change(path: str) -> str:
    """Classify one repo-relative path into a zone.

    Returns one of: "protected", "allowed", "protocol", "out_of_scope".

    Precedence is deliberate and security-first:
      1. protected  — wins over everything (e.g. "scripts/ci/foo.sh").
      2. protocol   — bookkeeping basenames/globs anywhere in the tree.
      3. allowed    — candidate write prefixes.
      4. out_of_scope — the default deny.
    """
    p = _normalize(path)
    if not p:
        return "out_of_scope"

    # 1. Protected always wins — never let a later rule "rescue" a secret.
    for prefix in PROTECTED_PREFIXES:
        if p == prefix or p.startswith(prefix):
            return "protected"

    # 2. Protocol bookkeeping (matched on basename so it works at any depth).
    base = _basename(p)
    if base in PROTOCOL_FILES:
        return "protocol"
    for suffix in PROTOCOL_GLOB_SUFFIXES:
        if base.endswith(suffix):
            return "protocol"

    # 3. Allowed candidate territory.
    for prefix in ALLOWED_CANDIDATE_PREFIXES:
        if p.startswith(prefix):
            return "allowed"

    # 4. Default deny.
    return "out_of_scope"


# ---------------------------------------------------------------------------
# Worktree inspection
# ---------------------------------------------------------------------------
def _git(repo_dir: str, *args: str, check: bool = False) -> subprocess.CompletedProcess:
    """Run a git command in repo_dir with a bounded timeout (never hang)."""
    return subprocess.run(
        ["git", "-C", repo_dir, *args],
        capture_output=True,
        text=True,
        timeout=60,
        check=check,
    )


def _git_bytes(repo_dir: str, *args: str) -> subprocess.CompletedProcess:
    """Run a bounded git command without decoding trust-anchor content."""
    return subprocess.run(
        ["git", "-C", repo_dir, *args],
        capture_output=True,
        timeout=60,
    )


def _ledger_blob(repo_dir: str, revision: str) -> Tuple[Optional[bytes], str]:
    """Read one exact ledger blob, returning a safe diagnostic on failure."""
    object_spec = (
        f":{DECISION_LEDGER_PATH}"
        if revision == ":"
        else f"{revision}:{DECISION_LEDGER_PATH}"
    )
    proc = _git_bytes(repo_dir, "show", object_spec)
    if proc.returncode == 0:
        return proc.stdout, ""
    detail = (proc.stderr or proc.stdout).decode("utf-8", errors="replace").strip()
    return None, detail or f"git show {revision}:{DECISION_LEDGER_PATH} failed"


def _working_ledger_blob(repo_dir: str) -> Tuple[Optional[bytes], str]:
    """Read the worktree ledger without following a possible symlink."""
    path = os.path.join(repo_dir, DECISION_LEDGER_PATH)
    try:
        if os.path.islink(path):
            return None, "ledger path is a symlink"
        with open(path, "rb") as fh:
            return fh.read(), ""
    except FileNotFoundError:
        return None, "ledger path is missing"
    except OSError as exc:
        return None, f"unable to read ledger path: {exc}"


def _ledger_change_status(repo_dir: str) -> Tuple[str, str]:
    """Classify the root ledger as unchanged, append-only, or a violation.

    Both the index and working-tree views are checked.  A staged rewrite could
    otherwise evade a worktree-only comparison and later be committed into the
    Law-1 trust anchor.  Each changed view must be a *strict* byte append to
    the exact HEAD blob; deletion, truncation, mutation, unreadability, and
    missing baseline evidence fail closed.
    """
    baseline, baseline_note = _ledger_blob(repo_dir, "HEAD")
    if baseline is None:
        return "violation", f"unable to read HEAD ledger: {baseline_note}"

    index_blob, index_note = _ledger_blob(repo_dir, ":")
    if index_blob is None:
        return "violation", f"unable to read index ledger: {index_note}"

    worktree_blob, worktree_note = _working_ledger_blob(repo_dir)
    if worktree_blob is None:
        return "violation", worktree_note

    changed = False
    for label, candidate in (("index", index_blob), ("worktree", worktree_blob)):
        if candidate == baseline:
            continue
        changed = True
        if len(candidate) <= len(baseline) or not candidate.startswith(baseline):
            return "violation", f"{label} ledger content is not a strict byte append of HEAD"

    return ("append", "") if changed else ("unchanged", "")


def _parse_porcelain(porcelain: str) -> List[Tuple[str, str]]:
    """Parse `git status --porcelain` output into (xy_status, path) tuples.

    Handles staged/unstaged/added/modified/deleted/renamed/untracked entries.
    For a rename ("R  old -> new") we return the *destination* path, since
    that is the file now present in the worktree that we may need to act on.
    Quoting of unusual paths (git's C-quoting) is stripped best-effort.
    """
    out: List[Tuple[str, str]] = []
    for raw in porcelain.splitlines():
        if not raw.strip():
            continue
        # Porcelain v1: 2 status chars, a space, then the path(s).
        xy = raw[:2]
        rest = raw[3:] if len(raw) > 3 else raw[2:].lstrip()
        if " -> " in rest:  # rename / copy: "old -> new"
            rest = rest.split(" -> ", 1)[1]
        out.append((xy, _normalize(rest)))
    return out


def check_worktree(repo_dir: str) -> Dict[str, object]:
    """Classify every changed path in repo_dir's worktree.

    Returns {protected: [...], out_of_scope: [...], allowed: [...],
             protocol: [...], ledger_appends: [...], ledger_violations: [...],
             ok: bool}.  The DECISION_LEDGER is not protocol: only an exact
             byte append to HEAD is admissible in a candidate worktree.
    """
    proc = _git(repo_dir, "status", "--porcelain")
    if proc.returncode != 0:
        raise RuntimeError(
            f"git status failed in {repo_dir!r}: {proc.stderr.strip() or proc.stdout.strip()}"
        )

    buckets: Dict[str, List[str]] = {
        "protected": [],
        "allowed": [],
        "protocol": [],
        "out_of_scope": [],
    }
    for _xy, path in _parse_porcelain(proc.stdout):
        if not path:
            continue
        # Root-ledger status is handled with byte-level HEAD/index/worktree
        # comparison below.  (The comparison also catches a rename/deletion
        # whose porcelain destination is some other path.)
        if path == DECISION_LEDGER_PATH:
            continue
        buckets[classify_change(path)].append(path)

    ledger_status, ledger_note = _ledger_change_status(repo_dir)
    ledger_appends = [DECISION_LEDGER_PATH] if ledger_status == "append" else []
    ledger_violations = [DECISION_LEDGER_PATH] if ledger_status == "violation" else []

    return {
        "protected": buckets["protected"],
        "out_of_scope": buckets["out_of_scope"],
        "allowed": buckets["allowed"],
        "protocol": buckets["protocol"],
        "ledger_appends": ledger_appends,
        "ledger_violations": ledger_violations,
        "ledger_note": ledger_note,
        "ok": (
            not buckets["protected"]
            and not buckets["out_of_scope"]
            and not ledger_violations
        ),
    }


# ---------------------------------------------------------------------------
# Enforcement
# ---------------------------------------------------------------------------
def _is_tracked(repo_dir: str, path: str) -> bool:
    """True if git already tracks path (so revert == checkout, not clean)."""
    proc = _git(repo_dir, "ls-files", "--error-unmatch", "--", path)
    return proc.returncode == 0


def _revert_path(repo_dir: str, path: str) -> Tuple[bool, str]:
    """Revert a single out-of-scope path.

    Tracked files: `git checkout -- <path>` restores the committed version.
    Untracked files: `git clean -f -- <path>` (also `-d` so empty dirs go).
    Returns (success, human_note).
    """
    if _is_tracked(repo_dir, path):
        proc = _git(repo_dir, "checkout", "--", path)
        verb = "checkout"
    else:
        proc = _git(repo_dir, "clean", "-fd", "--", path)
        verb = "clean"
    if proc.returncode == 0:
        return True, f"reverted ({verb})"
    return False, f"REVERT FAILED ({verb}): {proc.stderr.strip() or proc.stdout.strip()}"


def _restore_ledger_from_head(repo_dir: str) -> Tuple[bool, str]:
    """Restore both index and worktree ledger state to HEAD after a violation."""
    proc = _git(
        repo_dir,
        "restore",
        "--source=HEAD",
        "--staged",
        "--worktree",
        "--",
        DECISION_LEDGER_PATH,
    )
    if proc.returncode == 0:
        return True, "reverted (git restore --source=HEAD --staged --worktree)"
    return False, f"REVERT FAILED (git restore): {proc.stderr.strip() or proc.stdout.strip()}"


def enforce(repo_dir: str, revert: bool = True) -> Dict[str, object]:
    """Fence the worktree, halting on protected or non-append ledger changes.

    Behaviour:
      * out_of_scope changes  -> reverted (if revert=True), loop continues.
      * protected changes     -> NOT reverted. We set halt=True and print a
                                 loud banner; this is a human-review event.
      * ledger rewrite/delete -> restored to HEAD (index and worktree) and
                                 HALTED.  Only byte-prefix appends survive.
      * otherwise             -> ok, nothing to do.

    Returns the check_worktree() dict augmented with:
        reverted: [...], revert_errors: [...], halt: bool.
    Always prints a clear report.
    """
    state = check_worktree(repo_dir)
    protected: List[str] = state["protected"]            # type: ignore[assignment]
    out_of_scope: List[str] = state["out_of_scope"]      # type: ignore[assignment]
    allowed: List[str] = state["allowed"]                # type: ignore[assignment]
    protocol: List[str] = state["protocol"]              # type: ignore[assignment]
    ledger_appends: List[str] = state["ledger_appends"]  # type: ignore[assignment]
    ledger_violations: List[str] = state["ledger_violations"]  # type: ignore[assignment]

    reverted: List[str] = []
    revert_errors: List[str] = []

    if revert:
        for path in out_of_scope:
            ok, note = _revert_path(repo_dir, path)
            if ok:
                reverted.append(path)
            else:
                revert_errors.append(f"{path}: {note}")

    # This is intentionally independent of --no-revert.  That flag is a
    # diagnostic escape hatch for ordinary out-of-scope writes; it must not
    # leave a modified Law-1 trust anchor in a candidate worktree.
    for path in ledger_violations:
        ok, note = _restore_ledger_from_head(repo_dir)
        if ok:
            reverted.append(path)
        else:
            revert_errors.append(f"{path}: {note}")

    halt = bool(protected or ledger_violations)

    # ---- Report -----------------------------------------------------------
    print("=" * 68)
    print(f"scope_guard.enforce — {repo_dir}")
    print("-" * 68)
    print(f"  allowed       : {len(allowed)}")
    print(f"  protocol      : {len(protocol)}")
    print(f"  ledger append : {len(ledger_appends)}")
    for p in ledger_appends:
        print(f"      - {p}  [byte-prefix append allowed]")
    print(f"  out_of_scope  : {len(out_of_scope)}"
          + (f" -> reverted {len(reverted)}" if revert else " (revert disabled)"))
    for p in out_of_scope:
        tag = "reverted" if p in reverted else "left-in-place"
        print(f"      - {p}  [{tag}]")
    for err in revert_errors:
        print(f"      ! {err}")
    if protected:
        print("-" * 68)
        print("  !!! PROTECTED PATHS CHANGED — HALTING FOR HUMAN REVIEW !!!")
        print("  These are NOT auto-reverted; a human must inspect them:")
        for p in protected:
            print(f"      * {p}")
    if ledger_violations:
        print("-" * 68)
        print("  !!! DECISION LEDGER REWRITE/DELETE — REVERTED AND HALTING !!!")
        print("  Only an exact byte append to the HEAD ledger is permitted:")
        for p in ledger_violations:
            tag = "reverted" if p in reverted else "RESTORE FAILED"
            print(f"      * {p}  [{tag}]")
        ledger_note = state.get("ledger_note")
        if ledger_note:
            print(f"      ! {ledger_note}")
    print("=" * 68)

    state.update({
        "reverted": reverted,
        "revert_errors": revert_errors,
        "halt": halt,
    })
    return state


# ---------------------------------------------------------------------------
# Self-test (classification plus a disposable git fixture for ledger semantics)
# ---------------------------------------------------------------------------
def _selftest() -> int:
    failures: List[str] = []

    def check(name: str, got: str, want: str) -> None:
        if got != want:
            failures.append(name)
            print(f"  FAIL  {name}: got {got!r}, want {want!r}")
        else:
            print(f"  ok    {name} -> {got}")

    def check_bool(name: str, condition: bool) -> None:
        if not condition:
            failures.append(name)
            print(f"  FAIL  {name}")
        else:
            print(f"  ok    {name}")

    cases = [
        # protected
        ("Configuration/Secrets.swift", "protected"),
        ("Garage/Resources/GoogleService-Info.plist", "protected"),
        ("CloudFunctions/.env", "protected"),
        ("firebase.firestore.rules", "protected"),
        ("firebase.storage.rules", "protected"),
        ("firebase.json", "protected"),
        (".firebaserc", "protected"),
        ("scripts/ci/verify-ios.sh", "protected"),
        ("Garage.xcodeproj/project.pbxproj", "protected"),
        # allowed
        ("Garage/Features/Log/LogView.swift", "allowed"),
        ("Garage/Design/Theme.swift", "allowed"),
        ("Garage/Core/Networking/Client.swift", "allowed"),
        ("Tests/LogViewTests.swift", "allowed"),
        ("CloudFunctions/src/index.ts", "allowed"),
        ("reports/run-42.json", "allowed"),
        ("results/metrics.csv", "allowed"),
        ("logs/loop.log", "allowed"),
        ("docs/research/notes.md", "allowed"),
        # protocol
        ("PLAN.md", "protocol"),
        ("PLAN_REVIEW.md", "protocol"),
        ("GOAL.md", "protocol"),
        ("STATE.json", "protocol"),
        ("CROSS_CHECK.md", "protocol"),
        ("DECISION_LEDGER.jsonl", "out_of_scope"),
        ("DONE", "protocol"),
        ("RESOLUTION.md", "protocol"),
        ("./REVIEW.md", "protocol"),
        ("regression_CASE.md", "protocol"),
        ("perf_ASSESS.md", "protocol"),
        # protocol basenames win even nested under an allowed dir
        ("reports/PLAN.md", "protocol"),
        # out_of_scope
        ("random_top_level.txt", "out_of_scope"),
        ("scripts/brain/scope_guard.py", "out_of_scope"),  # brain scripts: not a candidate zone
        ("Garage/OtherStuff/Thing.swift", "out_of_scope"),
        ("Package.swift", "out_of_scope"),
        ("", "out_of_scope"),
    ]
    for path, want in cases:
        check(path or "<empty>", classify_change(path), want)

    # Precedence sanity: protected beats a protocol-looking basename.
    check("scripts/ci/PLAN.md (protected wins)",
          classify_change("scripts/ci/PLAN.md"), "protected")

    # A candidate can append a governed override, but cannot rewrite the
    # durable trust anchor.  Exercise the real index + worktree enforcement
    # path in an isolated git repository so both cases are regression-proof.
    try:
        with tempfile.TemporaryDirectory(prefix="scope-guard-ledger-") as repo:
            subprocess.run(["git", "init", "-q", repo], check=True, timeout=60)
            ledger = os.path.join(repo, DECISION_LEDGER_PATH)
            baseline = b'{"decision":"baseline"}\n'
            with open(ledger, "wb") as fh:
                fh.write(baseline)
            subprocess.run(
                [
                    "git", "-C", repo,
                    "-c", "user.name=scope-guard-selftest",
                    "-c", "user.email=scope-guard-selftest@example.invalid",
                    "add", DECISION_LEDGER_PATH,
                ],
                check=True,
                timeout=60,
            )
            subprocess.run(
                [
                    "git", "-C", repo,
                    "-c", "user.name=scope-guard-selftest",
                    "-c", "user.email=scope-guard-selftest@example.invalid",
                    "commit", "-qm", "ledger fixture",
                ],
                check=True,
                timeout=60,
            )

            append = b'{"decision":"operator override"}\n'
            with open(ledger, "ab") as fh:
                fh.write(append)
            append_state = enforce(repo)
            append_blob, _ = _working_ledger_blob(repo)
            check_bool(
                "ledger pure append passes",
                not append_state["halt"]
                and append_state["ledger_appends"] == [DECISION_LEDGER_PATH]
                and not append_state["ledger_violations"]
                and append_blob == baseline + append,
            )

            with open(ledger, "wb") as fh:
                fh.write(b'{"decision":"mutated historical row"}\n')
            mutation_state = enforce(repo)
            restored_blob, _ = _working_ledger_blob(repo)
            check_bool(
                "ledger mutated line is reverted and halts",
                mutation_state["halt"]
                and mutation_state["ledger_violations"] == [DECISION_LEDGER_PATH]
                and DECISION_LEDGER_PATH in mutation_state["reverted"]
                and restored_blob == baseline,
            )
    except (OSError, subprocess.SubprocessError) as exc:
        check_bool("ledger append/rewrite fixture ran", False)
        print(f"      ! ledger fixture error: {exc}")

    print()
    if failures:
        print(f"SELFTEST FAILED: {len(failures)} failure(s)")
        return 1
    print("SELFTEST PASSED")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _print_check(state: Dict[str, object]) -> None:
    for zone in ("protected", "out_of_scope", "allowed", "protocol"):
        items: List[str] = state.get(zone, [])  # type: ignore[assignment]
        print(f"{zone} ({len(items)}):")
        for p in items:
            print(f"  {p}")
    print(f"ok = {state['ok']}")


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(
        description="Domain scope guard: classify + fence worktree changes."
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    cp = sub.add_parser("check", help="Classify worktree changes (read-only).")
    cp.add_argument("repo", nargs="?", default=".", help="Repo dir (default: cwd).")

    ep = sub.add_parser("enforce", help="Revert out-of-scope; halt on protected.")
    ep.add_argument("repo", nargs="?", default=".", help="Repo dir (default: cwd).")
    ep.add_argument("--no-revert", action="store_true",
                    help="Report only; do not revert out-of-scope files.")

    sub.add_parser("selftest", help="Run the built-in classify_change suite.")

    args = ap.parse_args(argv)

    if args.cmd == "selftest":
        return _selftest()

    repo = os.path.abspath(args.repo)

    if args.cmd == "check":
        state = check_worktree(repo)
        _print_check(state)
        return 0 if state["ok"] else 1

    if args.cmd == "enforce":
        state = enforce(repo, revert=not args.no_revert)
        # Exit codes: 2 = halt (protected), 1 = had out_of_scope, 0 = clean.
        if state["halt"]:
            return 2
        return 0 if not state["out_of_scope"] else 1

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
