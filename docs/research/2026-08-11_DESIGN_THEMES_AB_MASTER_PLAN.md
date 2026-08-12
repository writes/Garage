# Design Themes × A/B Master Plan — v2, 2026-08-11

**Status:** REVISED after GPT-5.6 Sol strategy co-review (18 findings, 10 blockers — ALL
incorporated below; disposition table §10) → operator review → Law-1 votes (§8) → execution.
**Live-state stamp (verified via ASC API 2026-08-11):** review submission `5c19326d` is
READY_FOR_REVIEW and **NOT submitted** — operator owes subscriptions-attach + Submit.
Re-verify before acting on any App-Review-dependent step.

**Operator ask:** implement all design versions/layouts in full, functionality verified in
parity across all themes; Settings picker eventually; FIRST deep A/B testing on which theme
gets used most and how — high-value metrics only.

Grounding: 4-area deep audit + critic (2026-08-11) and Sol co-review (same day). This v2
supersedes v1 wholesale.

---

## 1. The design inventory (audited)

Two app-wide designs exist, and only two:

| Arm | Design | Source | Status |
|---|---|---|---|
| control | **Garage** (shipped) | the app | LIVE |
| challenger | **Underhood (UH-24)** | `2026-07-24_underhood_concept.html` (interactive prototype: Hood, Logbook, Record, Bay, Handover; full token system) | design ADOPTED by tri-vote 2026-07-24; **zero code shipped**; name dead (wordmark stays Garage) |

Dropped/orthogonal: Continuity (rejected; trust-wedge pieces are *functionality*, not
theme — see §5 exclusion), Living Garage/PATINA (per-vehicle Pro personalization, post-
decision only), Cold Start & Chapters (dropped), Concours (a feature).

## 2. ⚠️ URGENT PRE-LAUNCH ITEM (independent of this plan's timeline)

**The binary in App Review already carries `design_megatest` epoch 1 LIVE-ARMED at 50/50,
and its `variant_a` is the partial PR #23 "bold" pack** (radius/shadow/FAB deltas at 3
chokepoints) — not Underhood. Public launch of this binary starts the experiment with the
wrong challenger on day 1 (Sol B1). The pre-registration is also explicitly review-phase-
only (Sol B2) — production enrollment was never authorized.

**Resolution (binding):**
1. **Now:** stage the server kill (`app_config/experiments` → epoch 1 `isKilled: true`)
   with a runbook; execute it BEFORE the app goes on sale. Accept the bounded first-render
   leak on fresh installs (bundled state applies before the async fetch — Sol B8) as a
   launch-window imperfection; exposure rows logged during the leak are quarantined by
   epoch closure.
2. **First post-approval build:** bundled registry ships epoch 1 killed + the fail-closed
   enrollment gate (§6.2). Epoch 1 is then CLOSED with zero (or quarantined-only) public
   enrollment, recorded in the prereg's results section as "never publicly enrolled;
   superseded".
3. The real design test is **epoch 2**, under a superseding production pre-registration
   addendum (§6.1). No in-place mutation of epoch 1 (prereg rule honored).

## 3. Phase 0 — Truth re-baseline + safety holes (1 cycle)

- **P0.1 Silent-control hole:** client treats any allocated arm whose DesignPack is a spare
  slot as killed; CI cross-consistency test pins Swift `ExperimentArm`/registry ↔
  CloudFunctions `KNOWN_ARMS`.
- **P0.2 Allocation clamp (Sol B7):** for an open epoch the client and server BOTH accept
  exactly the pre-registered weights (`{control:1, variant_a:1}`) or `isKilled` — any other
  weight/roster change requires a higher epoch backed by a new prereg. Tested on both sides;
  in the operator runbook.
- **P0.3 Unit of assignment (Sol B5 — was a caveat, is a defect):** assignment is
  install-scoped; the analysis SQL keys on Firebase uid with pseudo-id fallback →
  cross-device contamination. Fix: **installation is the experimental unit end-to-end** —
  `arm_composite.sql` re-keyed to `user_pseudo_id`, prereg minimum re-denominated to
  mature *installations*, ratified by Law-1 vote (folded into Q1 session) and the stale AB-plan
  doc line corrected.
- **P0.4 Metric repair (Sol B6):** frozen "paywall CTR" has a post-treatment denominator и
  unordered attribution. Amend PRE-ENROLLMENT in the epoch-2 addendum to intent-to-treat
  paywall-reach over all mature exposed installations (primary), with the ordered
  source-matched CTR retained as descriptive; record the amended SQL commit.
- **P0.5 Crash guardrail path (Sol B9):** consent-gated Crashlytics keys for arm+epoch, an
  arm-resolved crash-free query with a validated denominator (TestFlight-verified join),
  and a DAILY guardrail report separate from weekly outcome peeks. The 99.5% kill guardrail
  is not "live" until this path has an end-to-end receipt.
- **P0.6 Doc repairs:** DESIGN_STANDARDS G1 (dark mode is fixed on main), UH-IMPL-1 stale
  anchors, analytics README phantom features + 59→60 count, AB-plan unit line.
- **P0.7** Commit the uncommitted underhood app-icon work (data-loss risk).

## 4. Gate: votes + treatment freeze BEFORE any architecture (Sol B3)

Run the Law-1 session and freeze the **arm manifest** before Phase-1 code:

- **Q1 — challenger scope:** A) full Underhood (visual world + IA re-mapping, full concept
  feature set) | B) visual world only | C) both as separate arms (3-arm epoch 2; raises
  total minimum mature exposure 1,000→1,500 and doubles challenger exposure — Sol B18
  correction). *Recommendation: A* — the adopted design is the registered hypothesis.
- **Q2 — moved PRE-ENROLLMENT (Sol B15):** theme entitlement policy (Pro-gating,
  grandfathering of exposed free users) + post-decision precedence
  (explicit user choice > winner default). Deciding this after exposure could strip a theme
  from users who tested it.
- **P0.3 ratification** in the same session.
- Output: **arm manifest** — an enumerated, frozen list of every visual, navigation, copy,
  and interaction difference variant_a may carry. Anything not listed renders identically.
  **Functional/schema changes are banned from the manifest** (§5).

## 5. Phase 1–2 — Build (engine, then Underhood in full)

**Architecture (binding):** themes = token packs + a closed set of chokepoints over ONE
shared view hierarchy; no forked screens. DesignPack v2 covers the full `Theme.*` token
surface + appearance control + component styles + the manifest's structural chokepoints.
AccentScheme composes within themes (Underhood default amber, accents allowed).

**Phase 1 engine — where it lives (built, control-identical, no content):**
`Garage/Design/DesignTokens.swift` (colour/type/spacing/radius/corner value types, incl. the
chamfer hook) · `DesignComponents.swift` (card, primary/secondary button, FAB, tab bar) ·
`DesignStructure.swift` (the CLOSED manifest-§2 hooks: tab configuration, Hood trends row,
settings accessory, framing copy) · `DesignPack.swift` (the pack + `DesignPackStore`) ·
`DesignPack+Arms.swift` (the per-arm literals — raw values, never `Theme.*` reads).
`Theme` is now pure routing: every token is a `@MainActor` computed read of the active pack,
so all ~412 existing call sites resolve through it unchanged and stay live-reactive to a kill
switch. Consumers wired in Phase 1: the four component chokepoints, the appearance chokepoint
(`preferredColorScheme` in `ContentView`, control = nil = follow the system) and the tab
configuration in `ContentView.mainTabs`. The remaining structural hooks ship with control
values, tested and unconsumed, for waves U1′–U4′. `DesignPackControlPinTests` pins every
control token to its pre-refactor literal — the control-stability contract until §6.3's pixel
snapshots land.

**Phase 2 = full Underhood, explicitly (Sol B4)** — re-anchored waves with acceptance
criteria per wave; every concept feature either implemented or listed as an
operator-approved cut:
- **U1′ Visual world:** tokens from the concept CSS, single dark world, chamfer geometry,
  type scale.
- **U2′ Hood + Systems Bay:** hood odometer/source block, service lights, hood-assembly
  reveal, Systems Bay derivation + tile details.
- **U3′ Logbook + Record:** logbook presentation, record-ritual framing (copy-level only).
- **U4′ Bay + Handover + login:** parts/bay composition, Handover live dossier preview,
  login treatment, and the **explicit Stats/Settings route disposition** (old plan's D2 —
  decided in Q1 session, verified by a reachability assertion).
- **EXCLUDED from the treatment (Sol B11):** trust-wedge provenance (origin/correction
  schema) — it is functionality, not design; shipping it in one arm confounds the test,
  in both arms mid-experiment changes control. Deferred post-decision with its own schema
  vote (restored from old D1).

## 6. Phase 3 — Measurement machinery (before any exposure)

### 6.1 Epoch-2 superseding pre-registration addendum (Sol B2, B13)
Immutable, written before exposure: production cohort + eligible binary/build, rollout
start, exposure cutoff, observation cutoff, **calendar decision date** + data-lag
allowance, no-decision outcome, operator; the amended paywall metric (P0.4); installation
denominators (P0.3); and a **checked-in operating-characteristic simulation** justifying
the per-arm minimum against plausible baselines with a minimum-worthwhile-effect and
expected-loss ceiling — the inherited 500 is not carried on faith; purchase-rate keeps
equal composite weight only if the simulation supports it (else demoted to
tiebreaker per the original metrics plan).

### 6.2 Fail-closed enrollment (Sol B8)
New installs render control and emit NO exposure until the effective registry (bundled ∧
server override) is resolved; treatment then applies atomically WITH its exposure record.
Epoch changes record the new-epoch exposure at the switch instant. A bundled activation
flag remains the release-safety floor.

### 6.3 Parity contract (Sol B12) — the "verified in parity" definition
- **Feature Registry × arm matrix**, frozen: one reachability assertion per feature per arm.
- Semantic equivalence assertions on every re-routed flow: same records written, same
  events fired.
- **Control visual baseline:** snapshot key screens (iPhone+iPad, light+dark) before/after
  the shared-root refactor — the control must be pixel-stable through Phase 1.
- Per-arm journey + unit lanes via `EXPERIMENT_FORCE_DESIGN_ARM`, plus a **release-mode
  per-arm verification** as a go-live prerequisite (DEBUG-only runs don't qualify).
- Contrast matrix: Underhood × ALL FOUR accents × component states (disabled/selected/
  warning/destructive/focus) (Sol B16); suppress or retune failing accents.
- Gate lane additions are PROTECTED `scripts/ci/` changes → drafted for operator.

### 6.4 "How it's used" instrumentation (Sol B14)
A **frozen minimal interaction map** for Underhood-unique surfaces (hood reveal, Systems
Bay tiles, Handover preview — canonical IDs via the frozen-name-registry ritual), marked
exploratory: excluded from the decision rule, read only on the registered weekly cadence.
Generic taxonomy sliced by `design_arm` covers everything else; no other new events.

## 7. Phase 4–5 — Run, decide, then the picker

- **Go-live needs its own review pass (Sol B10), new Phase 3.5:** the experiment binary is
  itself reviewed — Review Notes disclose both designs and the server kill/allocation
  controls; metadata/screenshots reconciled; a documented deterministic reviewer route
  shows BOTH worlds in the release binary without contaminating enrollment (demo mode is
  the natural vehicle). Enrollment starts only after THAT binary is approved and on sale.
- Run per the addendum: weekly peeks, SRM before claims, daily crash guardrail (P0.5),
  kill via runbook.
- **Closeout transaction (Sol B15):** lock results → stop exposures → archive epoch →
  winner default → migrate precedence to explicit-choice-over-default → THEN the Settings
  picker ships (persisted like themeID with the wipe-guard), with entitlement per the Q2
  pre-enrollment decision. Living Garage/PATINA enter only after this point, as Pro
  layers on the winner.

## 8. Law-1 vote points (consolidated)

1. Pre-build session (§4): Q1 challenger scope + P0.3 unit ratification + Q2 entitlement/
   precedence + Stats/Settings disposition (D2).
2. Post-decision: trust-wedge schema vote (restored D1) before that feature ships.

## 9. Sequencing

P0 + §2 kill staging (1 cycle, can start now) → votes/manifest freeze → Phase 1 engine
(1–2 cycles) → Phase 2 waves U1′–U4′ (3–5 cycles) → Phase 3 machinery + 3.5 review pass →
enrollment at that binary's release → run to the addendum's calendar date → closeout →
picker. Nothing here touches the build currently awaiting review; §2's server kill is the
only pre-launch action.

## 10. Sol findings disposition (18/18)

| # | Sev | Disposition |
|---|---|---|
| 1 | BLOCKER | §2 (epoch-1 kill before sale; bundled disable next build) |
| 2 | BLOCKER | §2 + §6.1 (epoch 2 + superseding production addendum) |
| 3 | BLOCKER | §4 (votes + arm manifest before architecture) |
| 4 | BLOCKER | §5 (explicit U1′–U4′ full-concept deliverables + cut list) |
| 5 | BLOCKER | P0.3 (installation unit end-to-end, SQL re-keyed) |
| 6 | BLOCKER | P0.4 (ITT paywall-reach amendment pre-enrollment) |
| 7 | BLOCKER | P0.2 (allocation clamp both sides) |
| 8 | BLOCKER | §6.2 (fail-closed enrollment; atomic expose-on-treat) |
| 9 | BLOCKER | P0.5 (arm-resolved crash path + daily guardrail) |
| 10 | BLOCKER | Phase 3.5 (§7 — review disclosure + reviewer access to both worlds) |
| 11 | MAJOR | §5 exclusion (trust-wedge out of treatment; D1 vote restored) |
| 12 | MAJOR | §6.3 (registry×arm matrix, semantic asserts, control baseline, release-mode lane) |
| 13 | MAJOR | §6.1 (OC simulation, calendar stop, no-decision outcome, purchase weight) |
| 14 | MAJOR | §6.4 (frozen exploratory interaction map) |
| 15 | MAJOR | §7 closeout + Q2 moved pre-enrollment |
| 16 | MINOR | §6.3 accent×state contrast matrix |
| 17 | MINOR | Live-state stamp in header (verified 2026-08-11; 5c19326d NOT submitted) |
| 18 | MINOR | §4 Q1-C corrected arithmetic |
