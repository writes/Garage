# Garage Product-Expansion Research Program — DRAFT BODY

**Status:** Draft for governance review · Synthesizes 4 research sweeps (MARKET, PRICING, ADJACENCY, USABILITY) + 3 lenses (VISIONARY, GROWTH PM, SKEPTIC) · Subordinate to the standing unanimous VALIDATE-FIRST verdict (auction-comps kill-test gates heavy Phase-1 build-out)

---

## 1. Executive Summary

1. **The wedge is confirmed as whitespace, not wishful thinking.** No competitor treats resale documentation as the product; export is a buried footnote everywhere, and the category's #1 complaint — data loss/lost photos at export — occurs at exactly the moment a resale product must be bulletproof (MARKET whitespace #1–2).
2. **$1.99/mo is rejected.** Across all three modeled scenarios, $4.99 yields **2.1–2.5× the net LTV per payer** ($36.15 vs $16.26 SBP-net blended), churn elasticity gives back only 0–16%, and higher-priced utility apps convert *as well or better* top-of-funnel (PRICING §7). If you want "don't-think-about-cancelling," the honest instrument is a **free tier**, not a cheap one.
3. **Recommended pricing architecture:** Free Logbook (1 vehicle, CSV export free forever) → **Garage Pro $4.99/mo / $34.99/yr** (annual anchored) → **Resale Passport $34.99 one-time per vehicle**, Carfax-anchored ($24.99–$44.99 market proof). Enroll in Apple Small Business Program day one (+21.4% net revenue, zero tradeoff).
4. **The money is at the sale event, not the monthly habit.** The category has raced logging-utility pricing to $0–$10/yr; consumers demonstrably pay $25–45 one-time for a trust document at the transaction moment (Carfax/AutoCheck). Hybrid buyers are ~7% of payers but ~25% of revenue (PRICING §4).
5. **Deep beats broad, decisively.** CARFAX Car Care (free, 4.8★, 50M+ users, $1.14B parent) owns the casual mainstream; the defensible ground is the serious owner with 2–4 vehicles in the gap between toy loggers and AUTOsist's 5-vehicle fleet floor (MARKET whitespace #4; SKEPTIC §1).
6. **"More than a car app" — yes, but only in one direction and only on triggers.** Vehicles-with-secondary-markets (powersports/marine/RV) is a schema extension with HIGH wedge-fit; homes (Centriq: dead Jan 2026) and OBD hardware (Automatic Labs: dead 2020) are graveyard-confirmed dead ground (ADJACENCY ranked table).
7. **The two highest-leverage moves aren't expansion at all:** BaT/Cars & Bids/forum-shaped Passport exports — which simultaneously extend the wedge AND generate the auction-comps validation data the governance gate requires (ADJACENCY #3–4).
8. **Growth strategy: profitable-by-default, growth via zero-CAC loops.** LTVs of $16–36 don't clear paid-UA payback; the Passport itself is the growth mechanic (every sale hands one perfect prospect a proof artifact). No paid installs in year one (GROWTH PM #28–29).
9. **The existential risk is the self-reported trust gap:** buyers may discount owner-typed records to near zero — CARFAX's willingness-to-pay rides on third-party data, the one property Garage can't have. The comps kill-test plus a passport A/B on live listings tests this for ~$0 in days (SKEPTIC §4).
10. **Everything above is contingent:** no Phase-2 AI depth, no powersports build, no Passport marketing spend until the kill-test passes its pre-registered death condition (delta <~5% or vanishing under confounds → downgrade the wedge and re-price off "resale lift").

---

## 2. Market Landscape + Whitespace

| Tier | Players | Price band | Weakness Garage exploits |
|---|---|---|---|
| Toy loggers (ad-supported) | Drivvo, Fuelly, Simply Auto | $0–$20/yr | Data loss endemic; export loses photos (Fuelly); autoplay ads on *paying* users (Drivvo); dark-pattern trust corrosion |
| Enterprise-in-consumer-skin | AUTOsist | $7–55/vehicle/mo, **5-vehicle min** | 2–4 car serious owners fall in the gap entirely |
| Free OEM/insurer utilities | CARFAX Car Care, Jerry, CarAdvise | Free (referral/lead monetized) | Shop-affiliate favoritism; DIY/independent work second-class; buyer-side not owner-side |
| VIN/history lookups | Bumper ($27.99/**mo**), carVertical, Carfax reports ($44.99 one-time) | $25–45/report | Proves one-time transaction-moment WTP; but third-party data only, owner can't build the record |
| Diagnostics hardware | FIXD, Carly | Dongle + sub | "Subscription trap" reputation; hardware COGS; graveyard (Automatic Labs) |
| Indie/no-dark-pattern niche | Motorist ($3.49/mo), Road Trip (one-time), LubeLogger (self-hosted, free) | $0–$42/yr | Proof of unmet trust demand — a segment has *exited the commercial market* rather than tolerate lock-in |

**Whitespace synthesis (MARKET):** (1) resale/export as the product, not a footnote; (2) durable, never-lose-data record-keeping as an existential guarantee; (3) an explicit no-dark-patterns trust pledge as genuine differentiation, not table stakes; (4) the 2–4 vehicle serious-owner tier; (5) enthusiast depth (oil-analysis trends, mods) — MotorMia is the only attacker and it's rough (3.6★); (6) owner-owned portable passport vs. the coming OEM dealer-controlled vault wave (Kia Digital Passport, HeyAuto) — a position no OEM can occupy by definition.

Market sizing: treat the "$2.5B maintenance-app market" figures as report-mill noise; the load-bearing anchors are the $828B underlying repair/maintenance service market and CARFAX's **$1.142B FY2025 revenue** as existence proof that vehicle-history trust is a real business (MARKET).

---

## 3. Pricing & Monetization

### The $1.99 question: **No.**

Worked LTV (PRICING §7, perpetuity method, RevenueCat Utilities benchmarks):

| Scenario | $1.99 net LTV (SBP) | $4.99 net LTV (SBP) | Ratio |
|---|---|---|---|
| A: price buys retention (11.7% vs 14.0% churn) | $14.46 | $30.29 | 2.1× |
| B: category-driven churn (12.5% flat) | $13.53 | $33.93 | 2.5× |
| C: blended 65/35 monthly/annual mix | **$16.26** | **$36.15** | 2.2× |

Three independent reasons $1.99 fails beyond the math: (a) the "set-and-forget" psychology is unsupported — the user who doesn't think about cancelling also doesn't think about the app, and Utilities churn ~12%/mo regardless within this band (SKEPTIC); (b) it's a dead zone — too expensive to beat free/one-time incumbents (Simply Auto $9.99/**yr**), too cheap to fund the product, forfeiting ~55% of per-payer revenue without expanding the funnel the way free does; (c) it *positions* Garage in the toy-logger tier whose brand associations (data loss, ads) are the exact opposite of a trust product.

The deeper structural point: **subscribers statistically churn ~8 months in; the resale event happens once per 4–8 year ownership cycle.** The subscription cannot be the revenue engine. The event must be (SKEPTIC §4).

### Recommended architecture

- **Free — "The Logbook":** 1 vehicle, unlimited manual entries, deadline reminders, **raw CSV export free forever**, 10 lifetime OCR scans. This is the top-of-funnel and the "never think about cancelling" layer, honestly implemented.
- **Garage Pro — $4.99/mo or $34.99/yr** (annual highlighted, ~40% discount): unlimited vehicles, unlimited OCR + email-forward ingestion, photo-batch import, oil-analysis trends, completeness scoring, widgets. 7-day trial on annual; instrument trial length (7 vs 14) — trial-structure experiments are the single largest lever available (~80% uplift potential, RevenueCat) and the long-vs-short data is genuinely contested.
- **Resale Passport — $34.99 one-time, per vehicle:** verified buyer-facing PDF + hosted shareable link. Anchored between AutoCheck ($24.99) and Carfax ($44.99) — direct market proof of transaction-moment WTP. Free watermarked preview always visible (it *is* the upsell). **Pro-annual includes one Passport credit/year** — makes annual a bundle, not a discount. Merely offering a one-time option alongside subs lifts total conversion 15–25% (RevenueCat A/Bs).
- **Trust Pledge as a pricing feature:** "No ads ever. Raw data exports free forever. No price hikes on existing subscribers." Directly de-risks commitment in a category defined by Drivvo ad-hijacks, Fuelly export losses, and Bumper's $27.99/mo trap (MARKET; GROWTH PM #14).
- **Apple Small Business Program, day one.** 15% vs 30% = +21.4% net proceeds. Checklist item, not a debate (PRICING §5).

---

## 4. Deep vs. Broad: **Deep.**

Features-first for the serious owner (2–4 vehicles, enthusiast-adjacent, documentation-minded). Reasoning:

1. **Broad is occupied by free.** CARFAX Car Care (50M+ users, subsidized by a $1.14B B2B business) and Jerry ($75M Series C) own the casual mainstream. You cannot out-free them, and every mainstream feature you build converges on their roadmap (SKEPTIC).
2. **Deep is empty.** The serious-owner tier between toy and enterprise has *nothing*: MotorMia is early/rough, Motorist is a polished solo logger with no ecosystem, LubeLogger users left the market entirely. The unserved persona (multi-car, oil-analysis, DIY-respecting) is precisely who Garage's Claude-parsed oil-analysis pipeline already serves (MARKET whitespace #4, #7).
3. **Depth users are the word-of-mouth engine.** BITOG/Rennlist/BaT-comments enthusiasts are the loudest channel in the category and already treat documentation as price-determining (ADJACENCY #3). Win them and the mainstream positioning ("the app serious people use") follows (VISIONARY #21).
4. **One caution, priced in:** the deepest enthusiasts overlap with the most payment-averse segment (self-hosters). Depth earns love and distribution; the **Passport at the transaction moment earns the revenue**. Depth features are the acquisition channel, not the monetization (SKEPTIC §3).

---

## 5. More Than Cars: **Yes — but one axis only, on triggers, not on ambition.**

The generalization that survives the evidence is *"assets that are owner-maintained, provenance-priced, and have an active secondary market"* (VISIONARY #20's three tests) — **not** "all owned things." Homes fail the tests (appraisal-driven, 13-year hold, Centriq's corpse); consumer OBD hardware breaks asset-light economics (Automatic Labs' corpse).

**Staged expansion map:**

| Stage | Scope | Trigger to start | Trigger to skip/kill |
|---|---|---|---|
| **0 (now)** | Cars only. Marketplace-native exports (BaT/C&B/eBay-shaped Passport packages) + public passport link | Immediately — this is also the kill-test data source | Kill-test death condition fires → re-scope wedge |
| **1** | Powersports/motorcycles → marine/RV. Schema extension (vehicle→event→attachment→export is asset-agnostic); new service-schedule content, parsing tuned per drivetrain | Kill-test passed AND RRV curve healthy AND core car flywheel showing organic Passport pulls. BaT already auctions motorcycles — same passport, day one | Weak wedge-transfer evidence in first vertical → stop at cars |
| **2** | Collection/estate tier (3–15 vehicles): fleet dashboard, agreed-value insurance exports, succession packets — the AUTOsist-gap whale tier | Demonstrated multi-vehicle Pro cohort with elevated retention/WTP | — |
| **3** | B2B chain-of-custody (white-label shop exportable record only; shop attestation network) + owner-consented Ownership API | Passport is a recognized noun in listings; attested-record demand visible from owners | Never head-on vs CARFAX/Cox/Tekmetric |
| **Horizon** | "The Vault" (equipment, aircraft, watches) — only where all three tests pass | Stage-1 verticals profitable; brand promise proven portable | Any vertical failing the three tests |
| **Never** | Home/asset maintenance (Centriq), OBD dongles (Automatic Labs), own marketplace (BaT owns liquidity), community/forum (integrate, don't compete) | — | Log to graveyard per Law 4 |

The 3-year framing (VISIONARY): if the premise validates, the endgame is the **owner-side trust layer** — CARFAX inverted — with the VIN-anchored, ownership-transferable record as the compounding asset. That vision is directionally right and should shape architecture (records attach to the vehicle, tamper-evident timestamps from v1) without licensing any premature build-out.

---

## 6. Usability Optimization Backlog (ranked, effort S/M/L)

Optimizing for **RRV (Resale-Ready Vehicles)** — vehicles crossing the export-worthy completeness threshold — not DAU (GROWTH PM's one-metric).

| # | Item | Effort | Rationale |
|---|---|---|---|
| 1 | First-run **photo-batch OCR bulk import** ("shoebox session") — in onboarding, not Settings | M | Best-verified activation lever in the corpus (Streak/OneSchema: +50% import completion, +110% first-week imports); the wedge is void with half-empty history (USABILITY §3) |
| 2 | **Email-forward ingestion** (`logs@garage.app`) | M | TripIt-validated; logs without opening the app — decisive for a low-frequency product; reuses the Claude parser |
| 3 | **Share-sheet extension** (Photos receipt / Mail PDF → Garage) | S | Decouples capture from logging; cheapest recurring-friction cut |
| 4 | **Receipt OCR at manual entry** (already roadmapped) | S–M | Per-event friction floor: photograph vs 8 fields |
| 5 | **Record-completeness score + gap checklist** ("87% resale-ready — missing: 2023 brake job") | S | Honest loss-aversion (asset status, not daily streaks); doubles as RRV instrument and Passport upsell surface |
| 6 | **Deadline reminders on real dates**, never batched | M | The category's proven retention loop (transactional pushes ~69% open); Simply Auto's under-notify complaints set the bar to beat |
| 7 | **Competitor CSV importers** (Fuelly/Drivvo/Simply Auto, named one-tap mappings) | S | Catches the category's data-loss refugees with history intact |
| 8 | **VIN scan at add-vehicle** + factory schedule + NHTSA recalls | S | One-time friction cut; instant pre-populated value; don't over-invest |
| 9 | **Status widget** (next due date/mileage) | S | Display not input; reinforces #6 at near-zero cost |
| 10 | **Annual "Garage Recap"** (shareable, resale-readiness framed) | M | Structurally better annual-cadence fit than for daily apps, but explicitly unproven — ship with a kill metric (<3% share rate after 2 cycles = cut) |
| 11 | App Intents/Siri | S | Cheap opportunistic sugar; circulating retention stats for it are fabricated (USABILITY ⚠️) |
| — | **Skip v1:** Live Activities (cited "2.7×" stat failed direct source verification), Watch logging, OBD hardware, daily streaks | — | Graveyard/fabricated-evidence backed (USABILITY §4; SKEPTIC §5) |

---

## 7. Feature Expansion Backlog (ranked by wedge-fit)

1. **Marketplace-native Passport exports** (BaT/Cars & Bids/eBay-shaped dossiers) — very high fit, low effort, and *is* the kill-test data source (ADJACENCY #4; VISIONARY #7).
2. **Hosted, shareable Passport page** with QR + "records maintained with Garage" footer — the growth loop itself; the strategic goal is buyers asking "does it have a Garage Passport?" (VISIONARY #6; GROWTH PM #28).
3. **Tamper-evident chain-of-custody** (hash-chained entries, receipt-image hashes from v1) — directly attacks the self-reported-trust gap, the product's existential risk; trust accrued over time is the one asset no entrant can backfill (VISIONARY #2; SKEPTIC §4).
4. **Oil-analysis/fluid-trend intelligence** (longitudinal wear-metal trends, fleet-percentile alerts) — the enthusiast lighthouse; serves the unserved persona; Phase-2 gated on kill-test (VISIONARY #11).
5. **Shop attestation via free web link** (no app, no affiliate extortion) — upgrades entries from self-reported to verified, inverting CARFAX's most-hated behavior; start as a lightweight countersign, not a network build (VISIONARY #3).
6. **AI listing generator + sale concierge** at the transaction moment — monetizes the flywheel's exit as a one-time purchase stacked on the Passport (VISIONARY #13).
7. **Predictive cost-to-own forward curve** — gives every log entry a quantified payoff; Phase 2, needs aggregate data (VISIONARY #12).
8. **Buyer-side pre-purchase mode** (request a passport / PPI template) — second wedge, converts buyers into day-zero logging owners; Stage 1+ (VISIONARY #9).
9. **Powersports/marine/RV schema extension** — Stage 1 per §5 triggers (ADJACENCY #1).
10. **Public garage pages / marque registries** — status display, explicitly not a forum; defer until organic demand appears (VISIONARY #15).
11. **Ownership API / aggregate-outcomes dataset** — Phase 3; architecture should not preclude it (opt-in flags, clean schema) but zero build now (VISIONARY #4–5).

---

## 8. Growth Strategy: **Profits primary; growth via zero-CAC loops.**

Reasoning: growth-first is only rational when a network effect compounds users into value, and Phase 1 has none — no UGC, no liquidity, no cross-user value; users are support cost until the flywheel is proven (SKEPTIC §1). Meanwhile per-payer LTVs ($16–36) don't clear paid-UA payback in this category, and the hypothesized word-of-mouth loop rides on the unvalidated resale-lift premise.

Concretely: run **profitable-by-default** (SBP + $4.99/$34.99 + Passport sustains an indie at ~thousands of payers) and let growth come free from: refugee SEO + competitor importers (the category actively bleeds data-loss refugees on BITOG); honest founder participation in BITOG/Rennlist/marque subs; the published kill-test study as the category's citable stat with Garage's name on it; and the Passport-in-every-listing loop, which exposes exactly one perfect prospect per sale — a person holding proof of what complete records are worth, on the day they buy a used car (GROWTH PM #22–28). No paid installs year one; revisit only if the Passport→buyer→install loop shows a measurable k-factor worth amplifying.

---

## 9. Risks & Kill-Tests

**R1 — Existential: the self-reported trust gap.** All resale-lift evidence (Motorway "up to 20%," HPI "−40% if missing," the BaT premium) concerns documented history *generally*, much of it third-party-verified; the CarGurus 11% figure failed primary-source verification. The unproven leap is that a record the seller typed in transfers that trust; dealers actively distrust owner-self-reported history (ADJACENCY #5; SKEPTIC §4). **Kill-test (this IS the standing VALIDATE-FIRST gate, sharpened):**
   - Scrape 200–400 closed BaT/C&B auctions in tight model/year/mileage bands; code documentation depth; regress hammer price on documentation tier. **Pre-registered death condition: delta <~5% or vanishing under confounds → downgrade the wedge, re-price off "resale lift" as headline claim.** Days of work, ~$0.
   - Complement: 10 mock Passports A/B'd on live private listings + direct buyer/bidder interviews — isolates the *self-reported* component the comps study can't.
   - Per the standing verdict: no Phase-2 AI depth, no powersports build, no Passport marketing until this passes.

**R2 — Subscription/event cadence mismatch.** Subscribers churn ~8 months in; the sale event is 4–8 years out. Mitigation is architectural (free tier keeps the record alive post-churn; Passport monetizes the event regardless of subscription status) — already embedded in §3.

**R3 — CARFAX moves owner-side.** They have distribution (50M+) and data, but structural conflicts (shop-referral monetization, buyer-side business model) make honest owner-fiduciary positioning hard for them (VISIONARY #10). Mitigation: trust pledge + chain-of-custody as the un-copyable asset.

**R4 — Enthusiast payment aversion.** The persona depth serves overlaps the LubeLogger crowd that pays $0 on principle. Mitigation: depth = distribution, Passport = revenue; never gate the raw export.

**R5 — Fabricated evidence entering decisions.** Multiple circulating stats (Siri retention, Live Activities "2.7×") failed direct source verification (USABILITY). Standing rule: no unverified figure drives a build priority; flag per the evidence-calibration standard.

**R6 — Expansion graveyard re-entry.** Centriq (homes) and Automatic Labs (consumer OBD) should be logged to `docs/research-assay/audit/` as named corpses per Law 4 so these ideas arrive pre-tested if they resurface.

---

## 10. Open Questions for Governance Votes

**Q1 — Pricing model** (this document recommends A):
- **A:** Free Logbook + Pro $4.99/mo / $34.99/yr + Resale Passport $34.99 one-time (annual includes 1 Passport credit); Trust Pledge; SBP day one.
- **B:** Operator's original instinct: $1.99/mo single tier, Passport included, maximize subscriber count and set-and-forget retention.
- **C:** No subscription at all: free app + event-priced Passport ($34.99) + one-time Pro unlock ($29.99 lifetime, Simply Auto/Road Trip model).

**Q2 — Deep vs. broad** (recommends A):
- **A:** Depth-first for the serious 2–4 vehicle owner; enthusiast features (oil-analysis trends, completeness grades) as the acquisition channel; mainstream growth only via the Passport loop.
- **B:** Broad-first: simplest-possible logger + reminders for the mass market, compete adjacent to CARFAX Car Care on polish and trust.
- **C:** Dual-track: broad free tier engineered for mass appeal + deep paid tier, built simultaneously.

**Q3 — Expansion scope** (recommends A):
- **A:** Cars only until the kill-test passes; then powersports/marine/RV as Stage 1 per the trigger map (§5); homes/OBD/marketplace/community permanently graveyarded.
- **B:** Begin powersports schema-extension groundwork now in parallel with the kill-test (BaT already auctions motorcycles; same passport).
- **C:** Commit now to the multi-asset "Vault" vision as the north star and architect v1 explicitly for asset-agnostic records, accepting slower car-wedge iteration.

**Q4 — Kill-test scope** (recommends A):
- **A:** Comps regression + live-listing Passport A/B + buyer interviews (tests the self-reported gap specifically), pre-registered death condition, published as content.
- **B:** Comps regression only (faster, cheaper, but can't isolate self-reported trust).
- **C:** Skip to build; treat the Carfax one-time-report WTP precedent as sufficient validation.
---

## 11. Naming study (three-model panel + two-round collision screen)

Three panels (Fable 5, GPT-5.6 Sol, Gemini 3.1 Pro High) generated 36 candidates; notable
convergence: **Provenance appeared independently on all three decks** (validating the concept
even though the name itself screens CROWDED), Motorfolio and CarLedger on two each.

**Round-1 screen (the obvious/evocative tier):** 6 of 8 CROWDED or BLOCKED —
Glovebox (5+ live same-category iOS apps + funded insurtech), ServiceBook (live identical-
category app), Pedigree (Mars global mark), ClearTitle (real-estate collision + semantically
misleading), Provenance (live iOS app + provenance.io blockchain + provenance.org), Stamped
(stamped.io SaaS), CarLedger (carledger.io in the identical niche). Sole survivor: Motorfolio.

**Round-2 screen (coined tier): 5 of 8 CLEAR** — Odograph, Proofmile, Motorkeep, Roadfolio,
Ownmark. (Veyra: 4+ same-name apps; Valorem: same-name valuation app + Valorem Reply;
Logsmith: fragmented small-software use.)

**Final slate for decision (all screened CLEAR; USPTO TESS class 9/42 knockout search
recommended before commitment):**

| Name | Brand argument | Caveat |
|---|---|---|
| **Motorkeep** | "Keeping" is the wedge verb — the keeper's record; .com buyable on Afternic | MotorK (EU dealer SaaS) is a distant phonetic neighbor |
| **Roadfolio** | Portfolio-of-the-road; premium, scales to powersports/marine naturally | "-folio" family adjacency to AppFolio (low risk) |
| **Motorfolio** | Same family, more literal | Small Greek B2B app uses it; clean .com gone |
| **Proofmile** | "Proof" is the product — proof of care per mile | Leans mileage-tracker semantically |
| **Ownmark** | The mark of ownership; fully asset-agnostic for the expansion map | Least car-flavored today |
| **Odograph** | The recording instrument itself; dictionary-perfect, near-zero collision | Obscure word; generic-mark weakness |

Collective vote (Law 1) on the recommendation pending; **final selection is an operator
branding decision** — the collective supplies the screened slate and its verdict.

---

## 12. Governance verdicts (live Law-1 tri-votes, 2026-07-10 — ledger rows appended)

| Fork | Verdict | Rule |
|---|---|---|
| Q1 Pricing | **A — Free Logbook + Garage Pro $4.99/mo·$34.99/yr (annual includes 1 Passport credit) + Resale Passport $34.99 one-time + Trust Pledge + Apple SBP day one.** The operator's $1.99 instinct is honored through the FREE tier — the layer users genuinely never think about cancelling — while payers price at the value tier the math supports | majority |
| Q2 Deep vs broad | **A — Depth-first for the serious 2–4-vehicle owner**; enthusiast features are the acquisition channel; mainstream reach rides the Passport loop | majority |
| Q3 Expansion scope | **A — Cars only until the kill-test passes; powersports/marine/RV as Stage 1 on triggers; homes/OBD/marketplace graveyarded** | **unanimous** |
| Q4 Kill-test scope | **A — comps regression + live-listing Passport A/B + buyer interviews**, pre-registered death condition, published as content | majority |
| Q5 Name (recommendation) | **A — Motorkeep** (screened CLEAR; .com buyable). Final selection is an operator branding decision; Roadfolio is the collective's runner-up | majority |

Growth posture (§8 of this doc, affirmed by Q1–Q3): **profitable-by-default; growth via
zero-CAC Passport loops; no paid acquisition in year one.** Every verdict remains subordinate
to the standing VALIDATE-FIRST gate — the kill-test is the next strategic action.
