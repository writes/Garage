#!/bin/sh
# SessionStart hook — inject the cross-agent HANDOFF state into every new session
# (Organ III). Stdout from a SessionStart hook is added to the session context, so
# the agent reads "what just happened / what's next / who's touching what" first.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HANDOFF_PY="$ROOT/scripts/brain/session_handoff.py"
if [ -f "$HANDOFF_PY" ]; then
  echo "===== HANDOFF (machine-brain Organ III — read first) ====="
  python3 "$HANDOFF_PY" --status 2>/dev/null
  echo "==========================================================="
else
  echo "[session-handoff-inject] $HANDOFF_PY not found; brain not installed?"
fi
