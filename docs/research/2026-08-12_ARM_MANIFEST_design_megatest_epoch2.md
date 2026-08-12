# ARM MANIFEST — design_megatest epoch 2 (FROZEN at the 2026-08-12 vote session)

The enumerated, closed list of every difference `variant_a` (full Underhood) may carry versus
`control` (shipped Garage). **Anything not listed renders identically in both arms.** Additions
require a plan amendment BEFORE implementation; after enrollment begins, additions require an
epoch bump. Source decisions: Q1 = A (full Underhood, majority, ledger 2026-08-12) ·
D2 = A (unanimous, same session) · trust-wedge EXCLUDED (Sol B11) ·
design source: `2026-07-24_underhood_concept.html` (visuals/copy ONLY — its wordmark is DEAD;
no name/wordmark change ships in any arm).

## 1. Token pack (DesignPack v2 surface)

| Token group | control | variant_a |
|---|---|---|
| Color palette | shipped Theme.Colors (system light/dark) | Underhood palette from the concept's CSS custom properties; SINGLE dark world |
| Appearance | system-following | committed dark (`preferredColorScheme(.dark)` via the appearance chokepoint) |
| Typography scale | shipped Theme.Typography | concept type ramp (display/label sizes, weight mapping) |
| Shape | shipped Theme.Radius | chamfer geometry (concept corner language) per component class |
| Component styles | shipped card/button/FAB styles | chamfered cards, Underhood button geometry, tab-bar styling, FAB treatment |
| Accent | AccentScheme (4 accents, Pro) applies | SAME AccentScheme applies; Underhood amber is the arm's DEFAULT accent only |

## 2. Structural chokepoints (closed list)

1. **Tab mapping (routing chokepoint):** Dashboard→Hood · Log→Logbook · Add-entry flow→Record ·
   Garage→Bay · Export/dossier surface→Handover. Labels + SF symbols per concept; the tab COUNT
   stays 5; each tab hosts the SAME view hierarchy as its control counterpart.
2. **Stats disposition (D2-A):** no Stats tab in variant_a; Hood gains a "Trends" entry row that
   PUSHES the existing, unmodified `StatsView` full-screen.
3. **Settings disposition (D2-A):** no Settings tab in variant_a; EVERY tab root's nav bar gains
   an avatar/gear button presenting the existing, unmodified `SettingsView` as a sheet.
4. **Hood hero block:** Dashboard's vehicle header renders the concept's hood treatment
   (odometer/source block, service lights strip) — same underlying data sources as the
   Dashboard cards it restyles; the hood-assembly reveal animation.
5. **Systems Bay presentation:** Bay renders the Garage-tab feature set with the concept's tile
   grid presentation (derivations from EXISTING data only).
6. **Logbook presentation:** Log rows restyled per concept (ledger framing); same rows, same
   paging, same search.
7. **Record framing:** the add-entry flow carries the concept's ritual copy (copy-level only —
   same forms, same fields, same validation).
8. **Handover framing:** the export surface carries the concept's handover framing/copy; same
   export engine, same outputs.
9. **Login treatment:** the sign-in screen restyled per concept tokens (same providers, same
   flows, same error surfaces).

## 3. Explicitly EXCLUDED from variant_a

- Trust-wedge provenance (origin/correction schema) — functionality, not design (Sol B11; own
  vote D1 later).
- Any wordmark/name/app-icon change (naming workstream is operator-gated; icon ships to BOTH
  arms or neither).
- Living Garage / PATINA personalization (post-decision Pro layer).
- Any schema, event-name, or data-write change: both arms write IDENTICAL records and fire
  IDENTICAL analytics events (the arm lives ONLY in user properties, the exposure event, and
  the frozen exploratory interaction map defined at Phase 3).
- Any Pro-gate change: entitlements identical across arms (Q2 governs post-decision theming
  entitlements, not arms).

## 4. Parity contract binding this manifest

Feature-registry × arm reachability matrix (every shipped feature reachable in ≤2 taps in both
arms); identical accessibility identifiers; identical data writes and event streams; control
visual baseline pinned before the engine refactor; per-arm journey + contrast lanes
(Underhood × all 4 accents × component states); release-mode per-arm verification before
enrollment (master plan §6.3).
