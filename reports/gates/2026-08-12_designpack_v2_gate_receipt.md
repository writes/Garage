# Gate receipt — feat/designpack-v2-engine

Exact-HEAD receipts for the deterministic local gate (the promoter — GitHub Actions is down
account-wide on a billing failure, operator-owed). Commands run from a clean tree; exit codes
captured as the script's own `$?` (never a pipeline tail's), per the 2026-08-11 false-green
lesson.

## HEAD `2d218e5` (reviewed head; code identical to `da0b861` — subsequent commits are
docs/ledger/brief files only)

Run 2026-08-12 ~20:20–20:45Z:

| gate | command | exit |
|---|---|---|
| policy | `./scripts/ci/policy-checks.sh` | **0** |
| security | `./scripts/ci/security-checks.sh` | **0** |
| verify-ios (build + regen-equality + lint + unit + journeys + archive) | `./scripts/ci/verify-ios.sh` | **0** |

verify-ios tallies (from /tmp/final_gate.log): `Executed 30 tests, with 0 failures` (journey
suite, 916s) · unit target green · swiftlint --strict clean · pbxproj regen-equality inside
the gate.

## Prior code-identical receipts

- `bb706c5` (same code, first branch commit): policy 0 · security 0 · verify-ios **0** —
  1110/1110 unit, 30/30 journeys (929s), lint 0/0.
- B2 fix state (later `c9b6708`): full unit target **1111/1111** on iPhone 17 Pro
  (includes the new `anExplicitClassicChoiceBeatsThePackDefaultAccent`).

## Review chain for this branch

1. Gemini 3.1 Pro (High) read-only cross-check on the full code diff: NONE (resolver-verified).
2. tri_review briefs: 2026-08-12T18-54-43Z (DEGRADED — evidence truncation), 19-10-04Z
   (DEGRADED — Sol lane timeout at 840s; fixed with --timeout 1500), 19-24-53Z (GO/NO-GO/GO —
   Sol blockers B1–B5), 20-35-49Z (GO/NO-GO/GO — Sol process-evidence findings, remediated by
   the commit adding this receipt).
3. B1–B5 remediation: Q2 vote 2026-08-12T19:42:11Z (group 9674af0cd9208c94) · B2 explicit-choice
   fix `c9b6708` · B3/B4 merged to main in PR #81 · B5 = the control visual diff report beside
   this file · A3 bundled-kill merged in PR #82.
