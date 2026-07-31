# Typed extraction — voice & receipt fill type-specific form fields (rev 4 — AS SHIPPED)

> **rev 4 (2026-07-31, measured supersession of rev 3's single-widened-tool design): SPLIT
> CALL.** Merging the typed vocabulary into the main tool destroyed common-field extraction
> MODEL-INDEPENDENTLY — ablation with the untouched v1 prompt + single shot scored 64.6%
> CORE-COMMON (baseline 98.5%); Sonnet 5 fared no better than Haiku (87.7% vs ~90%); three
> rounds of prompt/few-shot repair plateaued at ~90%. Attention dilutes across a wide optional
> schema. **As shipped:** call 1 is BYTE-IDENTICAL to the validated v1 config for both schema
> versions; v2 adds a SECOND narrow call whose tool holds only the classified entry type's
> fields (widest: tire, 6), with one worked exchange per type family and its own
> TYPED_SYSTEM_PROMPT; failure degrades to all-null typed fields, never sinking the proposal.
> This also structurally eliminates cross-type leakage (Sol #4) and the optional-parameter
> ceiling (Sol #1). §2's field table remains the base vocabulary; §1's "flat additive on the
> same tool" principle is DEAD — see reports/voice-golden-{prod,prod-v2,ablate-tool-only}.json.
>
> **FINAL SHIPPED SET (rev 4 final): 10 fields.** Trimmed by per-field measurement (the gate
> Sol's NO-GO enforced — aggregate scores had hidden below-bar fields):
> `position` + `filterBrand` (0–5/9 recall in every config) and the fuel trio
> `gallons`/`pricePerGallon`/`fuelGrade` (bistable attention split when a grade is spoken —
> the model alternated grade-only vs numbers-only at temperature 0 — plus a measured
> FABRICATION mode: price/gal deterministically derived as total÷gallons, which no prompt
> prohibition fixed without chilling collateral, third measured chilling instance). Fuel now
> makes NO second call; its form seeds station/total from the common fields. The second call
> runs at temperature 0 and validates tool names at the trust boundary.
>
> **Shipping gate met (5 runs, reports/voice-golden-prod-v2.json): CORE-COMMON 320/325 =
> 98.5% (= baseline, paired), TYPED 135/140 = 96.4%, EVERY field ≥80% (worst: brand 20/25;
> seven fields at 100%), zero foreign-type leaks.**
>
> Receipt typed ground-truth eval cases: deferred (receipt call 1 is untouched so
> common-field non-regression is structural; the vocabulary + second-call pattern are
> voice-eval-validated; the receipt two-call request path is unit-tested); add before any
> receipt-specific typed prompt iteration. Rev-2 candidates: fuel trio via a different
> design (receipt line-item parsing), position/filterBrand, AI-processing consent parity
> with the oil-analysis flow (App Review 5.1.2(i) — queued product-wide, predates this PR).

Operator request 2026-07-31: "extract the information and fill out the form fields" — for both
voice quick-add and receipt scan. Today both tools extract only the 7 common fields; every
type-specific field (maintenance item, fuel gallons, brake position…) is structurally
unreachable. Form-field inventory: agent report 2026-07-31 (all 12 forms, enums, defaults).

Review lineage: rev 1 → Gemini (7 findings) → rev 2 → GPT-5.6 Sol (28 findings) → rev 3.
Accepted/refuted dispositions inline; the two structural verdicts were settled EMPIRICALLY:

- **Strict-schema optional-parameter ceiling is real and measured** (Sol #1): a raw API probe
  2026-07-31 rejected 26 optional params ("Schemas contains too many optional parameters
  (26)"); the realistic receipt schema (9 existing props) + 15 typed fields (24 optional)
  compiles. Budget: typed set = **15 fields**, receipt lands at 23/25 optional, and a
  **wire-shape unit test fails the build at >23** so the cliff is a tested invariant, plus the
  eval script probes schema compilation before spending on cases.
- **Version gating** (Sol #2/#3): the client sends `schemaVersion: 2`; the server selects the
  expanded tool + prompt ONLY for v2 requests. v1/absent requests run the legacy tool and
  prompt byte-identical — old builds (≤7) cannot lose notes-resident facts to fields they
  can't decode, and "server deploys first" becomes genuinely safe.

> **READING GUIDE for §§1–4:** these sections are the rev-3 DESIGN RECORD and retain the
> pre-split 15-field wording for review-lineage traceability. Where they conflict with the
> rev-4 header above (single widened tool, 15 fields, few-shots, position/filterBrand/fuel
> trio, addendum), THE HEADER IS THE SHIPPED TRUTH. Authoritative shipped surfaces:
> `CloudFunctions/src/functions/typedExtraction.ts` (10 fields, split call, temp 0, per-type
> serviceAction verbs) and `reports/voice-golden-prod-v2.json` (enforced gate).

## 1. Design principles (rev 3 record)

- Flat, additive, optional; one shared `TYPED_DETAIL_PROPERTIES` spread into both tools; one
  shared sanitizer. No anyOf/nesting.
- Only fields with UI to receive them. Deferred live-UI fields are enumerated in §6 with
  their behavior (Sol #20).
- **Wire values decode as `String?`/`Double?`/`Int?` — never Codable enums** (Sol #16, Gemini
  #3). Each form maps via an explicit, unit-tested conversion table; unknown values → nil →
  form default. `position` uses TirePosition's REAL raw values `fl|fr|rl|rr|front|rear|
  all_four` (Sol #8); brake maps `front/rear` only and `all_four→all`; corner values do NOT
  coarsen to an axle for brakes — no seed, the fact stays in notes (Sol #9).
- Sanitizer rule is uniform: **out-of-bounds ⇒ null** (numbers out of range, strings over
  length, enum values off-list, non-safe-integers). Never truncate (Sol #18, Gemini #4).
  Ranges relaxed: gallons (0,150], pricePerGallon (0,25], quantityQuarts (0,40].
- **Sanitizer is entry-type-aware** (Sol #4): typed fields foreign to the proposal's
  entryType are nulled server-side (e.g. `gallons` on a brake entry) — cross-type leakage
  dies at the source, not in 12 client mappings.
- Response carries `proposalSchemaVersion: 2` (Sol #17) so the client and analytics can
  distinguish "old server" from "nothing extracted".
- Multi-action/multi-brand jobs: the model extracts the PRIMARY action/brand
  (prompt-directed, few-shot-anchored); the full statement still lands in notes. Forms are
  single-value Pickers — extraction must not exceed what the form can hold (refutes Sol #6 /
  Gemini #2 arrays for rev 1; noted as rev-2 candidates with UI work).
- Substantive picker defaults (Sol #12): unchanged in rev 1 — identical to today's manual
  entry; the form is a review surface. Recorded as a known limitation; unselected-state
  pickers are a separate product decision.

## 2. Typed fields (15)

| Field | Wire type | Sanitizer | Serves |
|---|---|---|---|
| `workItem` | string | ≤160 else null | maintenance matcher, repair.title, upgrade.title |
| `brand` | string | ≤80 | oilBrand, padBrand, tireBrand, upgrade.brand (primary component's brand; prompt: omit if ambiguous across components — Sol #7 mitigations) |
| `productModel` | string | ≤80 | tire.model |
| `filterBrand` | string | ≤80 | oilChange.filterBrand |
| `oilGrade` | string | ≤20 | oil forms' grade ("0W-40") |
| `quantityQuarts` | number | (0,40] | oilChange.quantityQuarts, oilConsumption.amountAdded |
| `gallons` | number | (0,150] | fuel.gallons |
| `pricePerGallon` | number | (0,25] | fuel.pricePerGallon |
| `fuelGrade` | enum FuelType raws `regular_87\|premium_91\|premium_93\|e85\|diesel` | off-list→null | fuel.fuelGrade; prompt: omit unless exact match (89-octane ⇒ omitted, picker default) |
| `position` | enum `fl\|fr\|rl\|rr\|front\|rear\|all_four` | off-list→null | tire.position (all 7); brake.position (front/rear direct, all_four→all, corners→no seed) |
| `serviceAction` | enum `pads_replaced\|rotors_replaced\|fluid_flush\|inspection\|new_install\|rotation\|tread_depth_reading\|removed` | off-list→null | brake.action (first 4) / tire.actionType (last 4); foreign-to-form values → no seed |
| `nextDueOdometer` | integer | (0,2e6) ∧ isSafeInteger | maintenance.dueMileage. ABSOLUTE odometer; schema description instructs interval addition ("due in 5,000 miles" + vehicle context currentOdometer) — Sol #14/#15; both phrasings evaled |
| `tireSizeFront` | string | ≤20 | tire.frontSize |
| `tireSizeRear` | string | ≤20 | tire.rearSize |
| `upgradeCategory` | enum UpgradeCategory raws `suspension\|engine\|aero\|interior\|wheels\|other` | off-list→null | upgrade.category (Sol #13 — picker-default misclassification is worse once title auto-fills) |

Dropped from rev 2 under the ceiling budget (deferred; common fields + notes only): `venue`,
`lapCount`, `bestLapTime` (track day), `dmeReportType` (DME). Rationale: lowest-frequency
types; a rev-2 per-family tool split can restore them.

## 3. Client mapping

`TypedProposalDetails` (all optionals, raw wire types) computed from both proposals.
`EntryFormScaffold` gains `onAIPrefill: ((TypedProposalDetails) -> Void)?` — invoked in the
same `.task`, after `applyVoicePrefill`/`applyReceiptPrefill`, only when a voice/receipt
handoff seeded THIS presentation, never for edit, and only once per view-model
(`wasVoiceSeeded || wasReceiptSeeded` guard — same rebuild semantics as the held-slot fix).

Pure, unit-testable mappers (Sol #27): each form's seeding logic lives in a static
`XFormSeed.apply(TypedProposalDetails, to: …)`-style pure function (or equivalent testable
surface), with fixture tests covering: server-shaped JSON → proposal decode → mapper → form
state, including null/missing keys, unknown enum values, fractional integers, and
foreign-type payloads. Mapping rows:

- maintenance: workItem → `MaintenanceItemMatcher` (keyword table; no match → picker default,
  documented limitation Sol #11), nextDueOdometer → dueMileage.
- fuel: gallons, pricePerGallon, fuelGrade table, shopName → stationName copy, cost → totalCost.
- oilChange: brand → oilBrand, oilGrade, quantityQuarts, filterBrand.
- oilConsumption: quantityQuarts → amountAdded, brand → oilBrand, oilGrade.
- brake: serviceAction (4 brake values) → action, position (front/rear/all_four→all; corners →
  no seed), brand → padBrand.
- tire: serviceAction (4 tire values) → actionType, position (all 7) → position, brand →
  tireBrand, productModel → model, tireSizeFront/Rear.
- repair: workItem → title.
- upgrade: workItem → title, brand, upgradeCategory table → category.
- trackDay/dmeReport/alignment/oilAnalysis: common fields + notes only (typed deferred).

## 4. Server changes

- `TYPED_DETAIL_PROPERTIES` + `sanitizeTypedDetails(input, entryType)` shared module; spread
  into V2 variants of both tools. Tool selection by `request.data.schemaVersion === 2`.
- `toolInputFromPayload` (Sol #21): verify current block-selection logic during
  implementation; with `tool_choice` forced and strict mode the response carries exactly one
  block — assert that and reject multi-block responses.
- Field-presence logging extends with `typedFieldCount` + `schemaVersion`.
- Scaffold logs a seeded-field-NAME list breadcrumb (names only, no values); correction-rate
  telemetry deferred (Sol #28 noted).

## 5. Eval plan (Sol #22–25, Gemini #6)

- **Paired non-regression**: the untouched original 18-case corpus runs against the v2
  schema/prompt; per-field scores (entryType, odometer, cost, shop, isDiy, date, notes) must
  each be ≥ the 2026-07-31 baseline (`reports/voice-golden-prod.json`, 64/65 = 98.5%).
- **Typed scoring is positive-anchored**: typed fields score ONLY on cases where the value is
  expected present, plus explicit absence cases (field must be null) and foreign-type cases
  (typed field on the wrong entryType must be null — also covered by the sanitizer test).
  A silent model cannot pass: every one of the 15 fields has ≥1 positive case; gate =
  per-field positive recall ≥0.8 AND zero foreign-type leaks.
- ~14 new voice cases (fuel fill-up, staggered tires, brake corner phrase→notes, oil change
  full detail, maintenance next-due interval AND absolute, upgrade with category, repair,
  multi-brand ambiguity→omission, 89-octane omission, …). Few-shot examples use DIFFERENT
  surface forms than eval cases (Sol #25 contamination note; sealed holdout deferred).
- receiptGoldenEval: typed expectations added to the pinned corpus; same positive-anchored
  scoring. Real-receipt holdout corpus deferred (Sol #26 noted).
- Eval script gains a pre-spend schema-compilation probe (one cheap call; hard-fails on 400).

## 6. Deferred live-UI fields (explicit, Sol #20)

Left at form defaults, facts land in notes: brake wear percentages + padCompound, tire tread
depths, maintenance/repair `status`, trackDay venue/eventType/laps/bestLap, DME
provider/reportType/summary, alignment shopNotes, oil-analysis lab values (own PDF-import
path). Cross-field contradiction validation (gallons×price vs cost, next-due vs current
odometer) deferred to the form's existing validation layer (Sol #19 noted; odometer floor
reconcile already runs).

## 7. Rollout

Server first (v2 path dormant — no client sends schemaVersion 2). Client rides build 8.
No feature flag beyond the version gate itself.
