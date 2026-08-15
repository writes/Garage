# Gate receipt — feat/underhood-u1-tokens

Final head `d911960` (single squashed commit; this receipt + HANDOFF are the only later
commits, docs-only). GitHub Actions remains down account-wide (billing) — the deterministic
local gate is the promoter. Real exits (script's own $?):

| gate | exit |
|---|---|
| policy-checks | **0** |
| security-checks | **0** |
| verify-ios (build + regen-equality + lint + unit + journeys + archive) | **0** |

Tallies: unit **1146/1146** in 162 suites **with exactly 1 known issue** (the pinned badge AA
miss, `withKnownIssue`); journeys 30/30; swiftlint --strict clean. Two prior gate runs failed
honestly (a `Comment` type mismatch, then a 141-char line) and are captured in the session log.

## Review chain
1. Implementation agent's own verification: mutations M1–M8 all caught (M4/M6/M7 at PIXEL level
   via the new RenderProbe); measured 19-pairing contrast matrix.
2. Gemini 3.7 Flash (High) — machine delegate lane, resolver-verified: NONE ×2.
3. **GPT-5.6 Sol read-only adversarial cross-check: 7 findings** → F1 (conditional tab-chrome
   branches would tear down the tab subtree on a live kill) FIXED value-parameterized; F2
   (secondary button silently bolded by the arm's bold ramp — concept bolds only `.primary`)
   FIXED `.regular` + pinned; F4 (AA miss pinned as a passing contract) FIXED via
   `withKnownIssue`; F7 (FAB glyph unpinned) FIXED. F3 (secondary fill/label/border-colour
   fidelity), F5 (composited state-matrix contrast), F6-remainder (view-wiring enforcement =
   Phase-3 snapshots; UIAppearance proxy staleness on live kill documented in-code) → U2'/
   Phase-3 debt, recorded in HANDOFF next-steps.
4. Gemini 3.1 Pro (High) — repo pin, resolver-verified: 2 findings → the primary-button-border
   claim REFUTED by mutation M7's pixel evidence (control edge distance ≤1 enforced); the
   appearance-proxy claim = Sol F6(d), documented (cosmetic residue on emergency kill only).
