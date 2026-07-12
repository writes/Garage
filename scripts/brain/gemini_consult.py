#!/usr/bin/env python3
"""gemini_consult.py — headless Gemini voter (Organ I).

Backend ladder: agy (Antigravity / AI Ultra)  →  Vertex gemini-2.5-pro (gcloud ADC)
→  GEMINI_API_KEY REST. Emits a single JSON object {decision, reasoning, confidence}
on stdout, plus the backend used on stderr.

LANDMINES honored:
  * #1  Never call `agy models` (it HANGS). We only ever `agy -p "..." --print-timeout`.
  * #2  Always feed input non-interactively + redirect stdin from /dev/null; bound with
        an outer timeout so a hung CLI cannot wedge the whole loop.
  * #3  The free @google/gemini-cli OAuth tier is dead for individuals — not in the ladder.
  * #12 agy silently downgrades unrecognized --model labels. Use only an exact server-roster
        display label and verify its resolver log; never trust model self-report.

Usage:
  python3 gemini_consult.py --prompt-file q.txt [--timeout 120] [--backend auto|agy|vertex|api]
  echo "question..." | python3 gemini_consult.py --timeout 120
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from dataclasses import dataclass
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from typing import Dict, Iterable, Optional, Tuple

# The one canonical model allowlist for every v3 lane.  Callers may read
# BRAIN_* environment variables, but they must compare their effective
# selections against this mapping before invoking a provider.
ROSTER: Dict[str, str] = {
    "claude": "claude-fable-5",
    "codex-strategy": "gpt-5.6-sol",
    "codex-implement": "gpt-5.6-terra",
    "gemini": "Gemini 3.1 Pro (High)",
}

VERTEX_MODEL = "gemini-2.5-pro"
VERTEX_LOCATION = os.environ.get("VERTEX_LOCATION", "us-central1")
AGY_MODEL = os.environ.get("BRAIN_GEMINI_MODEL", ROSTER["gemini"])
AGY_RESOLVER_LABEL_RE = re.compile(
    r'Propagating selected model override to backend:\s*label="([^"]+)"'
)

VOTER_INSTRUCTION = (
    "You are one of three independent LLM voters resolving a decision. Reply with ONLY a "
    "single JSON object, no prose, no code fences:\n"
    '{"decision": "<one of the enumerated options, verbatim>", '
    '"reasoning": "<=60 words citing the strongest evidence>", '
    '"confidence": <float 0..1 calibrated to evidence strength>}\n'
    "Calibrate confidence to EVIDENCE (real verification > docs > intuition). Do not inflate."
)


def roster_deviations(
    effective_models: Dict[str, str], lanes: Optional[Iterable[str]] = None
) -> Dict[str, Dict[str, str]]:
    """Return effective model labels that differ from canonical lane pins.

    Consumers name only the lanes they operate.  Unknown requested lanes are a
    programming error rather than an implicit policy exception; an omitted
    effective lane is reported as an empty effective value and therefore fails
    closed like any other deviation.
    """
    selected_lanes = tuple(ROSTER) if lanes is None else tuple(lanes)
    unknown = [lane for lane in selected_lanes if lane not in ROSTER]
    if unknown:
        raise ValueError(f"unknown roster lane(s): {', '.join(unknown)}")
    return {
        lane: {"expected": ROSTER[lane], "effective": effective_models.get(lane, "")}
        for lane in selected_lanes
        if effective_models.get(lane) != ROSTER[lane]
    }


def last_agy_resolver_label(log_text: Optional[str]) -> Optional[str]:
    """Extract the final agy backend resolver label from already-read log text."""
    if log_text is None:
        return None
    labels = AGY_RESOLVER_LABEL_RE.findall(log_text)
    return labels[-1] if labels else None


def gemini_resolver_decision(
    log_bytes: Optional[bytes], start_offset: Optional[int], pinned_model: str
) -> Tuple[bool, str]:
    """Fail closed unless a caller-selected resolver byte region matches.

    This pure helper knows only bytes and an offset. ``verify_agy_resolver``
    first decides whether the original real target/inode survived: it passes
    zero for replacement/truncated targets and the old size only for a growing
    same-inode target. Parsing only that region prevents an older successful
    resolver record from verifying a later invocation. Every invalid input
    remains an unverified mismatch.
    """
    if (
        log_bytes is None
        or not isinstance(start_offset, int)
        or isinstance(start_offset, bool)
        or start_offset < 0
    ):
        return False, "unverified"
    # agy can rotate/truncate cli.log between capture and verification. A
    # smaller file cannot contain pre-call bytes, so its complete content is
    # the fresh region associated with this call.
    effective_offset = 0 if len(log_bytes) < start_offset else start_offset
    appended_text = log_bytes[effective_offset:].decode("utf-8", errors="replace")
    observed = last_agy_resolver_label(appended_text) or "unverified"
    return observed == pinned_model, observed


@dataclass(frozen=True)
class AgyResolverSnapshot:
    """Identity and length of the real resolver target before one agy call."""

    target_path: str
    inode: Optional[int]
    size: int


class AgyResolverLockError(RuntimeError):
    """The resolver-verification lock could not be acquired fail-closed."""


def _agy_resolver_log_path() -> str:
    """Return the resolver log path, allowing deterministic deployment overrides."""
    return os.environ.get(
        "BRAIN_AGY_RESOLVER_LOG",
        os.path.expanduser("~/.gemini/antigravity-cli/cli.log"),
    )


def _agy_lock_timeout() -> float:
    """Return the bounded resolver-lock wait, defaulting safely to 120 seconds."""
    raw = os.environ.get("BRAIN_AGY_LOCK_TIMEOUT")
    if raw is None:
        return 120.0
    try:
        return max(0.0, float(raw))
    except ValueError:
        return 120.0


def _agy_lock_paths() -> Tuple[str, ...]:
    """Return the configured lock path followed by the safe temp fallback."""
    configured = os.environ.get("BRAIN_AGY_LOCK")
    # cli.log is itself a symlink; put the default lock in the real per-run
    # log directory, which remains stable across its cli-*.log rotations.
    log_dir = os.path.dirname(os.path.realpath(_agy_resolver_log_path()))
    primary = configured or os.path.join(log_dir, ".brain-agy.lock")
    fallback = os.path.join(tempfile.gettempdir(), ".brain-agy.lock")
    return (primary,) if os.path.abspath(primary) == os.path.abspath(fallback) else (primary, fallback)


@contextmanager
def agy_resolver_lock():
    """Serialize every resolver-verified agy call across processes.

    The lock spans the pre-call resolver capture, agy subprocess, resolver
    verification, and reply parsing. Its default lives alongside the resolver
    log; when that directory cannot be written, a temp-directory fallback
    provides the same cross-process advisory lock. Failure to establish either
    lock is fail-closed rather than allowing one lane to bind another lane's
    resolver line.
    """
    fd: Optional[int] = None
    errors = []
    deadline = time.monotonic() + _agy_lock_timeout()
    for candidate in _agy_lock_paths():
        try:
            fd = os.open(candidate, os.O_CREAT | os.O_RDWR, 0o600)
        except OSError as exc:
            errors.append(f"{candidate}: {exc}")
            continue

        # A usable primary lock must not fall through to the fallback merely
        # because another process holds it. That would create two independent
        # lock domains and let resolver evidence cross lanes. Instead retry a
        # non-blocking flock until the monotonic deadline, then fail closed.
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    os.close(fd)
                    raise AgyResolverLockError("agy lock timeout")
                time.sleep(min(0.1, remaining))
            except OSError as exc:
                errors.append(f"{candidate}: {exc}")
                os.close(fd)
                fd = None
                break
        if fd is not None:
            break
    if fd is None:
        raise AgyResolverLockError("unable to acquire agy resolver lock; " + "; ".join(errors))
    try:
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def capture_agy_resolver_offset() -> Optional[AgyResolverSnapshot]:
    """Capture the real resolver target identity immediately before an agy call.

    ``cli.log`` is a symlink that agy may repoint to a fresh per-run file. The
    target pathname, inode, and byte size are all required to distinguish a
    larger replacement target from appended bytes on the original target. A
    not-yet-created target is represented by a zero-length, no-inode snapshot;
    other stat failures stay unverified rather than guessing.
    """
    target_path = os.path.realpath(_agy_resolver_log_path())
    try:
        stat = os.stat(target_path)
        return AgyResolverSnapshot(target_path, stat.st_ino, stat.st_size)
    except FileNotFoundError:
        return AgyResolverSnapshot(target_path, None, 0)
    except OSError:
        return None


def verify_agy_resolver(
    pinned_model: str, start_snapshot: Optional[AgyResolverSnapshot]
) -> Tuple[bool, str]:
    """Verify resolver evidence bound to one agy invocation, fail-closed.

    After agy returns we resolve ``cli.log`` again. A replacement target path
    or inode is parsed in full even if it is larger than the prior offset;
    a same-inode target is parsed only when it grew. A same-inode truncated
    target is parsed in full because all its bytes are fresh relative to the
    captured offset. Crucially, an unchanged target at the same byte size has
    no fresh resolver record and therefore fails closed; reparsing that whole
    file could bind this invocation to a stale earlier record. Unreadable or
    malformed evidence remains an ``unverified`` mismatch.
    """
    if not isinstance(start_snapshot, AgyResolverSnapshot):
        return False, "unverified"
    target_path = os.path.realpath(_agy_resolver_log_path())
    try:
        stat = os.stat(target_path)
        with open(target_path, "rb") as handle:
            log_bytes = handle.read()
    except OSError:
        return False, "unverified"

    replaced = (
        target_path != start_snapshot.target_path
        or stat.st_ino != start_snapshot.inode
    )
    if replaced:
        offset = 0
    elif stat.st_size > start_snapshot.size:
        offset = start_snapshot.size
    elif stat.st_size == start_snapshot.size:
        return False, "unverified: no fresh resolver record"
    else:
        offset = 0
    return gemini_resolver_decision(log_bytes, offset, pinned_model)


def _extract_json(text: str) -> Optional[Dict]:
    """Pull the first balanced JSON object out of a possibly-noisy model reply."""
    if not text:
        return None
    # Strip code fences if present.
    text = re.sub(r"```(?:json)?", "", text)
    depth = 0
    start = -1
    for i, ch in enumerate(text):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                blob = text[start : i + 1]
                try:
                    return json.loads(blob)
                except json.JSONDecodeError:
                    start = -1
                    continue
    return None


def _normalize(obj: Dict, backend: str, agy_model: str = AGY_MODEL) -> Dict:
    decision = obj.get("decision", obj.get("vote", ""))
    reasoning = obj.get("reasoning", obj.get("rationale", ""))
    try:
        confidence = float(obj.get("confidence", 0.5))
    except (TypeError, ValueError):
        confidence = 0.5
    confidence = max(0.0, min(1.0, confidence))
    return {
        "agent": "gemini",
        "decision": str(decision).strip(),
        "reasoning": str(reasoning).strip(),
        "confidence": confidence,
        "backend": backend,
        "model": agy_model if backend == "agy" else VERTEX_MODEL,
    }


def try_agy(
    prompt: str, timeout: int, model: Optional[str] = None
) -> Tuple[Optional[str], str]:
    """Preferred backend. NEVER `agy models`. Always -p + --print-timeout + stdin /dev/null.

    The caller must hold ``agy_resolver_lock`` and capture resolver identity
    before launching this subprocess, then verify and parse before releasing
    that lock.

    DS-5 (2026-07-12): the prompt travels as an argv element, visible in `ps`
    to every local process while agy runs. agy has no stdin/prompt-file mode
    (landmine #2: it must not read stdin at all), so argv visibility is an
    accepted residual for NON-secret text on this single-user machine — but
    secrets are screened fail-closed here so a credential can never reach a
    process listing.
    """
    from secret_screen import secret_scan  # local sibling; deferred import avoids cycles
    hits = secret_scan(prompt)
    if hits:
        return None, f"agy blocked: prompt tripped secret screen ({', '.join(hits)})"
    cmd = ["agy", "--sandbox"]
    if model:
        cmd.extend(["--model", model])
    cmd.extend(["-p", prompt, "--print-timeout", f"{timeout}s"])
    try:
        proc = subprocess.run(
            cmd,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout + 15,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return None, f"agy unavailable/timeout: {e}"
    if proc.returncode != 0:
        return None, f"agy rc={proc.returncode}: {proc.stderr.strip()[:200]}"
    return proc.stdout, "agy"


def try_vertex(prompt: str, timeout: int) -> Tuple[Optional[str], str, Optional[int]]:
    project = os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("GCLOUD_PROJECT")
    if not project:
        try:
            project = subprocess.run(
                ["gcloud", "config", "get-value", "project"],
                capture_output=True, text=True, timeout=15,
            ).stdout.strip()
        except Exception:
            project = ""
    if not project:
        return None, "vertex: no GCP project configured", None
    try:
        token = subprocess.run(
            ["gcloud", "auth", "print-access-token"],
            capture_output=True, text=True, timeout=20,
        ).stdout.strip()
    except Exception as e:
        return None, f"vertex: no ADC token ({e})", None
    if not token:
        return None, "vertex: empty access token", None
    import urllib.request

    url = (
        f"https://{VERTEX_LOCATION}-aiplatform.googleapis.com/v1/projects/{project}"
        f"/locations/{VERTEX_LOCATION}/publishers/google/models/{VERTEX_MODEL}:generateContent"
    )
    body = json.dumps({"contents": [{"role": "user", "parts": [{"text": prompt}]}]}).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode())
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        return text, "vertex", None
    except Exception as e:
        return None, f"vertex error: {e}", None


def try_api(prompt: str, timeout: int) -> Tuple[Optional[str], str, Optional[int]]:
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        return None, "api: no GEMINI_API_KEY", None
    import urllib.request

    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/{VERTEX_MODEL}:generateContent"
        f"?key={key}"
    )
    body = json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode())
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        return text, "api", None
    except Exception as e:
        return None, f"api error: {e}", None


def consult(
    prompt: str,
    timeout: int = 120,
    backend: str = "auto",
    model: Optional[str] = None,
) -> Dict:
    """Consult Gemini, pinning agy to AGY_MODEL unless a caller overrides it.

    The Vertex/API fallbacks intentionally remain in their separate
    gemini-2.5-pro namespace; a fallback must never masquerade as agy's
    strategic model label.
    """
    full = VOTER_INSTRUCTION + "\n\n=== DECISION ===\n" + prompt
    agy_model = AGY_MODEL if model is None else model
    notes = []

    if backend in ("auto", "agy"):
        try:
            # Do not release this cross-process lock until the reply has also
            # been parsed. Otherwise a second agy lane could rotate the
            # symlink and make this lane validate the wrong resolver line.
            with agy_resolver_lock():
                resolver_snapshot = capture_agy_resolver_offset()
                text, used = try_agy(full, timeout, model=agy_model)
                if text is None:
                    notes.append(used)
                else:
                    model_verified, resolver_label = verify_agy_resolver(
                        agy_model or AGY_MODEL, resolver_snapshot
                    )
                    if not model_verified:
                        return {
                            "agent": "gemini",
                            "decision": "",
                            "reasoning": "",
                            "confidence": 0.0,
                            "backend": "agy",
                            "model": agy_model or AGY_MODEL,
                            "model_verified": False,
                            "resolver_label": resolver_label,
                            "error": f"agy model downgrade detected (observed: {resolver_label})",
                            "backend_notes": notes,
                        }
                    obj = _extract_json(text)
                    if obj is None:
                        notes.append("agy: no JSON in reply")
                    else:
                        result = _normalize(obj, "agy", agy_model or AGY_MODEL)
                        result["model_verified"] = True
                        result["resolver_label"] = resolver_label
                        result["backend_notes"] = notes
                        return result
        except AgyResolverLockError as exc:
            notes.append(f"agy resolver lock unavailable: {exc}")

        if backend == "agy":
            return {
                "agent": "gemini",
                "decision": "",
                "reasoning": "",
                "confidence": 0.0,
                "backend": "none",
                "model": "",
                "model_verified": False,
                "error": "all backends failed",
                "backend_notes": notes,
            }

    ladder = {"vertex": [try_vertex], "api": [try_api]}.get(
        backend, [try_vertex, try_api]
    )
    for fn in ladder:
        text, used, _ = fn(full, timeout)
        if text is None:
            notes.append(used)
            continue
        obj = _extract_json(text)
        if obj is None:
            notes.append(f"{used}: no JSON in reply")
            continue
        result = _normalize(obj, used, agy_model or AGY_MODEL)
        # Vertex/API name the model in their request URL, so no separate local
        # resolver is involved in verifying those fallback lanes.
        result["model_verified"] = True
        result["backend_notes"] = notes
        return result

    return {
        "agent": "gemini",
        "decision": "",
        "reasoning": "",
        "confidence": 0.0,
        "backend": "none",
        "model": "",
        "model_verified": False,
        "error": "all backends failed",
        "backend_notes": notes,
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Headless Gemini voter (agy→Vertex→API).")
    ap.add_argument("--prompt-file", help="File containing the decision prompt.")
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument("--backend", choices=["auto", "agy", "vertex", "api"], default="auto")
    args = ap.parse_args(argv)

    if args.prompt_file:
        with open(args.prompt_file, encoding="utf-8") as fh:
            prompt = fh.read()
    else:
        prompt = sys.stdin.read()
    if not prompt.strip():
        print("error: empty prompt", file=sys.stderr)
        return 2

    result = consult(prompt, timeout=args.timeout, backend=args.backend)
    print(f"# gemini backend: {result.get('backend')}  notes={result.get('backend_notes')}",
          file=sys.stderr)
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("backend") != "none" else 1


if __name__ == "__main__":
    raise SystemExit(main())
