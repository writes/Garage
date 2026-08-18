# Gate receipt — waves U2′–U4′ (Underhood structural world), code head `f276c71`

**Branch:** `feat/underhood-u2-u4-structure` · **Base:** `main@130a71c` · **Date:** 2026-08-18

## Provenance

Two rival Cursor-agent implementations of the same waves were pushed 2026-08-18 (13:40Z /
13:41Z), both cut from `main@130a71c`:

- **A** `cursor/full-underhood-design-ab-f0de` — 5-tab IA, new `AppTab` identities
  `record`/`handover`.
- **B** `cursor/underhood-design-waves-u2-u4-c84c` — 4-tab IA repurposing the `.stats` slot.

**Selection was decided by the FROZEN arm manifest** (2026-08-12 vote session), not a new vote:
§2.1 fixes the tab count at 5 with the Record and Handover slots (A conforms; B violates), §4
requires identical accessibility identifiers (B renames `garage.*`→`bay.*`) and full
reachability (B's Gallery/Wheels tiles were dead buttons), §3 requires identical event streams
(B logs Handover visits as `stats` screen views). Branch A was integrated and hardened; branch
B was NOT merged — its two genuinely better mechanics (in-stack chrome, reactive pack
normalization) were grafted onto A. B's journey lane was adapted (it passed the arm-forcing
lever as a launch ARGUMENT; the lever reads the process ENVIRONMENT, so B's journeys could
never have forced the arm).

## Gate evidence (all at the code head, REAL exits)

| Run | policy-checks | security-checks | verify-ios | Notes |
|---|---|---|---|---|
| post-integration | 0 | 0 | 0 | 1,149 unit tests / 163 suites (1 known issue = tracked badge AA miss) + **35 journeys** incl. the new 5-test `UnderhoodDesignJourneyTests` lane (arm forced via `launchEnvironment`) |
| post round-2 remediation | 0 | 0 | 0 | same suites, regen-equality green |
| post round-3 remediation (f276c71) | 0 | 0 | 0 | same suites, regen-equality green |

Intermediate honest failures on the way: 3 compile errors (Swift-6 isolation in
`ServiceLightPill.Severity`, missing `Foundation` import + `#expect` inference in
`DesignStructureTests`), one 300-line-cap breach, five strict-lint violations
(`identifier_name` on `ok`, `line_length`, `file_length`/`type_body_length` ×2) — each fixed
and re-run to green.

## Review record (tri_review, 3 rounds)

- **R1** (`2026-08-18T15-07-50Z`): GO / NO-GO(Sol ×5) / GO → **all five Sol blockers verified
  REAL and fixed** (S1 attention-slice bay tiles → full `maintenanceRoster`; S2 stale
  cross-vehicle render → loading gate; S3 negative "MI OVER" + odometer-date claim → guards +
  honest copy; S4 stranded sheet flows → router-hosted Settings + literally-pushed
  `StatsContent`; S5 event-stream + copy + Logbook cost-delta → parity events, factual
  subtitle, cost dropped).
- **R2** (`2026-08-18T15-53-23Z`): GO / NO-GO(Sol ×5) / GO → **all five verified REAL and
  fixed** (N1 Stats route outside the gate + `screenViewed(.stats)` on push; N2 honest-empty
  progress bars + owner's-manual disclaimer; N3 warranty/fuel badges + loading-blanked source
  line; N4 router sheets dismissed on de-auth; N5 embedded export artifacts discarded on tab
  switch-away) plus a control-pixel guard on the Log/Garage background paints.
- **R3** (`2026-08-18T16-36-08Z`): GO / NO-GO(Sol) / DEGENERATE(gemini, known payload
  ceiling). Sol's remaining blockers are **scope/process, not code**: (1) tile tap-through +
  dossier preview — NOT in the frozen manifest (§2.5 "tile grid presentation, derivations from
  EXISTING data only"; §2.8 "same export engine, same outputs"); queued as U-wave/Phase-3
  candidates requiring a manifest amendment; (2) HANDOFF staleness — the write-last ritual,
  performed with this receipt; (3) missing head-bound gate receipt — THIS DOCUMENT (the gate
  cannot run inside Sol's read-only sandbox; it ran here, exits above).

Per the tri-review non-convergence doctrine (memory `tri-review-nonconvergence`): once code
findings are exhausted, reruns regenerate process-meta blockers — the merge proceeds on the
operator's explicit instruction, recorded in `DECISION_LEDGER.jsonl` tied to this head.

## Accepted residue / queued follow-ups

- Sheet-replacement UX: a follow-on present (export/paywall) from the Settings sheet REPLACES
  it (single router host); dismissing the replacement does not restore Settings. Documented
  trade-off vs stranded flows.
- Kill-path cosmetic: a variant-only Settings sheet stays presented (dismissible, renders the
  same SettingsView control ships) if the emergency kill fires while it is open. Queued: auto
  dismiss on pack swap.
- `formOpened(.export)` / `screenViewed(.settings)` per-visit cadence vs control's per-present
  cadence — semantic parity chosen over mechanical identity; flagged for the frozen
  exploratory interaction map at Phase 3.
- Queued (Phase 3 / U-wave polish): bay-tile tap-through, dossier preview decision (manifest
  amendment), kill-switch journey lane, artifact-cleanup lifecycle tests, per-arm release-mode
  verification, registry×arm reachability matrix, deep-link selectedTab sweep.
