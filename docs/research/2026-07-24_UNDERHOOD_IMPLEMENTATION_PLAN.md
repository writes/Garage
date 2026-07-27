# Underhood Transformation — Implementation Plan (UH-IMPL-1)

**Date:** 2026-07-24 · **Author:** Fable 5 (orchestrator) · **Status:** DRAFT → Sol co-review
**Authority:** operator directive 2026-07-24 ("implement the underhood transformation", artifact
39383192) + tri-vote (DECISION_LEDGER group per HANDOFF 2026-07-24): design direction ADOPTED,
name "Underhood" REJECTED pending trademark clearance.
**Design source of truth:** `docs/research/2026-07-24_underhood_concept.html` (UH-24) — palette,
chamfer geometry, type ramp, IA, ritual copy. This plan maps it onto ground truth (file:line
anchors verified 2026-07-24 on `feature/prod-hardening` @ 9bec399).

## Hard constraints (carried from votes + scope guard)

1. **Naming:** "Underhood" appears NOWHERE durable (no `project.yml`, `Info.plist`,
   `CFBundleDisplayName`, ASC metadata, marketing strings). One `Brand` token
   (`Garage/Design/Brand.swift`: `wordmark = "GARAGE"`) feeds every wordmark render; the swap
   is a one-line change post-clearance.
2. **Protected surfaces untouched:** `project.yml`, `scripts/ci/`, secrets, Firebase rules.
   New Swift files live under allowed prefixes (`Garage/Design/`, `Garage/Features/`,
   `Garage/Core/`, `Tests/`); `xcodegen generate` refreshes `Garage.xcodeproj/` (allowed).
3. **Branch discipline:** new branch `feature/underhood` off `feature/prod-hardening`.
   Nothing merges without the operator (Law 5). `verify-ios.sh` green per wave;
   `tri_review.py` before any merge request.
4. **No invented health scores** (UH-A "Facts Only"): every Systems Bay status = last recorded
   fact + interval math, with the source line shown. No synthetic composites.

## Waves

### U1 — Design system foundation + dark commitment
- Colorsets (`Garage/Resources/Assets.xcassets/*.colorset`): re-point to the UH palette —
  Background→Bay `#0D1217`, Surface→Gunmetal `#161E28`, new `SurfaceRaised`→Machined
  `#1E2836`, Accent/BrandPrimary→Lamp Amber `#F2A33C`, TextPrimary→Bone `#EAEFF3`,
  TextSecondary→Steel `#8B99A9`; Success `#4CC38A`, Error `#E4572E`, Warning=amber. The app
  commits to ONE visual world (concept: "engine bay, dark"): swap
  `.preferredColorScheme(.light)` → `.dark` at `GarageApp.swift:65-67,93` (same
  single-appearance strategy as today, inverted — no dual-appearance matrix to maintain).
- `Theme.swift` extensions: mono data ramp (`monoData`, `monoCaption`, `monoLarge` — all
  `.monospaced` + `tabularNumbers`), `display` (heavy, uppercase, −2% tracking), hairline.
- New `Garage/Design/Components/`: `ChamferShape` (Shape, one 45° top-right cut, 12–22pt by
  card importance) + `.chamferCard()` modifier (surface + hairline stroke inset);
  `ServiceLightPill` (dot+mono label, ok/warn/bad); `OdometerView` (mono digits,
  `.contentTransition(.numericText)` roll, reduced-motion honored). `garageShadow` retired on
  dark surfaces (hairlines carry depth).
- `CardModifier.swift` migrates to chamfer geometry; `AccentScheme` default becomes Lamp
  Amber (Pro alternates re-tuned to read on Bay in a later pass; picker stays).
- Tests: ChamferShape path geometry, theme token presence, odometer roll state, snapshot-free
  (existing harness has no snapshot infra — assert view-model/state level).

### U2 — IA remap + Hood
- `AppTab.swift`: `hood="Hood"` (was Dashboard), `logbook="Logbook"` (Log), `bay="Bay"`
  (Garage), `handover="Handover"` (new, hosts Export/dossier), Settings LEAVES the tab bar →
  avatar button in each screen header (sheet). Stats LEAVES the tab bar → "Trends" row on
  Hood presenting the existing (re-skinned) StatsView sheet. Existing Pro gates unchanged
  (`PaywallSource` sites keep their contexts; UH-D: "never on a locked tab").
- `ContentView.swift`: 4 tabs + center **Record** dock action — replace `FloatingAddButton`
  with a chamfered amber Record well (58pt, `router.present(.entryPicker)`; zero-vehicle gate
  at `AppRouter.swift:58-74` unchanged).
- **Hood screen** (re-skin `DashboardView`): odometer block (OdometerView + "recorded {date} ·
  entered by {origin}" source line from vehicle+latest odometer entry), service-lights row
  (due/overdue reminders → pills, amber/red per due state), **hood-assembly reveal**: vehicle
  card hinges open (`rotation3DEffect` x-axis, anchor top, ~64°, spring; reduced-motion =
  crossfade) revealing the **Systems Bay** grid.
- **Systems Bay** (design-new presentation over existing data): `SystemsBayService` derives
  per-system tiles — last matching entry (by `EntryType` group: oil, brake, coolant/
  maintenance, tire, battery via parts/warranty, cabin filter) + interval source (explicit
  `Reminder.repeatIntervalMiles/Months` when present; else "no interval set" — never invented)
  → due math + bar. Tile detail sheet: history + "Record work" path. Facts-only copy
  ("last @ 79,400 · due in 780 mi").
- Wear bars / recall badge re-skinned in place.

### U3 — Logbook + trust-wedge (schema wave — tri-vote first, see below)
- Logbook re-skin: search field, filter chips (mono uppercase, amber-on), year marks, entry
  rows with mono mileage right-aligned.
- **Origin chips (persisted provenance):** `FirestoreEntry.origin: String?` — enum
  `EntryOrigin { manual, voice, scan, import }` written at `makePendingEntry`
  (`EntryFormViewModel.swift:189-211`): manual default; voice when voice-prefill consumed;
  scan/import from the analysis/import coordinators. Legacy entries (nil) render "Entered by
  you". Chips: "Entered by you" / "Voice · reviewed" / "Scan · reviewed" + "Receipt attached"
  when attachments exist.
- **Correction stamps (visible, never silent):** scoped v1 to scalar fields (odometer, cost,
  date) to avoid the edit-in-place details-seeding blocker (pass-5 CUT stands). New guided
  "Correct this entry" flow writes `corrections: [CorrectionRecord]` on the entry
  (`{field, oldValue, newValue, correctedAt}` append-only) + updates the scalar + reconciles
  odometer via the existing delete-path reconciliation logic + revision bump. UI: "Corrected
  {date} · {field} {old→new}" with old value struck — never erased. Delete keeps its pass-5
  semantics.
- Draft ritual styling: voice prefill + oil-analysis draft surfaces adopt the amber
  uncommitted treatment ("DRAFT — amber until committed", Commit primary button).

### U4 — Bay + Handover
- **Bay tab:** vehicles list (chamfer vehicle cards, active badge) + Parts shelf resurfaced
  (SparePartsView content at top level of the tab, warranty chips) — existing Garage-tab
  features re-homed; gallery/wheel/detailing remain rows.
- **Handover tab:** re-skin `ExportView` as the dossier builder — section toggles rebuild a
  live preview card (record/evidence/page counts from real data), honest-copy footer
  ("what leaves your account is exactly what you can see"), PDF via existing
  `PDFExportService` (off-main, TPPDF). The `"Vehicle History: Not connected"` placeholder
  line is REMOVED in favor of the sections actually included. Full buyer-ready dossier
  content model remains Wave-3 iOS-7 (unchanged scope) — this wave is presentation +
  truthful sections only.
- Login wordmark → `Brand.wordmark` component ("GARAGE" + amber accent letterforms per the
  concept's masthead treatment, name-safe).

## Decision points routed per doctrine
- **D1 (Law-1 tri-vote, before U3):** trust-wedge schema — `origin: String?` +
  `corrections: [CorrectionRecord]` append-only on `FirestoreEntry`, scalar-only guided
  correction v1. (Both trust-wedge items were adopted in principle by today's earlier votes;
  this vote pins the concrete schema.)
- **D2 (Sol co-review, this doc):** IA displacement of Stats ("Trends" row on Hood) and
  Settings (avatar sheet) — concept is silent on both; dissent escalates to a vote.
- **D3 (operator, later):** name swap post-trademark; icon; App Store metadata. Out of scope
  here.

## Gates per wave
`xcodegen generate` → `verify-ios.sh` (policy, lint strict, build, sim tests, archive) green;
scope_guard clean (no protected writes); wave receipt in `docs/research/`; HANDOFF updated.
Pre-merge: `tri_review.py` all-provider review; operator holds merge.
