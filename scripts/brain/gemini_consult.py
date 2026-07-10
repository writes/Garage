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
import json
import os
import re
import subprocess
import sys
from typing import Dict, Optional, Tuple

VERTEX_MODEL = "gemini-2.5-pro"
VERTEX_LOCATION = os.environ.get("VERTEX_LOCATION", "us-central1")
AGY_MODEL = os.environ.get("BRAIN_GEMINI_MODEL", "Gemini 3.1 Pro (High)")

VOTER_INSTRUCTION = (
    "You are one of three independent LLM voters resolving a decision. Reply with ONLY a "
    "single JSON object, no prose, no code fences:\n"
    '{"decision": "<one of the enumerated options, verbatim>", '
    '"reasoning": "<=60 words citing the strongest evidence>", '
    '"confidence": <float 0..1 calibrated to evidence strength>}\n'
    "Calibrate confidence to EVIDENCE (real verification > docs > intuition). Do not inflate."
)


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


def try_agy(prompt: str, timeout: int, model: Optional[str] = None) -> Tuple[Optional[str], str]:
    """Preferred backend. NEVER `agy models`. Always -p + --print-timeout + stdin /dev/null."""
    cmd = ["agy"]
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


def try_vertex(prompt: str, timeout: int) -> Tuple[Optional[str], str]:
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
        return None, "vertex: no GCP project configured"
    try:
        token = subprocess.run(
            ["gcloud", "auth", "print-access-token"],
            capture_output=True, text=True, timeout=20,
        ).stdout.strip()
    except Exception as e:
        return None, f"vertex: no ADC token ({e})"
    if not token:
        return None, "vertex: empty access token"
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
        return text, "vertex"
    except Exception as e:
        return None, f"vertex error: {e}"


def try_api(prompt: str, timeout: int) -> Tuple[Optional[str], str]:
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        return None, "api: no GEMINI_API_KEY"
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
        return text, "api"
    except Exception as e:
        return None, f"api error: {e}"


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
    ladder = {
        "auto": [lambda p, t: try_agy(p, t, model=agy_model), try_vertex, try_api],
        "agy": [lambda p, t: try_agy(p, t, model=agy_model)],
        "vertex": [try_vertex],
        "api": [try_api],
    }[backend]

    notes = []
    for fn in ladder:
        text, used = fn(full, timeout)
        if text is None:
            notes.append(used)
            continue
        obj = _extract_json(text)
        if obj is None:
            notes.append(f"{used}: no JSON in reply")
            continue
        result = _normalize(obj, used, agy_model or AGY_MODEL)
        result["backend_notes"] = notes
        return result

    return {
        "agent": "gemini",
        "decision": "",
        "reasoning": "",
        "confidence": 0.0,
        "backend": "none",
        "model": "",
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
