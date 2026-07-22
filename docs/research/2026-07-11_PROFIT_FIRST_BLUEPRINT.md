# Garage Profit-First Product Blueprint — ADOPTED PLAN (2026-07-11)

**Status:** GOVERNING product plan (operator directive 2026-07-11), superseding parts of
`2026-07-10_PRODUCT_EXPANSION_RESEARCH.md` as recorded below. Every commitment here remains
**subordinate to the standing VALIDATE-FIRST gate** (the buyer-value kill-test) and to the Five
Laws. Sources reconciled: (1) the 2026-07-10 research + Sol epistemic corrections (§13 there
governs where rhetoric outran evidence), (2) the merged 2026-07-10 hardening audit
(`reports/audit/2026-07-10_AUDIT_REPORT.md`), (3) the 2026-07-11 external profit-first review
supplied by the operator. Where sources conflicted, conflicts were resolved by **verification
or Law-1 re-vote — never by adopting the newest document's assertion.**

---

## 1. Thesis (corrected)

Garage's opportunity is a **quality-and-trust gap, not empty whitespace**. Competitors already
ship attachments, reports, multi-vehicle depth, and transfer; within the reviewed competitor
set, none was found to do well at **turning a shoebox of ownership evidence into a buyer-ready,
owner-controlled record in minutes** — with explicit event-level provenance (self-reported /
receipt-backed / shop-attested / OEM / third-party), redaction, completeness, and sale-time
presentation. That superiority is itself a hypothesis to be proven in-market, not a fact.

This is the 2026-07-10 wedge with Sol's corrections fully absorbed: *the whitespace claim is
downgraded; the evidence-transformation job is promoted.* The buyer-value premise (owners'
self-authored records earning buyer trust) remains a **hypothesis under test** — the kill-test
gate stays armed, and no resale-lift claim may appear in marketing until it passes.

Two linked jobs define the product:
1. **Sale-time Backfill & Passport** — import the messy past, confirm extracted facts, redact,
   preview a buyer dossier, pay to publish/export (high-intent, transactional).
2. **Ongoing Pro/Collector capture** — low-friction imports, reminders, evidence completeness,
   deep logs (recurring, retention-driven).

## 2. Claims register — external review vs. verification

| # | External-review claim | Verdict | Disposition |
|---|---|---|---|
| 1 | Resale documentation is NOT whitespace; category has the features | **ACCEPTED** — consistent with Sol correction #1 | Position on evidence quality/trust, not feature absence |
| 2 | Deep multi-vehicle ownership is not empty | **ACCEPTED** (AUTOsist floor, self-hosted options) | Win on speed, provenance, redaction, sale workflow |
| 3 | CARFAX proves adjacent WTP only, not owner-authored demand | **ACCEPTED** — already the standing R1 risk | Kill-test isolates the self-reported component |
| 4 | Motorkeep and Roadfolio are occupied by live vehicle apps | **SUBSTANTIALLY CORRECT** (verified 2026-07-11): Roadfolio = hard collision, live on both US stores since May–June 2026 (predating the scan); Motorkeep = impaired (motorkeep.ru exact-name/category live web product; no store app; .com still buyable) | Q5 recommendation WITHDRAWN (ledger row); fresh slate + professional clearance; operator decides |
| 5 | BaT/C&B ToS prohibit the planned comps scrape | **ACCURATE** (verified 2026-07-11): both ToS ban scraping verbatim; both carve out written permission; C&B Cloudflare-403s bots site-wide | Q4 extraction method superseded (ledger row): permission-first → licensed data → small-N manual → consented sellers → controlled experiments |
| 6 | 5% resale lift is unestablished | **ACCEPTED** — was already the pre-registered death condition | Measure price, sell-through, trust, WTP as separate outcomes |
| 7 | LTV math = platform-net receipts, not contribution | **ACCEPTED** | Price decisions on observed 90-day cohort contribution |
| 8 | Annual full-Passport credit cannibalizes the transaction SKU | **ACCEPTED + RE-VOTED** — unanimous ledger row 2026-07-11T17:37:16Z | Credit REMOVED; see §4 |
| 9 | 7-day trial is not established as optimal | **ACCEPTED** — matches prior "instrument 7 vs 14" | Test after measuring time-to-first-value |
| 10 | Vertical breadth ≠ differentiation | **ACCEPTED** — matches unanimous Q3 (cars-until-killtest) | Expansion gates unchanged (§9) |

## 3. Verified capability truth table (audited app-tree SHA `0333324`; branch head at review
time `f8fc79b`, intervening commits documentation-only)

Adjudicated 2026-07-11 by a 12-agent read-only sweep against the live code — every row cites
current file:line evidence, not report claims (landmine #9).

| # | Surface | Verdict | Evidence (current code) | Scope |
|---|---|---|---|---|
| 1 | Buyer-ready PDF export | **GAP** | `PDFExportService.swift:25` "Vehicle History: Not connected" placeholder; photos = heading only (`:39`); receipts = "included separately" text (`:43`); TPPDF text-only | Moderate — embed real history + images |
| 2 | Attachment ingestion | **GAP** | `AttachmentPicker.swift:38,42` never reads bytes (placeholder filenames only); `StorageService.swift:14` upload exists with **zero call sites**; `EntryFormViewModel.swift:17` `[String]` paths, typed `Attachment` never constructed | Medium — full slice: bytes→validate→checksum→strip-metadata→upload→link |
| 3 | Hosted Passport | **GAP** (never built) | No `hosting` key in `firebase.json`; only 3 CF exports; zero `public` grants in either rules file | Large — net-new, deferred behind gates (§8) |
| 4 | Commerce ledger | **GAP** | `revenueCatWebhook.ts:296-298` binary `subscription.{entitlement:"pro",isActive}` only; no one-time SKU/credit/refund ledger | Several days — deferred with Passport |
| 5 | AI entitlement | **GAP** | `claudeProxy.ts:370` App Check enforced, `:275` auth-only; `:58` flat `DAILY_OIL_ANALYSIS_QUOTA=5` for every uid; **never reads `users/{uid}.subscription`** though the webhook maintains it | Small/medium — **P0 wave 1** |
| 6 | Vehicle limit | **GAP** | `firebase.firestore.rules:25` ownership-only create; cap lives only in `VehicleService.swift:203` client Swift | Small/medium — **P0, mechanism tri-voted (§11)** |
| 7 | Export gating | **GAP** | `ExportView.swift:10` whole export sheet Pro-gated ("Exports are part of Pro"); `ExportViewModel.swift:54` CSV capped at 500 entries | Small — **P0 wave 1** (free-CSV promise) |
| 8 | Product analytics | **GAP** (no intentional event schema; SDK automatic collection not yet audited) | FirebaseAnalytics + Crashlytics linked in `project.yml:81,85` but **zero call sites app-wide**; `analyticsOptOut` (`User.swift:11`) is a dead field — not persisted, not loaded, gates nothing; privacy manifest declares empty collected-data types while the SDK may auto-collect | Medium — **P0 wave 1, privacy-first** |
| 9 | Privacy/deletion | **GAP** | No Delete Account anywhere (`SettingsView.swift:20` sign-out only); no CF deletion/purge; `PrivacyInfo.xcprivacy` declares **empty** collected-data types (inaccurate) | Moderate — **P0 wave 2** |
| 10 | Orphan surfaces | **PARTIAL** (claim partly stale) | Recalls + reminders fully wired (GarageView→WarrantyService; Settings→ReminderService + dashboard). Genuinely orphaned: `ClaudeService.swift` — zero call sites. No notification/push layer exists at all | Small — wire oil-analysis entry point |
| 11 | Audit delta | (from audit report) | Payment pipeline identity-gated end-to-end; webhook hardened; CSV injection fixed; rules deny subscription self-grant. **All inert until `firebase deploy` (operator gate)** | — |
| 12 | Brain queue | **RECLASSIFIED** | `async-commit-review.js:406` top-level `return` is illegal as a plain Node module BUT is the documented Workflow-harness convention (body-wrapped async fn; `instrument-audit.js` identical). Handoff's "syntax bug" was a misdiagnosis — verify by executing via the Workflow harness, don't "fix" a working script | Verify-in-place |

**Net:** the external review's product-capability picture was **accurate** — the audit hardened
the trust boundary underneath the features, but the commercial promise (evidence dossier,
ingestion, free CSV, analytics, deletion) is still unbuilt. Phase 0 is therefore *both*
research and product hardening.

## 4. Offer ladder v2 (post re-vote)

Q1's architecture survives with one structural amendment, one clarification, and pre-registered
price experiments:

| Tier | Launch default | Pre-registered test cells | Guardrails |
|---|---|---|---|
| **Free Logbook** | 1 vehicle, unlimited manual entries, reminders, **raw CSV free forever (complete, uncapped)**, **10 account-level oil-analysis PDF imports (lifetime)** | — | No ads ever; limits server-enforced; never promise unlimited cloud AI |
| **Garage Pro** | $4.99/mo · $34.99/yr (annual anchored, 7-day trial); **up to 5 vehicles** (vote 2026-07-11T18:03:36Z UNANIMOUS, supersedes Q1 "unlimited vehicles"); AI imports at a **disclosed fair-use ceiling of 5/day with `resetAt` surfaced** (vote 18:03:16Z majority, supersedes Q1 "unlimited OCR" — copy says "generous fair-use limits", never "unlimited") | Annual $34.99 / $39.99 / $49.99; monthly $4.99 / $5.99; trial 7 vs 14 | Winner picked on **90-day contribution per eligible user**, not raw conversion; changes from voted defaults return to the ledger |
| **Resale Passport** | **$34.99 one-time per vehicle (the Q1-voted default stands)**; Carfax/AutoCheck-anchored | $29 / $39 / $49 as pre-registered experiment cells only | Permanent artifact = portable PDF; hosted link has a **defined finite term** + revocation; support+servicing < 20% of net; no blanket "verified" label — event-level provenance taxonomy only |
| **Pro↔Passport relationship** | **NO full annual credit** (unanimous re-vote 2026-07-11, supersedes that clause of Q1). Active-Pro member discount 20–25% on Passport; A/B an explicit "Pro + Passport" paid bundle ($59–65) vs separate purchase; credits never accumulate | Bundle vs no-bundle | Kills the SKU-erasure + banked-credit servicing liability ($2.66–$9.03/annual-sub modeled burden) |
| **Collector** | NOT built | $99–149/yr concept, 10–15 vehicles | Entry gate: 10–15% of paid users manage 3+ vehicles or accept $99+; headroom secured by the Pro=5 cap (OPEN FORK #1 resolved 2026-07-11) |
| **Concierge Passport / Shop attestation** | NOT built | $99–199 concierge; free attestation pilot first | Shop SaaS only after paid design partners |

**OPEN FORK #1 — RESOLVED (2026-07-11T18:03:36Z, UNANIMOUS): Pro = 5 vehicles**, disclosed in
offer copy; Collector takes the 10–15 range later behind its demand gate. Rules still use
named constants (any future change is a re-vote + operator-gated rules deploy, never
"one-line" in the casual sense — Sol #3 noted client logic, copy, tests, and migration all
move together).

Apple Small Business Program: **operator checklist item** — verify eligibility, enroll, confirm
the effective commission before any contribution math uses 15%. Trust Pledge stands: no ads
ever, raw exports free forever, no price hikes on existing subscribers. The free AI allowance
is named truthfully: **"10 account-level oil-analysis PDF imports"** (per Firebase account, not
per person; the endpoint is oil-report extraction, not general OCR).

## 5. P0 engineering backlog (the implementation contract)

Enterprise bar: every item lands with tests, passes `./scripts/ci/*`, and is reviewed per the
MODEL ROUTING pre-main ritual. Waves are strictly ordered; an item ships only when its
acceptance criteria hold.

### Wave 1 — revenue protection + truthful promises + instrumentation foundation (NOW)

Authorized by the sequence-supersession vote (2026-07-11T18:03:04Z, UNANIMOUS): **this
enumerated list and nothing else** proceeds in parallel with the kill-test protocol doc; any
wedge/Passport-premise build stays blocked behind the protocol.

| ID | Item | Files | Acceptance criteria (Sol-blocker dispositions folded in) |
|---|---|---|---|
| **iOS-0** | Offer/paywall truth audit (Sol #4) | `SubscriptionView.swift`, `ReminderConfigView.swift`, paywall/gate copy | Every promise visible in the paywall/offer maps to a shipped, reachable feature or is suppressed: reminders un-Pro-gate (free tier promises them) or the free offer drops them — resolve per §4 table (free = reminders included); no "buyer-ready PDF"/attachment/AI claims while those surfaces are placeholder; audit output = claim→surface→status table committed with the change |
| **CF-1** | AI entitlement tiering (Sol #9, #10, advisory 5) | `claudeProxy.ts`, `revenueCatWebhook.ts` + tests | Tier selection and bucket consumption **in the same transaction** (`users/{uid}` read inside the quota txn); Pro: 5/day disclosed fair-use (vote 18:03:16Z) with `resetAt` (next UTC midnight) in denial details; Free: 10 lifetime (`usage_quotas/{uid}_lifetime`, transactional); webhook persists **authoritative `expiresAt`** where the event supplies it and the fail-closed predicate is `entitlement=="pro" && isActive && (expiresAt missing ∥ expiresAt>now)`; typed denial details `{reason: free_lifetime_exhausted \| pro_daily_exhausted, entitlementUsed, resetAt?}` so the client can detect purchase→webhook lag (`entitlement_sync_pending` UX); PDF magic/size validation **before** quota reservation; refund matrix: infra-failure refunds the consumed bucket only, billed HTTP-OK output never refunds; tests: free-exhausted, pro-daily, expiry-lapsed, tier transitions both ways, refund per tier, malformed-PDF-pre-quota |
| **iOS-1** | Free raw CSV, truthfully complete (Sol #12) | `ExportView.swift`, `ExportViewModel.swift`, `EntryService.swift`, `CSVExportService.swift` | Free users get a **retrievable .csv file** (share sheet/fileExporter), not a byte count; raw export defaults to **all-time** range; versioned null-preserving raw schema (nulls = empty cells, never `0`/`false`; all persisted fields included); stable **cursor pagination** in EntryService with tests for multi-page, equal-timestamp boundaries, no gaps/dupes; PDF stays Pro (`// WAVE-3` marker); complete free-tier UI journey test |
| **iOS-2** | Analytics + privacy foundation (Sol #13, #14) | new `Garage/Core/Services/Analytics/`, `ProfileViewModel`, `AppState`, `PrivacyInfo.xcprivacy`, Settings UI | **Privacy-first ordering:** Firebase Analytics collection default-disabled before `configure()`; enabled only after an explicit persisted preference; `analyticsOptOut` becomes a real persisted+loaded profile field with a Settings toggle; sign-out/account-switch resets to disabled; `PrivacyInfo.xcprivacy` declares actual collected data types; event dictionary v1 as typed constants with schema-version param, PII prohibition enforced in the type (no uid/email/VIN/free-text params), documented idempotency for `first_*` events; spy tests incl. **negative** emission (opt-out ⇒ zero events); client `purchase_completed` labeled non-authoritative (server joins are the revenue source of truth) |
| **iOS-6L** | AI wiring + typed error routing (Sol #11) | `ClaudeService.swift`, `AppError.swift`, one maintenance-entry call site | `ClaudeService` maps Functions errors (incl. `resource-exhausted` details) to typed `AppError` cases; minimal oil-analysis import affordance so the path is end-to-end exercisable; quota-denied UX routes free→paywall, pro→`resetAt` message, mismatch→sync-pending; AI analytics events land here |
| **RULES-1** | Server vehicle-count enforcement — **Mechanism A′** (re-vote 18:03:52Z UNANIMOUS; Sol #5, #6, #7, #8) | `firebase.firestore.rules` (**PROTECTED** — operator deploy gate), new purge Cloud Function, `VehicleService.swift` + emulator tests | **Create (client-bound):** allowed only when the same batch sets `users/{uid}.vehicleCount == get()+1 ≤ tierCap` AND `users/{uid}.lastVehicleOp == {id: vehicleId, op:'create'}` — one create per batch by construction; **`userId` immutable** on vehicle update; ordinary updates count-neutral; `vehicleCount`/`lastVehicleOp` writable only via the bound transition (subscription-style protection); **delete = client soft-delete tombstone only** (count-neutral `deletedAt`); trusted CF purges subcollections recursively + decrements counter (closes the orphaned-subcollection cross-tenant leak — Firestore doc-delete never removes subcollections); tierCap: free=1, pro=5 as named constants; **migration contract:** read-only inventory → per-UID counter backfill → anomaly report → race-free rollout order (backfill → rules → binary) with rollback; emulator suite: at-cap denial per tier, multi-create batch denied, standalone ±1 denied, corrupt counter types, ownership-transfer denied, missing user-doc/counter, downgrade-over-cap, replay; offline UX claims deferred until offline create/reconnect/rejection tests exist (Sol advisory 4) |

### Wave 2 — trust debt (privacy, deletion, evidence intake)
- **iOS-4/CF-3 Account deletion + data lifecycle:** in-app Delete Account (re-auth + confirm) →
  CF recursive purge (Auth user, Firestore tree, Storage files) + accurate
  `PrivacyInfo.xcprivacy` collected-data declarations. (Absorbs the audit's queued
  account-deletion/data-lifecycle suite.)
- **iOS-5 Attachment ingestion pipeline:** bytes → magic/MIME + size validation → checksum
  dedupe → EXIF/metadata strip → private Storage upload → typed `Attachment` linked to entry;
  golden-corpus tests per document type. (Prereq for any dossier claim.)
- **iOS-6 Wire `ClaudeService`:** SUPERSEDED by Wave-1 **iOS-6L** (added via Sol round-2
  blocker #11 disposition) — this Wave-2 entry is retained only as a tombstone; do not
  schedule it separately.

### Wave 3 — the sellable dossier (pre-Passport, still local/portable)
- **iOS-7 PDF evidence dossier:** real history, embedded photos/receipts, per-event provenance
  labels, completeness/"buyer-ready" component score (identity, coverage, recency, continuity,
  evidence, attachments, consent — components visible, never a magic number).
- **iOS-8 Competitor CSV importers + email-forward ingestion** (activation levers #1–2 from the
  2026-07-10 usability backlog).

### Deferred behind gates (unchanged)
Hosted Passport + commerce ledger (§8 controls; ≥50 paid-Passport gate), Collector build,
shop SaaS, motorcycles (three healthy car-contribution months + 200 paid Passports + no
unresolved trust failure), boats/RV later, homes/OBD/marketplace/community stay graveyarded
(evidence-dated, with reconsideration triggers per Sol #5).

Enterprise-hardening track (absorbed from audit queue): supply-chain checks, observability
acceptance criteria, Swift-6 concurrency hazard suite, CI Node pin 22.

## 6. Measurement (KPI tree v1)

Primary: **Buyer-Ready-7** (≥35% provisional), **living documented-vehicle retention** (M12
monthly survival ≥10%), **contribution per activated vehicle** (positive by D90; channel
LTV/CAC ≥3× fully loaded — founder time counts as CAC).
Drivers: time-to-first-meaningful-import (<10 min median), backfill completion (≥50% in ≤20
min), evidence-supported event share (≥50% for buyer-ready), activated→paid (≥6%), Passport
sale-intent attach (10–15% near $39).
Guardrails: critical extraction error <2–5%; Passport support <15 min median, disputes/refunds
<5%; p95 per-account variable cost within tier contribution.
All thresholds are **pre-registered operating hypotheses** — recalibrate only via a documented
governance decision after pilot variance is known. iOS-2 is the prerequisite for every number
in this section; **no paid scale while measurement is blind.**

## 7. Validation ladder (promotion gates)

1. **Instrumentation foundation** (renamed per Sol — full *measurement readiness* additionally
   requires the KPI-to-authoritative-source matrix in the protocol doc: exact numerators,
   denominators, cohorts, windows, dedupe semantics, and server-side revenue/refund/cost joins;
   a client `purchase_completed` event is never authoritative contribution) — iOS-2 + CF-1 +
   RULES-1 shipped; no known entitlement bypass.
2. **Lawful buyer-value study** — protocol doc (the queued kill-test deliverable) with
   permission/license/consent design per §11 evidence; pre-registered, blinded coding, powered.
3. **Concierge backfill** — 30–50 real owners; ≥50% buyer-ready ≤20 min; critical errors <2–5%.
4. **Activation** — ≥35% meaningful activation after ≥2 onboarding iterations.
5. **Subscription price** — cells per §4; select on 90-day contribution.
6. **Retention** — monthly M12 ≥10%; annual first renewal ≥30%.
7. **Passport payment** — ≥50 real paid transactions; attach ≥10–15% near $39.
8. **Repeatable channel** — 3 measured tests/channel; CAC ≤⅓ of 12-mo contribution LTV.

Failure at any rung triggers the pivot table (§10), not a quiet re-rationalization.

## 8. Passport truth & privacy boundary (design constraints, binding when built)

Private data never becomes public in place: **publication job → allowlist + redaction →
event-level evidence classification → versioned snapshot (append-only by application policy) →
sanitized public asset copies → hardened cached renderer.** Opaque revocable tokens (optional
expiry/PIN), VIN masked by default, EXIF stripped, noindex/no-referrer, no third-party scripts,
rate limits. Corrections supersede visibly — no silent mutation. **Terminology discipline
(Sol):** an unanchored hash is a *checksum*; "tamper-evident" may be claimed only with a
signed or externally anchored manifest plus immutable version history — and even then it
proves non-alteration, never that the service occurred ("verified" is reserved for third-party
attestation). Idempotent commerce ledger (purchase/grant/use/refund/revocation per vehicle)
before the first sale. One-time price funds a **defined hosting term** + permanent portable
PDF, never indefinite service.

## 9. Growth & expansion posture (unchanged verdicts, tightened economics)

Profitable-by-default; zero-CAC loops first (marque forums, competitor-migration importers +
SEO, specialist shops/PPI, auction photographers/detailers, buyer-share loop); **fully loaded
CAC always** (founder time is not free); paid acquisition only after CAC ≤⅓ contribution LTV
with <12-mo payback. Cars → (gates) → motorcycles → (separate validation) → boats/RV.
Success definitions are **illustrative scenarios, not forecasts or validated models** (Sol):
"bootstrapped" ≈ 3–10K payers funding 1–3 people and "scalable" ≈ 20–30K+ payer-years +
Collector/B2B ARPU — both pending real contribution, salary, support, tax, and infrastructure
assumptions from instrumented cohorts. The upside scenario (~$1.48M gross / ~$525K after
founder labor at 350K accounts, 24.5K payers) illustrates the *scale class* a large-profit
ambition requires; it carries no evidential weight.

## 10. Pivot / kill conditions

| Signal | Pivot |
|---|---|
| Docs matter, but buyers discount owner-authored evidence | Provenance/attestation-first (receipt/shop/OEM) |
| Buyers value dossier; owners won't maintain | Sale-time concierge/import product, not subscription-first |
| Subscription utility works; resale lift doesn't | Enthusiast logbook/intelligence; kill the premium claim |
| Neither buyer trust nor WTP | Stop the Passport-heavy thesis |

A sub-5% price effect alone does NOT kill if sale-speed/negotiation-confidence/WTP/contribution
are strong; a positive observational correlation does NOT authorize resale-lift claims.

## 11. Governance record (2026-07-11)

- **Ledger 2026-07-11T17:37:16Z — UNANIMOUS (claude .78 / codex .97 / gemini .92):** remove the
  annual full-Passport credit → member discount 20–25% + explicit bundle A/B; credits never
  accumulate; finite hosted term. Supersedes that clause of Q1 (2026-07-10).
- **Ledger 2026-07-11T17:39:29Z + correction 17:47:57Z — vehicle-limit mechanism = A (true
  majority 2/3: claude+gemini):** rules-validated batched counter invariant (`getAfter`), no
  Cloud Function, offline-preserving. The original row mis-resolved to C via a **consensus.py
  canonicalization defect** (bare "A" vs "A: full text" wouldn't group → highest-confidence
  fallback let the lone dissenter win, violating Law 1's no-veto rule). Defect fixed
  same-session in `scripts/brain/consensus.py` (enum-anchored grouping + 8 regression
  self-tests, all green; recorded positions replay to majority A). Ledger scan: the only
  outcome-flipped vote; 9 rows from 2026-07-10 merely understated consensus strength
  (recorded 2/3 where substance was 3/3) — decisions unaffected.
- **Naming (Q5) — WITHDRAWN by evidence supersession (ledger 17:47:57Z):** Roadfolio = hard
  collision ("RoadFolio: Mileage Tracker", live US App Store id6764113657 v1.1.0 2026-06-19 +
  Google Play com.itfbusiness.roadfolio since ≥2026-05-18 — both predate the 2026-07-10 CLEAR
  screen: a screening miss). Motorkeep = impaired (no store app anywhere; motorkeep.com still
  parked/buyable; but motorkeep.ru is a live exact-name, exact-category Russian web product) —
  usable only if operator + trademark counsel explicitly accept coexistence. Fresh candidate
  slate + professional clearance workflow required; operator holds the branding decision.
- **Kill-test methodology — Q4 amended by evidence (ledger 17:47:57Z):** analytical design
  stands; extraction method superseded. Both platforms' ToS verbatim-prohibit scraping
  ("automated or manual"); both carve out written permission (BaT via Hearst contact; C&B
  legal@carsandbids.com); C&B 403s bots site-wide. Protocol doc must embed: permission-first →
  licensed datasets (verify their chain) → small-N manual coding → consented sellers →
  controlled buyer experiments. Pre-registered, blinded, powered (Sol #4).
- **Sol co-review round 2 (2026-07-11, this doc):** NO-GO as written — 15 blockers, all
  dispositioned: 4 resolved by fresh Law-1 votes (below), the rest folded into §5 acceptance
  criteria, §7 gate rename, §8 terminology, §12 deployment matrix, and advisory wording fixes
  throughout. Sol's technical counterexample on the bare counter invariant (multi-create batch
  under `getAfter` semantics) was **correct** — codex's original dissent was substantively
  right even though the vote-tally correction stood; A′ (below) closes it.
- **Votes of 2026-07-11T18:03Z (all resolved A):**
  - 18:03:04Z UNANIMOUS — narrow sequence supersession: the enumerated Wave-1 hardening list
    proceeds in parallel with the kill-test protocol doc (which stays the top Week-2
    strategic deliverable); everything else waits.
  - 18:03:16Z majority — Pro AI = disclosed 5/day fair-use ceiling with `resetAt`; supersedes
    Q1 "unlimited OCR"; copy never says "unlimited".
  - 18:03:36Z UNANIMOUS — Pro = 5 vehicles (supersedes Q1 "unlimited vehicles"); Collector
    keeps 10–15 headroom.
  - 18:03:52Z UNANIMOUS — Mechanism A′: client-bound create invariant
    (`lastVehicleOp` one-to-one binding) + server-owned soft-delete purge + immutability
    protections + migration contract.
- Graveyard maintenance (Law 4): Centriq (homes, dead 2026-01) and Automatic Labs (consumer
  OBD, dead 2020) to be recorded as named corpses; this external review itself recorded as an
  assayed intake.

## 12. Thirty-day execution map (repo-anchored)

| Week | Deliverables |
|---|---|
| 1 | Wave-1 code (iOS-0, CF-1, iOS-1, iOS-2, iOS-6L, RULES-1 on branch — the voted enumerated list, nothing else) through CI + tri-review; this doc + ledger rows; naming/ToS evidence closed out |
| 2 | **Kill-test protocol doc (top strategic deliverable** — lawful design per the Q4 amendment, pre-registered, with the KPI-to-authoritative-source matrix, exact error units/thresholds/confidence rules, and p95 support guardrails per Sol #14/adv. 6**)**; concierge-pilot recruitment plan (10–15 of 30–50 owners); Wave-2 specs |
| 3–4 | Wave-2 (account deletion/data lifecycle, attachment ingestion); pricing-cell instrumentation dry-run; end-of-month one-page continue/change/stop memo per hypothesis |

Deploys remain operator-gated (Law 5); nothing here authorizes production mutation.

**Component deployment matrix (Sol #15 — "firebase deploy" alone ships nothing client-side):**

| Component | Ships via | Live-verification probe |
|---|---|---|
| Firestore rules (self-grant-Pro fix; later RULES-1) | `firebase deploy --only firestore:rules` | Emulator-proven suite + a denied client self-grant write against production |
| Cloud Functions (webhook/entitlement/quota; later CF-1) | `firebase deploy --only functions` | Probe the **running revision** (landmine #9), not the deploy log |
| RevenueCat identity binding, CSV fixes, all iOS work | **Signed iOS binary release** (TestFlight/App Store) — no backend deploy ships these | Live end-to-end probe: Firebase UID → RevenueCat logIn → sandbox purchase → webhook → `users/{uid}.subscription` → client entitlement read |
| Both halves together | Coordinated cutover (backend first, then binary) | The e2e probe above on the shipped binary |
