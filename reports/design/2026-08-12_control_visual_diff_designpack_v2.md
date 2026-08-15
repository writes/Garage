# Control before/after visual diff — DesignPack v2 engine (parity-contract evidence)

Requirement source: master plan §6.3 parity contract + tri-review finding B5 ("control-identical
rendering is unproved"). Executed 2026-08-12 by an isolated agent in a worktree; nothing here
was produced by the branch under review.

## Verdict: CONTROL-IDENTICAL — byte-identical screenshots

Build A = pre-refactor main `76e1033` · Build B = engine head `da0b861` (the code-identical
predecessor of the reviewed head — later commits on the branch are docs/ledger only).
iPhone 17 Pro simulator, iOS 26.5, light appearance, status bar frozen (9:41), demo bootstrap
(`LOCAL_DEMO_MODE` + `UI_TEST_PRO`), installed-binary hash verified against the build under
test before every capture run (landmine #9).

Every screen's PNG is **SHA-256 identical** across the two builds (0 of 18.98M pixels differ):

| screen | SHA-256 (identical for A and B) |
|---|---|
| 01-dashboard | `2361ef06c26e70b2` |
| 02-log | `c5af759715da6617` |
| 03-garage | `a36b4b8a9689d51b` |
| 04-stats | `5e04544365da7c95` |
| 05-settings | `c1da74e6c96cef09` |
| 06-login | `0dc5be23c22c90d8` |
| 07-theme-marine (Pro accent picker) | `d6b39eafbba274b9` |
| 08-dashboard-marine (explicit accent applied) | `159bfd647abce0a6` |

(First 16 hex chars shown; full hashes + PNGs + amplified diff images in the session artifact
directory `visual-diff/` — shots-A-FULL/, shots-B-FULL/, diffs/.)

Screens 07/08 exercise the rewritten `AccentStore.explicitScheme` path (explicit Marine pick)
on both builds — also byte-identical.

## Instrument validity

- **Noise floor:** two runs of the SAME build differ by exactly 6,452 px/screen, always inside
  the home-indicator strip (bbox 387,2583–819,2598; auto-hide raced). A-vs-B is zero
  INCLUDING that strip.
- **Positive control:** same build, Classic vs explicit Marine accent → 23,232 px differ
  (accent surfaces: FAB, tab selection, badges). A genuine restyle registers 3.6× above the
  noise floor, so a zero here is meaningful.

## Coverage matrix — §6.3's full grid (iPhone+iPad × light+dark)

Second pass, same instrument: Build A `76e1033` vs Build B `0603038` (the final CODE head —
adds the corner-set chamfer hook and the explicit-accent fix, and, via rebase, main's #82
bundle-kill). Six core screens per configuration; installed-binary hash verified per run.

| configuration | A-vs-B differing px | verdict |
|---|---|---|
| iPhone 17 Pro — light | 189,476 (all in 05-settings) | identical except the #82 row (below) |
| iPhone 17 Pro — dark | 189,454 (all in 05-settings) | identical except the #82 row |
| iPad Pro 13" — light | 223,467 (222,834 in 05-settings) | identical except the #82 row + ±1-LSB iPad jitter |
| iPad Pro 13" — dark | 222,722 (all in 05-settings) | identical except the #82 row |

**The single differing region is NOT the engine.** Build B's rebase carries main's `a86808e`
(#82: the bundle records the operator's epoch-1 kill), and `ExperimentStore.isSurveyAvailable`
correctly returns false for a killed definition — Settings' "Design Feedback" survey row drops
out and the rows below shift up. Proof by isolation: the pre-rebase engine head `da0b861`
(same engine code, no #82) is **byte-identical to `76e1033` on every screen in every
configuration**. The engine deltas (chamfer hook, explicit-accent fix) produce zero pixels of
change — the chamfer's `RoundedRectangle` branch is what control renders (chamfer 0).

Per-device noise floors: iPhone same-build rerun = exactly 0 px; iPad same-build rerun = ≤620
px/screen at max channel delta 1 (compatibility-mode compositing jitter — the app is
iPhone-family and renders scaled on iPad), with identical bboxes to the matrix's non-Settings
sprinkle, fully accounting for it.

## Carried finding (Phase-3 input)

`DesignPackStore.apply(arm:)` is called only on the `.production` bootstrap branch
(GarageApp.swift); `.localDemo`/`.uiTest` return early, so demo always renders the default
control pack. This diff therefore proves the full token-resolution engine (every `Theme.*` read
at B resolves through the pack) but does NOT exercise arm selection — Phase 3's per-arm journey
lanes need an explicit pack-forcing lever, not the demo bootstrap.
