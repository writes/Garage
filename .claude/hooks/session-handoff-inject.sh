#!/bin/sh
# SessionStart hook — inject the cross-agent HANDOFF state into every new session
# (Organ III). Stdout from a SessionStart hook is added to the session context, so
# the agent reads "what just happened / what's next / who's touching what" first.
# macOS does not guarantee coreutils `timeout`; Perl's alarm survives exec and
# bounds this read-only Git discovery probe. Optional locks stay disabled too.
ROOT="$(GIT_OPTIONAL_LOCKS=0 /usr/bin/perl -e 'alarm 10; exec @ARGV or exit 127' git rev-parse --show-toplevel 2>/dev/null || pwd)"
HANDOFF_PY="$ROOT/scripts/brain/session_handoff.py"
if [ -f "$HANDOFF_PY" ]; then
  echo "===== HANDOFF (machine-brain Organ III — read first) ====="
  python3 "$HANDOFF_PY" --status 2>/dev/null
  echo "==========================================================="
else
  echo "[session-handoff-inject] $HANDOFF_PY not found; brain not installed?"
fi
