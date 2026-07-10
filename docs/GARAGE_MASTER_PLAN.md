# Garage — Master Plan

> **Living strategy + execution plan** for the Garage product, generated 2026-06-29.
> Companion to `PROJECT_STATE.md` (point-in-time technical snapshot). Where that file
> describes *what exists*, this file describes *what to build, in what order, and why*.
> Treat it the way the brain treats its other surfaces: durable-by-default, regenerate
> when strategy shifts. Substantive bets in here are candidates for the consensus layer
> (≥3 voters, 2/3, logged) — not solo calls.
>
> Lenses applied throughout: **principal architect** (rigor, schemas, infra), **engineer**
> (build-vs-buy, sequencing, effort), **product manager** (value, metrics, gates), and
> **car enthusiast** (what actually matters to the person under the car).

---

## 0. Strategic frame (the spine everything hangs on)

Two sentences to hold in your head while reading the rest.

**The wedge is resale documentation.** Effortless, trustworthy ownership records that
measurably raise a car's sale price. This is *why a serious owner adopts today*.

**The moat is the proprietary dataset.** A normalized, VIN-decoded, longitudinal record of
real-world maintenance, cost, failure-at-mileage, oil analysis, and consumable life across
thousands of specific year/make/model/**engine** combinations. This is *why Garage wins
long-term and how it eventually prints money beyond subscriptions*.

Every item below is scored against one question: **does it sharpen the wedge or feed the
moat?** Features that do neither are deferred regardless of how fun they are.

**North Star metric:** *Active Documented Vehicles* — vehicles with a living record
(≥ N structured entries, updated in the last 90 days, ≥1 attached document). It is the only
metric that simultaneously predicts retention, resale value, conversion, and moat growth.

**Effort legend:** S ≈ days · M ≈ 1–2 wks · L ≈ 3–6 wks · XL ≈ quarter+. (Calibrated to a
small core team accelerated by the multi-agent brain; adjust as the team scales.)

---

## 1. Phased roadmap (the master sequence)

Three phases. Each phase has a single thesis; do not start the next until the prior thesis
is proven by metrics, not vibes.

### Phase 1 — Solidify the wedge, start the flywheel  *(thesis: documentation that pays back)*
The flywheel: easy logging → complete records → high-value export/passport → resale lift →
word of mouth + ownership transfer → new owners onboarded with history already in hand.

| Workstream | Deliverable | Effort |
|---|---|---|
| AI ingestion (generalized) | Snap *any* invoice/receipt/email/sticker → structured entries | L |
| Resale Passport | Shareable read-only web record (history, mods, oil trends, receipts) | L |
| Ownership Transfer | Hand the full documented history to the buyer's account | M |
| OEM schedule ingestion | Factory-correct intervals per VIN → auto-reminders | M |
| Canonical data model + pipeline | Normalized schema + BigQuery aggregation (moat foundation) | L |
| Full instrumentation | Activation/retention/conversion/virality events live | M |

### Phase 2 — Depth, AI advisory, premium ladder  *(thesis: the app gets smarter as you use it)*

| Workstream | Deliverable | Effort |
|---|---|---|
| Advisor chat (RAG over the car) | "What's due next?" grounded in this car + fleet + OEM + TSBs | L |
| Oil-analysis intelligence | Parse → explain → trend → benchmark vs fleet → recommend | M |
| Predictive maintenance | "Water pumps go ~80–100k on this engine; budget $X" | L |
| Cost & value intelligence | TCO, cost/mile, market value, equity/depreciation | M |
| Track suite | Lap logbook, datalog storage, consumables-by-track-hours | L |
| Affiliate parts commerce | Service-due → exact parts list → buy (FCP/ECS/Tire Rack) | M |
| Collector tier + pricing test | Tiering ladder, gate instrumentation, price experiments | M |

### Phase 3 — Network effects + B2B  *(thesis: the data and the chain of custody become the business)*

| Workstream | Deliverable | Effort |
|---|---|---|
| Shop Edition | Stamped digital service records that auto-populate customer Garages | XL |
| Community / build following | Build-thread replacement; follow garages | XL |
| Telematics / OBD-II | Auto mileage + DTC capture (kills manual odometer entry) | XL |
| Aggregated data products | Anonymized reliability/cost benchmarks (opt-in only) | L |
| Partnerships | Agreed-value insurance, warranty, PPI networks | M |
| Marketplace foundations | "Every car here has receipts" — history-backed listings | XL |

---

## 2. Data architecture — every area of data

This is the most important architecture decision in the whole plan. **Lock the canonical,
normalized model now, while data volume is tiny and migration is cheap.** Free-text blobs
are a moat killer; structured-from-day-one is the moat.

### 2.1 Data layers
1. **Operational store (exists):** Firestore — per-user, owner-scoped, offline-first.
   Stays the system of record for live app data.
2. **Canonical normalized model (build):** the *shape* every entry conforms to so it can be
   rolled up across the fleet. Same models on device (`Garage/Core/Models/`) and in the
   warehouse.
3. **Analytical store / warehouse (build):** BigQuery, fed from Firestore via the Firebase→
   BigQuery export + scheduled transforms (dbt-style). This is where the moat lives and where
   benchmarks/predictions are computed. **Never** query Firestore for analytics.
4. **Derived/aggregate tables (build):** anonymized, k-anonymity-gated rollups by platform —
   the only thing that ever powers cross-user features or leaves the system as a product.

### 2.2 Core canonical entities (extend what's in `Core/Models/`)

```
Vehicle
  vin (decoded ↓), year, make, model, trim, engine_code, displacement,
  transmission, drivetrain, body, market/region, production_seq (rare cars),
  acquired_at, acquired_mileage, status {daily|track|stored|project|sold},
  current_value (linked to market feed)

VehicleVinDecode      // from VIN-decode integration; the join key for ALL fleet rollups
  squish_vin, plant, engine_family, options[], factory_schedule_id

MaintenanceEvent      // canonical taxonomy — NOT free text
  job_type (controlled vocab), system (engine|brakes|drivetrain|...),
  performed_at, mileage, who {DIY|shop}, shop_ref, labor_hours, labor_cost,
  parts[] (→ Part w/ number, brand, qty, unit_cost), fluids[] (→ Fluid),
  total_cost, currency, source {manual|scanned|telematics|shop_feed},
  verification {self|receipt|shop_stamped|vin_matched}, documents[]

FailureEvent          // ★ the gold — real-world reliability by platform
  component, system, mileage_at_failure, age_at_failure, symptom,
  resolution (→ MaintenanceEvent), cost, catastrophic{bool}

OilAnalysis           // normalized lab result
  lab, sampled_at, miles_on_oil, oil_brand_grade,
  wear_metals_ppm{fe,cu,al,cr,pb,...}, viscosity, tbn, fuel_dilution,
  coolant{bool}, flags[], recommendation

Consumable            // life tracked by USE, not just calendar
  type {brake_pad|rotor|tire|fluid|clutch|...}, installed_at, install_mileage,
  street_miles, track_hours, est_remaining, conditions

TrackSession
  track, date, weather, ambient/track_temp, laps[] (time, sector),
  setup{tire_pressures_hot/cold, alignment, damper, swaybar, fuel},
  datalogs[] (DME/AFR/boost/timing), incidents[], consumable_deltas[]

Document              // receipts, stickers, titles, dyno sheets, policies
  kind, storage_ref, ocr_text, extracted_event_ref, verification, vault{bool}

MicroSurveyResponse   // one-question popups → qual↔quant join (see §5.3)
  user_id, question_id, question_version, response_value, response_text?,
  trigger_context, session_id, vehicle_id?, answered_at,
  state_snapshot{tier, tenure, completeness_bucket, vehicle_count, lifecycle}
  // same identity + timestamp space as analytics events → joinable in BigQuery

MarketValue (time series) · Recall (exists) · TSB · Reminder (exists) ·
Warranty (exists, + Magnuson-Moss aftermarket-protection records)
```

Two controlled vocabularies are the backbone and must be versioned: **`job_type`** and
**`component`/`system`**. They are what make "every 2015 SQ5 water-pump failure" a queryable
fact instead of 400 different spellings. Build a mapping layer so scanned/NL input snaps onto
the canonical terms (AI does the snapping; humans confirm).

### 2.3 Data governance & lineage
- **Ownership:** the user owns their records, full stop. This is a legal and trust pillar
  (see §8) and a marketing pillar (see §10).
- **Provenance tier on every event** (`self < receipt < shop_stamped < vin_matched`) — drives
  how much weight the passport gives it and how trustworthy the moat is.
- **Soft-delete + export-on-demand** (data portability obligation and a trust feature).
- **Consent ledger:** explicit, revocable per-purpose consent for aggregate/anonymized use.
  Mirrors the brain's `DECISION_LEDGER` philosophy — durable, append-only, auditable.
- **Schema migrations are protected-surface decisions** — route through consensus; a sloppy
  migration corrupts the moat.

---

## 3. Integrations — inbound data + outbound action

The product's value scales with how much of the record it can populate *without typing* and
how many places it can act on the user's behalf.

### 3.1 Inbound (feed the record / the moat)
| Integration | Purpose | Build vs buy | Priority |
|---|---|---|---|
| **VIN decode** (NHTSA vPIC free + commercial enrichment e.g. DataOne) | The join key for all fleet rollups; auto-fill vehicle specs | Buy/API | P1 |
| **OEM maintenance schedules** | Factory-correct intervals → auto-reminders | Buy/license or build per-platform | P1 |
| **NHTSA recalls** (exists) | Recall alerts | Have it | — |
| **TSBs / known-issue DB** | Enrich predictions with bulletins + community failures | License (e.g. ALLDATA-class) + own DB | P2 |
| **Market value** (Black Book / J.D. Power / enthusiast indices, BaT comps) | Current value, equity, depreciation | Buy/API | P2 |
| **Track timing hardware** (RaceChrono, AiM, Garmin Catalyst, Apex Pro, Harry's LapTimer) | Import laps/datalogs | File import + APIs | P2 |
| **OBD-II / telematics dongle** | Auto mileage + live DTCs (the holy grail) | Hardware partner or BLE OBD | P3 |
| **Email forwarding inbox** | Forward a parts order / shop invoice → auto-parse | Build (parse pipeline) | P2 |
| **Fuel/charging** (optional) | MPG/efficiency, EV charge sessions/cost | API/import | P2 |

### 3.2 Outbound (act for the user / monetize)
| Integration | Purpose | Priority |
|---|---|---|
| **Parts retailers** (FCP Euro, ECS Tuning, Tire Rack, RockAuto, RealOEM lookups) | Service-due → parts list → buy (affiliate) | P2 |
| **Payments** (RevenueCat exists; Stripe webhook exists) | Subscriptions + transactional passport/report sales | Have base |
| **Insurance / warranty / PPI** (Hagerty-class agreed-value, extended warranty, inspection networks) | Opt-in high-quality referrals | P3 |
| **Apple Wallet** | Passport / "car pass" artifact | P3 |
| **Calendar / reminders** | Service due dates to the user's calendar | P2 |

**Integration engineering principle:** every external feed lands through an **adapter that
normalizes onto the canonical model** before anything else touches it. No raw vendor shapes
leak into the app or warehouse. This keeps vendors swappable and the moat clean. Functions
runtime (TypeScript/Node 22) is the right home for adapters; keep keys server-side per
existing `claudeProxy` pattern.

---

## 4. AI program — the highest-leverage surface

Thesis restated: **AI's first job is to kill data-entry friction (fills the moat); its second
is to turn accumulated data into advice (drives retention + willingness to pay).** Keep the
`ClaudeService → server proxy` pattern; extend, never bypass.

### 4.1 Feature ladder (priority order)
1. **Universal document ingestion** (generalize the Blackstone parser). Multimodal Claude on
   any invoice/handwritten receipt/parts email/window sticker/dyno sheet → structured entries
   mapped to canonical models. *Biggest single unlock.* (P1, L)
2. **Natural-language / voice logging.** "Changed oil, Motul 8100 5W40, 7qt at 78,340, rotated
   tires" → structured entries. For the guy who just rolled out from under the car. (P1–P2, M)
3. **Advisor chat grounded in the car.** RAG over the user's history + OEM schedule + fleet
   benchmarks + TSBs. "What's due next?" "Is this oil consumption normal for this engine?"
   Photo/audio triage of a cold-start tick. Engagement engine + premium feature. (P2, L)
4. **Oil-analysis intelligence (deepened).** Plain-English explanation, trend over time,
   fleet baseline for that engine, interval recommendation, rising-wear-metal flags. (P2, M)
5. **Predictive maintenance narratives + parts lists** with cost estimates → ties to commerce.
   (P2, L)
6. **Resale listing generator.** From documented history + mods + photos → BaT-quality writeup
   + spec sheet. Connects the moat directly to the wedge. (P2, M)
7. **Build-thread / spreadsheet importer.** Point at a forum thread or messy sheet → AI
   reconstructs structured history. Onboarding accelerant for veterans. (P3, M)

### 4.2 Model & cost strategy
| Job | Model class | Why |
|---|---|---|
| OCR/extraction | Haiku-class | High volume, cheap, high ROI; confirm-before-save catches errors |
| Term normalization (snap to vocab) | Haiku-class + rules | Deterministic where possible |
| Advisor chat / interpretation | Sonnet-class | Reasoning over context |
| Hard diagnostics / listing prose | Sonnet/Opus-class, gated | Quality where it pays |

- **Structured outputs / tool use** so AI maps *directly* into Codable models, validated —
  no fragile text parsing.
- **Confirm-before-save UX** (already used on oil autofill): both a safety control and a
  human-verified training signal. Keep it everywhere AI writes data.
- **Cost discipline:** per-tier token budgets, aggressive caching, cheap model first with
  escalation only on low confidence.
- **Privacy:** per-car RAG is scoped to the user's own data only. Fleet comparisons use
  **aggregated/anonymized** stats, never another user's raw records.

### 4.3 AI quality, safety & eval
- **Eval harness** for extraction accuracy (field-level precision/recall on a labeled receipt
  corpus) and advisor groundedness — wire it into CI the way `consensus.py`/`scope_guard.py`
  self-tests are wired. No AI feature ships without an eval gate.
- **Liability framing:** diagnostic/advisory output is *informational, not a mechanic's
  diagnosis*; surface that in-product (see §8).
- **Adversarial review:** route AI-feature changes through the immune-system workflows
  (`async-commit-review`, finder→refuter) before release.

---

## 5. Metrics & analytics — tracking that scales as it grows

Maintenance apps are **inherently low-frequency** — measuring them like a daily-engagement app
is the classic mistake. Measure activation, completeness, and quarterly retention.

### 5.1 Metric stack
| Layer | Metrics | Source |
|---|---|---|
| **Activation** (leading indicator) | % add vehicle · log 1st entry · attach receipt · run 1st export; time-to-aha | Product analytics |
| **Aha definition** | 1 vehicle + 3 structured entries + 1 receipt | Derived |
| **Retention** | Monthly/quarterly cohort curves; "logged this quarter"; **record completeness** | Cohort tables |
| **Conversion** | Trial→paid, free→paid, **which `ProGateView` converts** | RevenueCat + events |
| **Virality** | Transfers initiated/completed, passport views, invite→install (k-factor) | Events |
| **Monetization** | MRR/ARR, ARPU, LTV, LTV:CAC, logo+revenue churn, expansion, payback | RevenueCat |
| **Quality/ops** | Crash-free %, `claudeProxy` parse latency + success, sync-conflict rate, fn errors | Crashlytics + fn logs |
| **Moat health** | Active Documented Vehicles, events/platform, distinct VINs, provenance mix | BigQuery |

### 5.2 Instrumentation plan (do this in Phase 1)
- **Event taxonomy, versioned and documented** (a `docs/analytics/EVENTS.md`). Core events:
  `vehicle_added`, `entry_logged{type,source}`, `document_attached`, `ai_scan_started/
  confirmed/edited`, `export_run{format}`, `passport_viewed`, `transfer_initiated/completed`,
  `gate_viewed{gate_id}`, `gate_converted{gate_id}`, `reminder_fired/acted`,
  `survey_shown{question_id,version,trigger}`, `survey_answered{question_id,value}`,
  `survey_dismissed{question_id}`.
- **Every Pro gate fires an impression + outcome event** so you know *which* gate sells.
- **Tooling:** product analytics (PostHog self-host for data ownership, or Amplitude for
  speed); RevenueCat for subscription truth; Crashlytics (exists) for stability; BigQuery for
  moat + cohort analysis. One identity key joins them.
- **Privacy-respecting:** no PII in event payloads; honor consent; reflect in
  `PrivacyInfo.xcprivacy`.

### 5.3 In-app micro-surveys — one-question popups (the qual↔quant join)

A lightweight **single-question popup** layer threaded through the app. One question, one tap,
dismissible, never blocking a task. It is not a feedback gimmick — it is a *first-class
instrumentation surface* that captures the **"why" behind the behavioral data**, enriches the
moat, and feeds the AI. The defining requirement is that **every response is linkable** to the
user, the moment, the vehicle, the subscription state, and the analytics event stream — so qual
answers and quant behavior can be joined in the warehouse later.

**Why it earns a place (wedge + moat + revenue, all at once):**
- **User metrics:** satisfaction, friction, feature demand, "why did you do that."
- **Business metrics:** willingness-to-pay, purchase/sell intent, upgrade blockers, attribution.
- **Moat enrichment:** a single tap permanently enriches the structured dataset (e.g. daily vs
  track car, DIY vs shop). The popups *populate* the moat, not just measure sentiment.
- **AI signal:** a CSAT prompt right after an AI scan is a labeled training/eval signal for the
  ingestion model — the survey layer improves the AI layer.

**Question taxonomy** (purpose-segmented so it's never just NPS spam):

| Class | Example (single-question) | Trigger | Value |
|---|---|---|---|
| **Experience / CSAT** | "Was that scan accurate?" | right after `ai_scan_confirmed` | UX + **AI eval signal** |
| **Satisfaction / NPS** | "How likely to recommend Garage?" | sparingly, post-aha | retention proxy |
| **"Why" probe** | "What brought you to log this today?" | after `entry_logged` (rare) | intent insight |
| **Attribution** | "How did you hear about Garage?" | onboarding | CAC/channel truth |
| **Willingness-to-pay** | "Would predictive maintenance be worth $X/yr?" | near a `gate_viewed` | **pricing** |
| **Sell/purchase intent** | "Planning to sell this car within a year?" | on vehicle detail | **wedge** — predicts passport/transfer + converts |
| **Upgrade blocker** | "What's keeping you from Pro?" | on paywall dismiss | **conversion** |
| **Prioritization** | "Which would you use most?" | periodic, targeted | roadmap |
| **Moat enrichment** | "Is this your daily, weekend, or track car?" / "Wrench yourself or use a shop?" | after vehicle add | **moat segmentation** |

**Linking architecture — the part that matters.** Each answer is written as a canonical
`MicroSurveyResponse` (see §2.2), carrying:
- `user_id` / anonymized analytics id (**same identity space as behavioral events**),
- `question_id` + **`question_version`** (versioned so question changes never corrupt
  longitudinal analysis),
- `response_value` (structured: select index / scale) + optional `response_text`,
- `trigger_context` (the event/screen/Nth-occurrence that fired it) + `session_id`,
- `vehicle_id` (when vehicle-scoped),
- **a lightweight state snapshot at answer time** — tier (free/pro/collector), tenure,
  record-completeness bucket, vehicle count, lifecycle stage,
- `timestamp`.

Responses land in Firestore (operational) **and export to BigQuery alongside events** (§6), on
the same identity + timestamp keys, becoming just another fact table joinable to behavior,
subscription state, and moat data. The state snapshot makes the join robust even as the user's
state later changes. That is the concrete "future way of linking them": in analysis you can ask
*"do users who answer 'selling within a year' convert to Pro at higher rates?"*, *"does NPS
correlate with record completeness?"*, *"which segment finds AI scans inaccurate?"* — qual
cross-tabbed against quant, by cohort.

**UX & frequency discipline** (this is how you avoid tanking retention):
- One question, one tap, always dismissible; **never blocks** the underlying task.
- **Global survey budget** (e.g. ≤1 prompt per N sessions / cooldown days) + **per-question
  no-repeat** (never re-ask an answered question for that user).
- **Context-triggered, not random** — fire off the event taxonomy so the right question hits at
  the right moment (CSAT after the action, WTP near the paywall, sell-intent on vehicle detail).
- **Segment targeting** — only ask relevant users (no "rate the track suite" to someone with no
  track sessions).
- **Global opt-out** in settings; a dismissal is itself a logged signal.
- The response submission and the dismissal are **both analytics events**
  (`survey_shown`, `survey_answered`, `survey_dismissed` — see §5.2).

**AI angle.** AI prioritizes *which* question to ask next given what's already known (fill
profile/moat gaps, never re-ask), and synthesizes occasional free-text micro-responses into
themes at the aggregate level so open-ended answers don't drown the team in manual reading.

**Legal/privacy.** No PII in survey payloads; responses governed by the same consent ledger and
purpose-binding as other analytics (§8); declared honestly in `PrivacyInfo.xcprivacy`.
Aggregate/anonymized for any cross-user use.

**Build note.** Ship a small **survey engine**: a remote-config-driven question bank
(question id/version, type, trigger rule, target segment, cooldown), a frequency-cap/eligibility
resolver on device, a reusable one-question card/sheet in `Garage/Design/`, and the
`MicroSurveyResponse` write path into Firestore→BigQuery. Questions are data, not code, so the
team can add/retire questions without shipping a build.

### 5.4 Decision cadence
Weekly: activation + conversion + ops. Monthly: cohort retention + MRR + moat growth.
Per-feature: ship behind a flag, define the success metric *before* launch, read it after.

---

## 6. Infrastructure & platform

Current stack is sound (Firebase + Functions + XcodeGen + the CI gate + the brain). Additions
are about analytics scale, observability, and getting ready for B2B/real-time without
re-platforming.

### 6.1 Build it out
- **Warehouse:** BigQuery + Firebase→BQ export + scheduled transforms (dbt). The analytical
  backbone; **start in Phase 1 even at low volume** (migration is cheap now, brutal later).
- **Adapter/integration tier:** Functions modules per external feed (VIN, OEM, market, TSB,
  parts), each normalizing to canonical model. Rate-limit + cache + circuit-break each one.
- **AI orchestration:** extend `claudeProxy` into a small service with model routing, caching,
  token budgeting, and an eval hook.
- **Observability:** structured logs + traces + dashboards for parse latency, fn errors, sync
  conflicts, AI cost/req. The landmine "verify the *running* image, not a deployed ✅ note"
  applies — monitor reality.
- **CI/CD evolution:** the deterministic gate (`scripts/ci/*`) remains sole promoter; add
  Functions integration tests, the AI eval gate, and staged deploys (dev→prod) for functions.
- **Feature flags + remote config** for staged rollouts and pricing experiments.
- **Secrets:** stay off-device (existing posture); rotate; never in agent prompts (existing
  scope-guard rule). Add per-environment secret management for the new vendor keys.

### 6.2 Scale & cost posture
- Firestore stays operational/owner-scoped; analytics never hits it. Index discipline
  (`FirestoreIndexes.json`) as collections grow.
- Storage (receipts/photos/PDFs) will be the cost driver as documents pile up — lifecycle
  rules, thumbnailing, and tiered storage for cold documents.
- Functions cold-start + AI token spend are the recurring-cost levers; cache and route models
  accordingly.

### 6.3 Platform reach (staged)
iOS-first remains correct (Architecture is locked to native iOS per doctrine). Forward:
**Apple Watch** (log fuel at the pump, glance reminders), **CarPlay** companion (hands-free
log + fuel), **read-only web** (the passport — already required for sharing), and only later a
broader web/Android decision *as a product call, not a re-platform of the locked iOS app*.

---

## 7. Security & privacy engineering

The data asset is only legitimate — and only sellable at the B2B layer — if security and
consent are airtight. This is existential, not hygiene.

### 7.1 Current posture (keep)
Default-deny Firestore rules + per-owner checks · non-deletable user docs · App Check via
`AppIntegrityService` · Claude key off-device in `claudeProxy` · Keychain via
`SecureStoreService` · privacy manifest present.

### 7.2 Threat model & controls (extend)
| Threat | Control |
|---|---|
| Cross-user data access | Owner-scoped rules audited per new collection; rules are protected-surface (consensus) |
| Document leakage (receipts have PII/VINs) | Signed, expiring URLs; passport shares are explicit, revocable, scoped |
| AI prompt-injection via uploaded docs | Treat document text as **data, not instructions**; never let OCR'd content drive actions |
| Account takeover | Sign in with Apple/Google (no passwords — good); add transfer-confirmation safeguards |
| Aggregate re-identification | k-anonymity threshold on every aggregate; suppress small cells; never expose raw rows |
| Vendor key compromise | Server-side only, rotation, least-privilege, per-env isolation |
| Transfer abuse (steal a car's history) | Verified two-party transfer handshake; audit log; reversible window |

### 7.3 Privacy by design
- **User owns and can export/delete** their data (portability + deletion = legal duty *and*
  trust feature).
- **Purpose-bound consent** for aggregate use, revocable, logged.
- **Data minimization** in analytics events; **anonymization/aggregation** for anything that
  leaves the user's own scope.
- **`PrivacyInfo.xcprivacy` kept honest** as data uses expand (Apple requires accurate
  declarations; mismatches risk App Store rejection).

---

## 8. Legal & compliance boundaries

Where the lines are, and the artifacts you must produce. (Engineering-grade summary, not legal
advice — get counsel before B2B data sales and before any diagnostic-liability framing ships.)

| Area | Boundary / requirement | Artifact |
|---|---|---|
| **Data ownership** | Users own their records; you hold a limited license to operate + (opt-in) aggregate | ToS + clear ownership clause |
| **Privacy law** | CCPA/CPRA (CA), GDPR (EU) if you have EU users: access, deletion, portability, opt-out, purpose limitation | Privacy Policy, DSAR/deletion flow, consent ledger |
| **Selling aggregate data** | Lawful **only** if anonymized, aggregated, consented, opt-in; "sale/share" disclosures under CPRA; never individual records | Data-use disclosure, opt-out, k-anon spec |
| **AI diagnostics** | Frame as *informational, not professional diagnosis*; no guarantees; disclaim | In-product disclaimer + ToS clause |
| **Affiliate commerce** | FTC endorsement rules (16 CFR Part 255): disclose affiliate relationships clearly | Disclosure in UI near parts links |
| **Magnuson-Moss Warranty Act** | A *feature hook*: aftermarket parts don't auto-void warranty; help users document this — but don't give legal advice | Documentation feature + careful copy |
| **App Store** | Apple data-use + privacy-manifest rules; subscriptions via StoreKit/RevenueCat; no deceptive gating | Accurate `PrivacyInfo.xcprivacy`, review-safe paywall |
| **Shop Edition (B2B)** | Data-processing agreements; who owns shop-entered records vs customer records | DPA, B2B ToS |
| **Marketplace (future)** | Marketplace/seller liability, payments/escrow, disclosure of history accuracy | Separate legal track |
| **International** | Market/region field already in model; tax + privacy vary by region | Localized policies as you expand |

**Hard line:** never sell or expose individual user records. One breach of that destroys the
enthusiast trust the entire brand runs on. The B2B data product is *aggregate-only, opt-in,
anonymized* — design the pipeline so raw individual data *physically cannot* leave (§2.1
derived/aggregate tables + k-anon gate).

---

## 9. Design & prototyping

Design system already exists (`Garage/Design/`: Theme, cards, buttons, banners, skeleton/
shimmer, search, badges, empty states). The work is extending it for the new surfaces and
prototyping the few flows that make or break adoption.

### 9.1 Design principles
- **The log should feel effortless** — the entire wedge depends on logging not feeling like
  a chore. Friction here is the #1 product risk; design (and AI) attack it directly.
- **Enthusiast-grade, not generic.** This audience has taste; the app should feel like a
  precision instrument, not a fleet-management spreadsheet.
- **Trust is visual.** Provenance tiers, verification badges, and the passport must *look*
  credible — that look is what converts a forum buyer.

### 9.2 Flows to prototype first (highest leverage)
1. **AI scan → confirm → saved entry** (the core loop; nail the confirm UX).
2. **Resale Passport** (the thing strangers see; it sells the app to non-users).
3. **Ownership transfer handshake** (two-party, trustworthy, reversible window).
4. **Onboarding to first aha** (add vehicle → first scan → first export, < a few minutes).
5. **Advisor chat** grounded in the car (Phase 2).

### 9.3 Prototyping workflow
- Prototype the above as interactive mockups before building; test with 5–8 real enthusiasts
  (your own network + a target forum).
- Keep prototypes in `docs/research/` per the brain's convention; treat UX bets that touch
  conversion as testable hypotheses with a metric.
- Reuse `Garage/Design/` tokens so prototypes translate cleanly to SwiftUI.

---

## 10. Marketing & growth

Positioning, channels, and the loops. The audience is reachable, opinionated, and
community-clustered — perfect for organic + content + viral motions over paid.

### 10.1 Positioning
**"The serious car owner's record that pays you back at resale."** Enthusiast-grade detail,
Carfax-grade trust, effortless because AI does the typing. Own the emotional truth: *your car
deserves a real history, and that history is worth money.*

### 10.2 Built-in viral loops (the cheapest growth)
- **Passport sharing** — every shared listing on a forum/marketplace is an ad to the exact
  audience. Watermark/branding on the public passport.
- **Ownership transfer** — every sale onboards the next owner with history in hand.
- **Resale-listing generator** output naturally credits Garage.
- Instrument all three (k-factor in §5).

### 10.3 Content & SEO moat
The dataset is also a content engine: *"the real cost of owning a 997.2 over 5 years,"* *"what
actually fails on a B8 S4 and at what mileage,"* *"track-day consumable budgets by car."*
These are high-intent, high-SEO, and only *you* have the data to write them credibly. This is
defensible content marketing that compounds with the moat.

### 10.4 Channels
- **Community-first:** enthusiast forums, marque clubs, subreddits, Discords, track-day orgs,
  YouTube wrenching/ownership channels (review/affiliate fit).
- **Founder voice / build-in-public** for the early enthusiast crowd.
- **Partnerships** with shops (Shop Edition is also a distribution channel), parts retailers,
  and track organizers.
- **Paid only after** activation/retention are proven and LTV:CAC supports it — and LTV here
  is high (multi-year, multi-car, compounding data), which eventually justifies real CAC.

### 10.5 Launch sequencing
Phase 1 → niche launch to one or two enthusiast communities (Viper/Audi/BMW/Porsche-adjacent
fits the reference vehicles). Earn the wedge, gather testimonials of actual resale lift, then
widen.

---

## 11. Monetization execution

A single Pro tier under-monetizes both the AI-heavy user and the collector. Ladder + revenue
lines beyond subscriptions.

### 11.1 Tier ladder
| Tier | Includes | Indicative price |
|---|---|---|
| **Free** | 1 vehicle, manual logging, basic reminders, limited history | $0 |
| **Pro** | 3–5 vehicles, full AI scanning, full export + Passport, OEM schedules, oil interpretation, stats | ~$50–120/yr |
| **Collector/Enthusiast** | + track suite, datalog storage, predictive maintenance, fleet/vault, higher AI limits, priority advisor | ~$150–250/yr |
| **Lifetime** (optional) | One-time; great early cash + LTV if modeled | one-time |

**Free tier is a moat investment** — don't over-gate the *input* loop; you *want* the data in,
and the accumulated history is the switching cost that converts later. Gate *output and depth*,
not logging.

### 11.2 Pricing & gates
- Anchor to value: *"documenting your car can add $X,XXX at resale."* This audience spends
  thousands on the cars; price accordingly, annual-first.
- **Upgrade moments at value realization:** running an export, hitting the vehicle limit,
  scanning a document, listing a car. Instrument every gate (§5) and optimize the winners.
- A/B price and gates via remote config; read conversion by `gate_id`.

### 11.3 Revenue lines beyond subscriptions
- **Affiliate parts commerce** — reminder → exact parts list → buy. High intent, high
  conversion, disclosed and tasteful (the *right* part), not ads. Meaningful recurring revenue.
- **Transactional passport/report** at point of sale — $20–50 verified report is trivial
  against a $60k car; willingness-to-pay peaks here.
- **Shop Edition SaaS** — two-sided flywheel: shops pay; their stamped records raise consumer
  trust and feed clean data at the source.
- **Opt-in partnerships** — agreed-value/track/collector insurance, extended warranty, PPI
  networks; high-quality referrals where you know the exact car.
- **Aggregated data products** (long-term, careful, anonymized/opt-in only) — benchmarks to
  valuation firms, insurers, warranty underwriters, OEMs. Compounding asset, high margin.
- **Marketplace take-rate** (endgame) — history-backed listings; BaT-meets-Carfax.

---

## 12. Innovations, unique features & forward ideas

The bets that differentiate Garage from "yet another maintenance log." Roughly near→far.

**Near-term differentiators**
- **The car's digital twin that travels across owners.** VIN-anchored chain of custody —
  unbroken documented history that compounds in value with each transfer. No incumbent has the
  enthusiast-grade version of this.
- **Magnuson-Moss aftermarket-protection records.** Document that your mods don't void
  warranty; enthusiasts care intensely and no app helps them here. Great feature *and* content.
- **Consumables by use, not calendar.** "~2 track days left on these pads." Track owners have
  nowhere good to track this.
- **Provenance-weighted history.** Shop-stamped/VIN-matched records visibly outrank
  self-reported — trust you can *see*, which is what closes a sale.

**Mid-term**
- **Sentinel mode.** Background monitor for recalls + TSBs + known-issue patterns by platform;
  proactive "heads-up, this is starting to fail on your engine around now" alerts.
- **Ownership sinking-fund.** "Set aside $X/month for *this specific car*" from predicted
  maintenance — financial planning enthusiasts will love.
- **AR "where is it" assist.** Point the phone at the engine bay → highlight the oil filter /
  drain plug / sensor for this exact engine.
- **CarPlay + Watch micro-logging.** Log fuel/mileage at the pump hands-free — chips away at
  the manual-entry problem.

**Forward / moonshots**
- **OBD-II / telematics auto-capture.** The structural fix to manual odometer entry: automatic
  mileage + live DTCs + drive data. The single biggest forward bet — it removes the last big
  friction and unlocks real-time data and richer reliability signals. (XL, partner-dependent.)
- **EV battery-health moat.** Degradation curves by model/pack are *barely tracked well
  anywhere* and increasingly valuable to buyers, insurers, and OEMs. A wide-open extension of
  the moat as the fleet electrifies — start capturing structured battery/charge data early.
- **History-backed marketplace.** "Every car here has receipts." The documentation moat is
  exactly what makes a trusted enthusiast marketplace credible. Endgame.
- **Insurance/usage partnerships powered by verified history** — agreed-value and usage-based
  products where Garage's verified record is the underwriting signal.

---

## 13. Org, governance & how the brain runs this

This plan executes under the existing multi-LLM governance — that's a genuine advantage for a
small team.

- **Substantive bets here go through consensus** (≥3 voters, 2/3, no veto, logged) before
  becoming roadmap commitments — especially the canonical schema, pricing, B2B data, and any
  re-platform temptation (already Tier-D'd; stays native iOS).
- **Schema + rules + pricing config are protected surfaces** — changes halt for review.
- **Each AI feature ships with an eval gate** wired into CI alongside the existing self-tests.
- **`HANDOFF.md` stays the single live next-step;** this file is the strategy, not the live
  pointer.
- **Sequence ruthlessly:** Phase N+1 doesn't start until Phase N's thesis is metric-proven.
  The biggest org risk is the brain's capacity tempting too many parallel bets — hold the line
  on the wedge.

---

## 14. Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| **Data-entry friction kills adoption** | Critical | AI ingestion is existential (Phase 1, top priority), not a nice-to-have |
| **Naive engagement metrics mislead** | High | Measure activation + completeness + quarterly retention, not DAU |
| **Privacy/trust breach** | Critical | Aggregate-only/opt-in/anonymized B2B; raw individual data physically can't leave; airtight consent |
| **Moat data is messy (free-text)** | Critical | Canonical normalized model + controlled vocab from day one |
| **Scope sprawl (community/marketplace too early)** | High | Phase gating; wedge-or-moat test on every feature |
| **AI cost / accuracy** | Medium | Cheap-model-first routing, caching, eval gates, confirm-before-save |
| **Vendor lock / feed changes** | Medium | Adapter layer normalizing to canonical model; swappable vendors |
| **Diagnostic liability** | Medium | "Informational, not a diagnosis" framing + counsel before launch |
| **Re-platform temptation** | Low (handled) | Doctrine-locked native iOS; recorded Tier-D verdict |

---

## 15. First 90 days — concrete next actions

A pragmatic Phase-1 kickoff. (Map to `HANDOFF.md` for the always-current single next step.)

1. **Lock the canonical data model** (§2.2) — write it as Codable models + a `docs/data/
   CANONICAL_MODEL.md` + versioned `job_type`/`component` vocabularies. *Consensus decision.*
2. **Stand up BigQuery export + first transforms** — even at low volume. Moat foundation.
3. **Generalize AI ingestion** — extend `claudeProxy`/`ClaudeService` from Blackstone-only to
   any-document, structured-output into canonical models, confirm-before-save UX. Build the
   extraction eval harness and wire it into CI.
4. **Ship full instrumentation** — `docs/analytics/EVENTS.md`, gate impression/outcome events,
   activation + cohort + conversion dashboards. Include the **micro-survey engine** (§5.3):
   remote-config question bank, on-device frequency-cap/eligibility resolver, a one-question
   card in `Garage/Design/`, and the `MicroSurveyResponse` write path into Firestore→BigQuery —
   so the qual↔quant join exists from day one. Seed it with a CSAT-after-scan question (also an
   AI eval signal) and the sell-intent question (wedge predictor).
5. **Build the Resale Passport** (read-only web) + **Ownership Transfer** handshake — the
   wedge + the viral loop.
6. **Integrate VIN decode + OEM schedules** — auto-fill specs + factory-correct reminders.
7. **Prototype + user-test** the AI-scan loop, passport, transfer, and onboarding-to-aha with
   5–8 real enthusiasts before/while building.
8. **Draft the legal foundation** — ToS (data ownership), Privacy Policy, consent ledger,
   affiliate + AI disclaimers; get counsel on the data-ownership and diagnostic clauses.

---

*Master plan generated 2026-06-29. This is strategy + sequence, not live state. Route
substantive bets through consensus, keep `HANDOFF.md` as the live pointer, regenerate this
file when the strategy shifts. Wedge: resale documentation. Moat: the normalized dataset.
Test every feature against both.*
