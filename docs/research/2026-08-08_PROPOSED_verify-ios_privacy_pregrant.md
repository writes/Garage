# PROPOSED (operator-gated): simctl privacy pre-grant in verify-ios.sh

`scripts/ci/verify-ios.sh` is a PROTECTED surface, so this change is drafted here for the
operator to apply — not applied by an agent.

## Problem

The consent-voice journey (`Tests/UITests/Journeys/AIConsentJourneyTests.swift`) exercises the
real speech recognizer, which raises the system speech/microphone permission alerts. The
documented residual (2026-08-04 session): the real-recognizer + terminate sequence can
non-deterministically restart the iPad test runner — no app crash, but a flaked journey run.
Pre-granting the privacy services to the app bundle removes the system alerts from the run
entirely, which is the mitigation candidate recorded in machine memory
(`xcuitest-ipad-compat-traps`).

## Proposed patch

In `scripts/ci/verify-ios.sh`, inside the `if [[ -n "${SIMULATOR_NAME}" ]]; then` branch,
immediately BEFORE the test `xcodebuild` invocation:

```bash
  # Pre-grant mic/speech privacy to the app so the consent-voice journey never races the system
  # permission alerts (residual flake: real-recognizer + terminate can restart the iPad runner).
  # Local test builds run the Debug bundle id. `boot` is idempotent-ish: already-booted is fine.
  xcrun simctl boot "${SIMULATOR_NAME}" 2>/dev/null || true
  xcrun simctl privacy "${SIMULATOR_NAME}" grant microphone com.writes.harrysplayhouse.debug || true
  # Speech recognition is not a distinct simctl privacy service on all Xcode versions; `all`
  # covers it where supported. Non-fatal on failure — the journey's own retry copes as today.
  xcrun simctl privacy "${SIMULATOR_NAME}" grant all com.writes.harrysplayhouse.debug || true
```

## Notes for review

- `simctl privacy` addresses devices by name or UDID; the gate already selects
  `SIMULATOR_NAME`. If two devices share the name, switch the selection to capture the UDID
  (the `sed` in the gate already matches it) — happy to draft that variant on request.
- The grants are `|| true` on purpose: this is a flake mitigation, not a correctness gate, and
  a simctl version that rejects a service name must not fail the whole gate.
- The same three lines (with the non-debug bundle id if applicable) would belong in any CI
  workflow that runs the journeys on a fresh simulator.
- Verification after applying: run the gate twice on an iPad destination and confirm the
  consent-voice journey no longer shows the runner-restart signature in the result bundle.
