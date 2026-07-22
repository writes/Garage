# Garage Design & Production-Engineering Standards — ADOPTED (2026-07-12)

**Status:** Governing design/engineering quality bar (operator directive 2026-07-12: "utilize
the most common design properties and techniques of top-level engineering groups"). Synthesis
of a 6-lane web-research sweep (85 sourced practices: Apple HIG, Material 3, Shopify Polaris,
Uber Base, Stripe, Linear, RevenueCat industry data) + a 4-lane read-only audit of this repo.
Subordinate to the Five Laws and the 2026-07-11 Profit-First Blueprint (activation and trust
metrics there are the WHY for several items here).

## 1. Adopted standards (the bar)

### Design system
1. **Semantic tokens only at call sites** — raw hex/size/padding literals are legal only inside
   the token layer (`Garage/Design`). Never repurpose a semantic token off-role (HIG).
2. **Dark mode by construction** — every color token carries light+dark (asset-catalog
   Any/Dark variants or system semantic colors); elevation-aware surfaces per HIG base/elevated.
3. **Type scale = relative text styles** (Dynamic Type scales everything); custom sizes only
   via `UIFontMetrics`/`relativeTo:`; layouts reflow (wrap, stack-direction switch) at
   accessibility sizes — never truncate.
4. **Spacing via the Theme scale only** (already clean: zero raw-padding bypasses found);
   44×44pt minimum hit targets.
5. **Component tiers**: primitives consume only semantic tokens; every transient/feedback
   surface (toast, skeleton, empty, error, offline chip) is a design-system component, not
   per-screen improvisation.

### Screen-state contract (the "UI Stack")
Every screen ships all five states as a deliverable: **ideal, empty (3 species: first-use /
user-cleared / filtered-empty), loading (skeleton mimicking final layout; nothing <1s,
skeleton 1–10s), error (plain language + in-place Retry), offline (passive chip, never a
preflight gate)**. First-run empty states are activation surfaces: orient → value → ONE CTA.

### iOS-native excellence
Dynamic Type everywhere; VoiceOver measured by task completion (core flows finishable);
Reduce Motion/Transparency honored (crossfade variants); SF Symbols paired to text styles;
semantic haptics (prepared generators); keyboard never covers the focused field or CTA;
`performAccessibilityAudit()` in UI tests; Accessibility Nutrition Labels + EAA (June 2025)
treated as the compliance floor.

### Production engineering (targets, evidence-classified per Sol round-3 review)

| Target | Class | Source |
|---|---|---|
| Cold launch first frame ≤ ~400ms | Platform recommendation | Apple WWDC19-423 |
| **Hitch time ratio** <5 ms/s good · 5–10 warn · ≥10 act | Platform recommendation | Apple WWDC20-10077 (Apple's term; measures normalized late-frame time, not event frequency) |
| Main-thread blocks ≥250ms | Platform signal: **potential hang** to investigate — not automatically a defect | Apple Instruments hang guidance |
| Crash-free sessions ≥99.9% / 99.95% | **Industry benchmark observation** (Luciq/Instabug 2025 median 99.95%) — NOT an Apple floor; becomes a Garage SLO only after session definition, cohort, window, minimum N, and halt action are specified in the observability workstream (DS-8) | Luciq Mobile Stability Outlook 2025 |
| Phased rollout + halt criteria, flags-as-kill-switches, snapshot regression gate, MetricKit/Organizer telemetry, binary-size diffs | Practice adoption (no numeric claim) | multi-source |

No number above is a Garage SLO yet; DS-8 turns selected rows into SLOs with full gate
definitions. Accessibility framing (Sol adv. 4): Apple's Accessibility Nutrition Labels are
storefront metadata/readiness criteria and the EAA's applicability is jurisdiction/product
dependent — both are drivers for the accessibility backlog, neither phrase alone claims legal
compliance.

### Polish
Springs as default curves; interruptible transitions; matched-geometry list→detail; launch
screen identical to first frame; stable SwiftUI list identities; images downsampled to display
size with thumbnail-first delivery; `textContentType`/`keyboardType`/`submitLabel` on every
field; inline per-field validation.

## 2. Audit result — Garage vs the bar (evidence-cited; 4 agents, 2026-07-12)

**Strengths confirmed:** semantic token naming + clean spacing discipline (zero raw-padding
bypasses in 65 feature files), relative-style typography base, hardened export/entry
components, strong accessibility-identifier test contract (74 sites), CSV/PDF injection
hardening, App Check + server entitlements (post Wave-1).

| # | Gap | Sev | Evidence |
|---|---|---|---|
| G1 | All 10 brand colorsets define ONE universal appearance — **dark mode broken by construction**; `garageShadow` fixed black | **P0** | `Assets.xcassets/*/Contents.json`; `Color+Extensions.swift:4` |
| G2 | **Zero-vehicle first launch is not an activation surface** — new user lands in a blank 5-tab UI (directly harms Blueprint Buyer-Ready-7/time-to-first-import) | **P0** | `ContentView.swift:8-14`, `AppState.swift:97-105` |
| G3 | Five Garage sub-screens (Parts, Photo/Wheel galleries, Detailing, Warranty) have **no error branch**; ViewModels have no `isLoading`; failures render as silent fake-empty | **P0/P1** | `SparePartsView.swift:9-30` et al.; grep `isLoading` = 0 in those VMs |
| G4 | StatsView: no loading state; ErrorBanner without retry; charts render blank axes with no data + no accessibility labels | P1/P2 | `StatsViewModel.swift`, `StatsView.swift:20-21`, chart files |
| G5 | VehicleListView: bare blank list when empty | P1 | `VehicleListView.swift:8-15` |
| G6 | Offline is one tiny badge app-wide; sync failures otherwise invisible | P1 | `VehicleSwitcher.swift:24,36-41`; `SyncService.swift:29,45-48` |
| G7 | Typography bypasses: fixed `.font(.system(size:))` in FloatingAddButton, EmptyStateView (won't scale with Dynamic Type) | P1 | `FloatingAddButton.swift:11`, `EmptyStateView.swift:11` |
| G8 | SkeletonLoader + CardView defined but zero call sites; no toast component exists | P1/P2 | grep results in audit |
| G9 | accessibilityLabel coverage: 2 vs 74 identifiers — VoiceOver task completion unmeasured | P2 | grep results |
| G10 | LogView shows the same empty state for true-empty vs filtered-empty | P2 | `LogView.swift:13-24` |

## 3. LLM-leak audit result (operator directive)

**App/client: CLEAN.** No Anthropic/OpenAI/Gemini key, endpoint, or model id anywhere in the
iOS app, Info.plist, entitlements, or Configuration/; the only path is
`ClaudeService → Firebase callable`; the CF proxy sends only the PDF + fixed prompt (no
uid/email decoration); no payload/model-output logging; `.env` gitignored with no committed
history. Two P2 hardening notes: (a) no schema validation of the full Anthropic payload before
text extraction; (b) fetch/parse catch blocks swallow errors with zero logging (hurts ops, not
privacy).

**Brain/intelligence layer: 3 P1s + hardening (fix list DS-5):**
- `tri_agent_vote.py` writes raw LLM decision/reasoning to the append-only ledger with **no
  secret screening** (tri_review/dual_agent_loop have it; the vote path does not).
- `gemini_consult.try_agy()` passes the full prompt as an **argv element — visible in `ps`
  to every local process** while agy runs (a real local disclosure channel; also how hung
  prompts end up readable in process listings).
- `process_sentinel.py` (landmine #14) is not yet wired into an automated hook.
- P2s: fixed-regex secret allowlist; review workflows diff protected paths by content;
  `session_handoff.py` git call lacks a timeout.

**Process-leak posture:** sentinel live (13/13), first run caught two 27h hung agy wrappers
from a sibling session (reported, not killed — contention rules). Incident history is now
documented under landmine #14.

## 4. Execution backlog (gated, ordered)

**Sequencing (Sol round-3 blocker #2 disposition):** the 2026-07-11 sequence vote authorized
the enumerated Wave-1 hardening list "and nothing else." Therefore **iOS-6L and RULES-1
complete first** (through CI + tri-review); DS-1..3 execute only after that, or after a fresh
Law-1 sequence vote. DS-5 was executed 2026-07-12 as leak-audit remediation under the standing
operator directive (its round-3 corrections below). Severity labels G1–G3 are audit priorities,
not a release-blocking rubric — the release gate remains CI + tri-review + operator.

| ID | Scope (round-3 hardened) | Sev | Wave |
|---|---|---|---|
| **DS-1** | Dark-mode tokens — **no guessed hex**: map roles to Apple semantic neutrals wherever roles match; explicit `onPrimary`/highlight roles for fixed-white content (PrimaryButton/FAB/shimmer); foreground×surface contrast matrix committed with the change; light-mode pixels preserved; **operator visual approval in Dark + Increase Contrast required**; colorsets live under `Garage/Resources` (outside the scope-guard allowlist) → needs a governed, supervised edit like the rules precedent | P0 | after iOS-6L + RULES-1 |
| **DS-2** | First-run activation — requires an explicit `loading / loaded([Vehicle]) / failed` bootstrap state; activation surface ONLY on successful `loaded([])`; error+Retry on `failed` (never mislabel an outage as first use); DEBUG seed-vehicle path must not mask real zero-vehicle testing; hermetic zero-vehicle launch + CTA→save→refresh→tabs journey test | P0 | after iOS-6L + RULES-1 |
| **DS-3** | Loading/error/empty **phase 1** (renamed per Sol — not the full five-state contract; offline defers to DS-6): typed mutually-exclusive load states; `.task(id:)` keyed by vehicle/entitlement with stale-completion rejection; skeletons mimic final layout, delayed reveal (immediate interaction feedback always retained), **static fallback under Reduce Motion** (don't wait for DS-7); retry semantics + per-state VM tests + vehicle-switch journey | P0/P1 | after iOS-6L + RULES-1 |
| **DS-4** | Typography bypass cleanup (G7) + LogView filtered-empty split (G10) | P1 | queued |
| **DS-5** | Brain leak fixes — **round-3 status**: shipped (screen module, vote-path screening, sentinel hook, one timeout) with corrections required and applied: sentinel output sanitized (no command text — it re-amplified prompts through the hook), redaction-tripped voters invalidated (not counted live), remaining unbounded subprocess calls bounded, argv residual **formally accepted by unanimous vote 2026-07-12T21:45:13Z** (threat model documented; revisit if untrusted local users appear or agy ships file/stdin input) | P1 | DONE + corrected |
| **DS-6** | Toast component + offline chip + sync-failure surfacing (G6, G8) | P1 | queued |
| **DS-7** | Accessibility: VoiceOver task-completion measurement (the defensible gap — identifier counts are test hooks, not coverage), labels on charts/controls, `performAccessibilityAudit()` in UI tests, Reduce Motion variants | P1 | queued |
| **DS-8** | Perf/observability: MetricKit subscriber, launch/hitch-time-ratio budgets in CI, snapshot harness, and the SLO definitions that upgrade §1 benchmarks to Garage gates | P2 | gated |
| **DS-9** | Polish: matched-geometry list→detail, haptics map, image downsampling pipeline | P2 | gated |

Routing: **Terra writes, orchestrator verifies** — the DS-5 orchestrator-lane deviation is
logged; future brain fixes route through Terra like everything else. Blueprint Wave-2 "iOS-6"
is superseded by Wave-1 iOS-6L when it lands (Sol adv. 9). Audit-count clarification (adv. 6):
"74 identifiers / 2 labels" is the `Garage/Features` count, not app-wide.

## 5. Sources
Primary: Apple HIG (Color, Dark Mode, Typography, Accessibility, Launching), Apple TN/WWDC
hitch + MetricKit docs, Material 3 token docs, Shopify Polaris tokens, Uber Base, Stripe Apps
style, Linear redesign notes, RevenueCat industry reports (trials/paywalls), W3C DTCG. Full
per-practice citations in the workflow transcript (wf_cc865cee-8ef journal).
