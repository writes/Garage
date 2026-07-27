# Branding, Design Optimization & Launch Plan

> **Date:** 2026-07-27 · **Status:** research complete, decisions pending operator
> **Method:** `/deep-research` workflow (112 agents, 110 completed, 4.65M tokens, 951 tool calls)
> plus live first-party screening run locally. The workflow's **synthesis stage failed** (exceeded
> the 16k output-token cap), so this document is a manual synthesis from the raw agent journal:
> 139 raw sourced claims, 74 adversarial verdicts (60 upheld / 14 refuted), 21 claims surviving
> 3-vote verification.

## Confidence key

| Tag | Meaning |
|---|---|
| **[V]** | Survived 3-vote adversarial verification against a primary source |
| **[S]** | Single-source, sourced but not independently verified |
| **[L]** | Measured locally by me this session against a live API |
| **[?]** | Vendor-published, methodology partly undisclosed — directional only |

---

## 0. Executive summary — the three things that matter

1. **Pricing is the biggest unexamined risk.** Incumbent vehicle-tracking apps anchor at roughly
   **$10/year or a $10 one-time payment** [S]. Pro is $34.99/yr — about **3.5×the category
   anchor**. This is not fatal (the product is materially more capable), but it means the app is
   not competing on price; it must win on the resale-dossier wedge, and the paywall has to *say*
   so explicitly.
2. **The naming deadlock has a clean exit.** Every real English word screened had App Store
   collisions; every coined word came back clean [L]. That is not coincidence — it is the
   Abercrombie spectrum showing up in the data. Coined names are both legally safest and
   collision-free.
3. **Day 0 is where the business is won.** 90% of trial starts and 44.5% of all purchases happen
   on day zero [S]; 84% of short-trial cancellations happen by day one [S]. Onboarding-to-first-
   value is the highest-leverage surface in the product, ahead of every lifecycle feature.

---

## 1. Naming

### 1.1 Why the previous candidates died — the verified legal frame

- Likelihood of confusion is **the most common ground for refusal** at the USPTO **[V]**.
- Marks need not be identical — similarity in **sound, appearance, or meaning**, or a similar
  overall commercial impression, suffices **[V]**. A near-miss on `UNDERHOOD` is not safe merely
  because it is spelled differently.
- Goods are related if they are *identical, similar or competitive, used together, used by the
  same purchasers, advertised together, or sold by the same dealer* **[V]** — so a vehicle-record
  iOS app can be held related to automotive software outside an exactly matching Nice class.
- The examiner searches **registered *and* pending** marks regardless of any private clearance
  search **[V]**. `DR. UNDERHOOD` (SN 99842025) being pending makes it a live obstacle, not a
  theoretical one.
- Marks sit on a continuum — *fanciful → arbitrary → suggestive → merely descriptive → generic* —
  and **only fanciful, arbitrary and suggestive marks are inherently distinctive** **[V]**.
- The suggestive/descriptive line turns on whether the term needs **imagination** versus
  immediately telling the consumer something about the goods **[V]**, judged against the specific
  goods recited, in context **[V]**.

**This is precisely the failure mode.** `Auto`+`Chronicle`, `Motor`+`keep`, `Under`+`hood` all
telegraph the product instantly — no imagination required. They are descriptive-leaning by
construction, in a crowded automotive class.

> **Process note [V]:** TESS was retired 2023-11-30. The correct search system is
> **tmsearch.uspto.gov**. Any checklist still referencing TESS is pointing at a dead system.
> USPTO also warns that a coordinated-class search **is not exhaustive** **[V]** — a clean result
> is screening evidence, never clearance.
> Drafting goods/services from the USPTO **Identification Manual** avoids a **$200 per-application
> custom-description fee** **[S]**.

### 1.2 Live screening results

Measured **[L]** by `scripts/release/name_screen.py` against the iTunes Search API (exact and
near-name iOS apps) and Verisign RDAP (.com status). **Validated first against three names whose
verdicts were already known** — it independently reproduced all three.

**Validation run:**

| Name | Found | Matches known verdict |
|---|---|---|
| Underhood | `Dr. Underhood` — Rob Holmes, *Utilities* | ✅ the known blocker |
| Roadfolio | `RoadFolio: Mileage Tracker` | ✅ the known collision |
| Motorkeep | **`Motorkeep` — EXACT, Alvaro Lopez, *Utilities*** | ✅ **worse than recorded** |

> ⚠️ **Correction to the naming record:** `Motorkeep` is on file as merely "impaired" by
> `motorkeep.ru`. In fact there is an **exact-name iOS app in the Utilities category** — same
> name, same platform, same category. That is close to the worst possible collision profile.

**Candidate screen (20 names):**

| Name | Class | App Store | .com | Verdict |
|---|---|---|---|---|
| **Provenar** | fanciful | 0 exact / 0 near | registered | ✅ clear |
| **Kestrix** | fanciful | 0 / 0 | registered | ✅ clear |
| **Velmont** | fanciful | 0 / 0 | registered | ✅ clear |
| **Torvel** | fanciful | 0 / 0 | registered | ✅ clear |
| **Marqora** | fanciful | 0 / 0 | registered | ✅ clear |
| Vantra | fanciful | 0 / 3 | registered | ⚠️ medium |
| Quillon | arbitrary | 0 / 5 | registered | ⚠️ medium |
| Camber | suggestive (auto) | 0 / 5 | registered | ⚠️ medium |
| Vellum | arbitrary | 0 / 7 | registered | ⚠️ medium |
| Keepsake | suggestive | 0 / 9 | registered | ⚠️ medium |
| Curator | suggestive | 0 / 9 | registered | ⚠️ medium |
| Cogent | arbitrary | 0 / 10 | registered | ⚠️ medium |
| Verity | arbitrary | 0 / 10 | registered | ⚠️ medium |
| Kestrel | arbitrary | 0 / 12 | registered | ⚠️ medium |
| Tessera | arbitrary | 0 / 13 | registered | ⚠️ medium |
| Almanac | suggestive | 0 / 14 | registered | ⚠️ medium |
| ~~Lodestar~~ | arbitrary | **1 EXACT (*Utilities*)** / 9 | registered | ❌ high |
| ~~Ironclad~~ | suggestive | **1 EXACT** / 11 | registered | ❌ high |
| ~~Bellwether~~ | arbitrary | **1 EXACT** / 3 | registered | ❌ high |
| ~~Steward~~ | suggestive | **1 EXACT** / 13 | registered | ❌ high |
| AutoChronicle | **descriptive-leaning** | 0 / 0 | registered | ⚠️ legally weak |

**Every .com is registered**, including all coined candidates — normal for short pronounceable
strings. Treat as a cost input, not a veto; `get<name>.com` / `.app` are standard fallbacks.

### 1.3 Recommendation

**Shortlist: Provenar, Velmont, Torvel.** All fanciful (strongest distinctiveness class **[V]**,
automatic protection), zero App Store collisions **[L]**, and none telegraph the product — which
is exactly what sank the prior three.

`Provenar` is the strongest brand: it evokes *provenance*, which is precisely the product's
wedge (a documented, trustworthy history that survives resale), while remaining a coined word
rather than a description of the goods.

**On `AutoChronicle`:** it screens clean on the App Store, but it is the **same construction that
failed twice**. `Auto` + `Chronicle` immediately tells a consumer what the product does — the
textbook descriptiveness trigger **[V]**. It is the weakest legal candidate on the list despite
the clean collision screen. I would not build an identity on it.

### 1.4 What this screening is NOT

It checks App Store names and .com status. It does **not** search USPTO (no key-free API exists —
`data.uspto.gov` serves only an SPA shell **[L]**), does not assess likelihood of confusion across
coordinated classes, and does not reach common-law rights from unregistered use.

**An attorney must still:** run a full federal + state + common-law clearance in Nice classes 9
and 42 plus coordinated classes; opine on descriptiveness under §2(e)(1); and check foreign
registrations if you distribute outside the US.

**Verification links** are emitted per name by the screener (tmsearch.uspto.gov + Trademarkia).

---

## 2. Visual identity

### 2.1 Verified Apple guidance

- Apple's HIG **advises against text in icons but explicitly endorses a mnemonic monogram** (the
  app's first letter) as a legitimate recognition device **[V]**.
- **Thin line weights and sharp corners lose detail and crispness at small sizes**; Apple
  instructs bolder weights and rounder corners **[V]**.
- Prescribes a **single-concept, minimal-shape** icon on a solid or gradient background; fine
  features become busy and illegible **[V]**.
- Advises **against realistic 3D and complex illustration**, favouring a flatter frontal view
  **[V]**.

> The current AutoChronicle icon already complies: single concept, gradient background, bold
> forms, flat. The 2.5px inner border I removed after render-testing is **exactly** the failure
> mode in the third bullet — that decision is now backed by Apple's own guidance, not just my
> 40px comparison.

### 2.2 The monogram problem

Apple endorses monograms for *legibility*. That is not the risk here. The risk is **coupling**:
an `AC` monogram hard-binds the icon to a name that has not cleared legal review, in a workstream
already blocked twice. If the name changes, the icon is scrap.

**Recommendation:** keep the crossed wrench-and-screwdriver emblem — it is yours, it is
name-agnostic, and it survived to 40px in testing. Defer the monogram until a name clears.

---

## 3. App Store Optimization

**Hard constraints [V]:**

| Field | Limit |
|---|---|
| App name | **2–30 characters** |
| Subtitle | **30 characters** |
| Keyword field | **100 characters**, comma-separated, **no spaces** |

- Apple instructs **not to repeat** words already in the name, subtitle, or category — the indexed
  vocabulary is the *union* of the three, so duplication wastes the budget **[V]**.
- Search ranking is driven by text relevance **and** behavioural signals — downloads, ratings,
  reviews **[V]**. Ratings appear in search results *and* influence ranking — a ranking input,
  not just a conversion input **[V]**.
- **Up to three screenshots/previews render inside the search results list itself** **[V]** — the
  first three assets must convert before anyone reaches the product page.

**Custom Product Pages (CPP) — the highest-leverage ASO lever available:**

- Apple states referring users to a CPP yields **+2.5 percentage points conversion on average — a
  156% lift over the 1.6% baseline** **[V]**.
- **CPPs can be assigned keywords** so the CPP, not the default page, is served in *organic*
  search **[V]**. This makes CPPs an organic lever, not just a paid-landing tool — widely
  misunderstood.
- Up to **70 additional product page versions** [S]; each varies screenshots, promo text, previews
  — title/subtitle/keywords stay fixed to the default listing [S].

**Product Page Optimization (PPO) — note the release-cycle trap:**

- Max **three treatments** per test; testable elements are **icon, screenshots, previews only** —
  *not* title, subtitle, keywords, or description **[V]**.
- **Testing an alternate icon requires that icon to already ship inside the published binary**
  **[V]**. Screenshot/preview tests can be submitted independently of a new version [S].
  → **Icon experimentation is gated on a release cycle; screenshot experimentation is not.**
  If you ever intend to A/B the icon, ship the variants in the binary *now*.

---

## 4. Conversion & retention

Source: RevenueCat *State of Subscription Apps 2026* (115,000+ apps, $16B revenue) unless noted.

### 4.1 Gating — the single most consequential product decision

| Model | D35 download→paid | RPI @ D60 |
|---|---|---|
| **Hard paywall** | **10.7%** median (top quartile >20%) | **$3.09** |
| **Freemium / soft** | 2.1% median | $0.38 |

≈**5× conversion, ≈8× revenue per install** [S]. **But** — and this qualifier survived
verification — **the retention advantage does not persist; after one year retention is nearly
identical** [S]. Hard gating buys *acquisition-stage monetization*, not durable retention.

There is a genuine trade: hard paywalls yield **21% higher LTV** while soft paywalls **convert
~50% better** [S]. Garage's current soft gating (vehicle count, AI/day, attachments, themes) sits
on the higher-conversion / lower-LTV side. That is a defensible choice for a trust product where
users must see their own data before paying — **but it should be a decision, not an accident.**

### 4.2 Trial length — a free ~5-point lever

| Trial length | Trial→paid median |
|---|---|
| ≤4 days | 25.5% |
| 5–9 days | **37.4%** ← current 7-day |
| 17–32 days | **42.5%** (top quartile 59.4%) |

Longer trials convert better [S] — but also cancel more (3-day 26% vs 30-day 51% [?], underlying
chart paywalled and unverifiable). Net of both, a **14-day trial is a cheap, reversible test.**

### 4.3 Day 0 dominates everything

- **90% of trial starts and 44.5% of all purchases occur on Day 0** [S].
- **55.4%** of 3-day trial cancellations occur on Day 0; **84%** by Day 1 [S].
- **>90% of users churn within the first 30 days** [S].
- Onboarding paywalls with a trial convert **1.35%** vs **0.89%** for post-onboarding placement —
  a **~52% relative lift** (Adapty 2026) [?].

→ First-session activation is the decisive lever. For this product, activation ≈ *first vehicle
added and first service record logged*, ideally with one AI-parsed receipt to demonstrate the
magic immediately.

### 4.4 Plan mix and churn

- **Annual RPI ≈2× monthly**: D14 $0.36 vs $0.18; D60 $0.46 vs $0.24 [S] → **annual-forward
  framing**.
- **Utilities first-renewal:** annual **35%**, monthly **57%**, weekly 49% [S].
- **Year-1 annual churn ≈72%**, worsened from 56% in 2025; ~35% of annual cancellations land in
  month 1 [S].
- **Retention converges after the first renewal** — by the third renewal all categories sit in a
  tight 74–91% band [S]. The **first renewal is the churn cliff.**
- **Cheaper plans retain better annually**: 36% (low-priced) vs 23% (high-priced) [S].

### 4.5 Pricing — the flagged risk

- Median North America: **$9.99/mo, $39.99/yr** [S]. Garage at $4.99/$34.99 is *below* the general
  market.
- **But the category anchor is far lower**: Simply Auto's top tier is **$9.99 per year**, its Gold
  tier a **$9.99 one-time** payment [S].
- Utilities discount harder than any category — median promo **−63%** vs ~−50% overall [S].
- Higher-priced subs convert trial→paid *better*, arguing against discounting to lift conversion
  [S] (qualitative only; no numeric spread published).

**The tension:** priced as a value play against the general subscription market, priced at a
premium against direct competitors. Both can be true — it depends whether buyers frame this as
"a fuel-log app" or "the thing that proves my car's history at resale." **That framing is a
positioning decision the paywall copy must win**, and it is testable.

---

## 5. Sequenced plan

### Now — before public launch (highest leverage, low cost)

1. **Resolve the name.** Take `Provenar` / `Velmont` / `Torvel` to an attorney for clearance.
   Everything downstream — icon, ASO, domain, legal entity — is blocked behind this.
2. **Instrument Day 0.** Funnel events for: install → onboarding step → first vehicle → first
   record → first AI parse → paywall view → trial start. Without this, every later decision is
   guesswork.
3. **Fix the ASO fields** (30/30/100 char budgets; no cross-field duplication).
4. **Ship the first three screenshots as conversion assets**, not feature tours — they render
   inside search results.
5. **Decide gating explicitly** — soft (current) vs hard, with the 5×/8× vs retention-parity
   evidence on the table.

### Next — at launch

6. **Annual-forward paywall** (≈2× RPI), monthly as the secondary option.
7. **Test a 14-day trial** against the current 7-day.
8. **Move the paywall into onboarding** and measure against the current placement.
9. **Custom Product Pages with assigned keywords** — the +2.5pp / 156% lever, and it works
   organically.
10. **Seed reviews deliberately** — they are a ranking input, not just social proof.

### Deliberately defer

- Icon A/B testing (gated on a release cycle; needs variants pre-shipped in the binary).
- Localization (highest experiment win-rate at 62.3% [?], but premature pre-PMF).
- Android / web.
- Any monogram-based identity, until the name clears.

### Metrics to instrument

| Metric | Benchmark |
|---|---|
| D35 download→paid | 2.1% soft / 10.7% hard |
| Trial→paid | 37.4% at 7-day |
| Utilities annual first-renewal | 35% |
| Utilities monthly first-renewal | 57% |
| D60 RPI | $0.38 soft / $3.09 hard |

---

## 6. Caveats

- **The workflow's synthesis stage failed**; this is my manual synthesis of the raw journal.
  21 of 139 claims carry 3-vote verification — the rest are sourced but unverified and tagged
  accordingly.
- **RevenueCat benchmarks are cross-category medians**, not automotive-specific. No
  vehicle-maintenance-category subscription benchmark was located.
- **Adapty figures are vendor-published** with partly undisclosed methodology — directional only.
- **One verification agent died** mid-response (`Product Page Optimization` assets claim); that
  claim is corroborated by a second independent source and marked [V] on that basis.
- **Nothing here is legal advice.** The naming screen is a collision filter, not clearance.
