# Design Personalization + Monetization + UI Research — Garage

> 2026-07-21 · web-grounded collective research (17 agents: 6 research lanes → 5 design
> directions → adversarial judging → synthesis). **Advisory design input only.** Per Law 1 +
> Law 4 nothing here is a build authorization — the core architecture decisions need a
> tri-agent vote and a research-assay graveyard intake first (see §7).

## 1. The honest verdict (read this first)

The operator's instinct — make the app uniquely *theirs* per user and per car — is **strongly
supported**. The instinct to monetize that via a **cosmetic add-on catalog** (sound bites, color
packs, per-model packages) is **mostly not supported by the evidence**, for one structural
reason:

> Every strong cosmetic-monetization precedent — Fortnite (~$6B/yr skins), Duolingo avatars,
> Discord, Strava icons — depends on the item being **SEEN by other people**. A private
> maintenance log has **no social-visibility surface** (no feed, lobby, wall). Cosmetics that
> nobody sees don't sell.

So the winning shape is:

- **Identity / theming = a RETENTION + DIFFERENTIATION lever bundled INTO Pro** (the Strava
  model — zero cannibalization), *not* a second revenue pillar.
- **Real willingness-to-pay exists only on stranger-facing surfaces with dollar stakes:** the
  **resale Certificate/Dossier** (documented history commands a real resale premium) and
  **Garage Wrapped** (a Spotify-Wrapped-style conversion flywheel that rides the data the app
  already owns).
- **Two of the operator's specific ideas should be dropped:** the **engine-sound catalog** is a
  live IP battleground (Harley sound-mark fight, copyrighted recordings, Midler/Waits passing-off)
  and **model-name "packages"** ("Porsche 911 Pack") are direct trademark infringement + an Apple
  Guideline 5.2 takedown vector.

## 2. Evidence base (web-grounded, cited)

- **Personalization drives retention/ARPU** (directional, aggregator-sourced): ~10–15% revenue
  lift (McKinsey-cited), 87% will pay more for personalization; but the honest caveat from the UX
  literature is *"personalize the workflow, not just the wallpaper"* for utility apps.
- **Strava** (closest comp): sells custom app icons *as a Pro perk*, segments users into named
  identity personas, ties personalized recaps to retention — **theming as a subscription perk,
  not a standalone SKU.**
- **Spotify Wrapped:** 200M+ engagements in 24h, zero paid media — works because *"it says
  something about them, not the brand."* Garage already **owns** the underlying data.
- **Fortnite / gaming cosmetics:** proof cosmetics-only economies are huge — *but only with social
  visibility* (self-expression + in-group signaling). Clemson research on skins confirms the
  driver is status/allegiance, not utility.
- **Gran Turismo / Forza livery editors:** the auto-specific proof that *car-identity*
  customization (paint/livery/badge) sustains engagement — but inside a social/sharing loop.
- **IKEA effect / psychological ownership** (Norton–Mochon–Ariely): attachment comes from what the
  user **built** (their history, photos, configuration), not a purchased skin → the churn moat is
  *the user's own data + configuration*, and it's free.
- **NHTSA vPIC:** public-domain VIN decode (era, body, powertrain, displacement, region) — the
  lawful, license-free, trademark-free backbone for per-model personalization. (Deeper factory
  build data → licensed feed like ChromeData/DataOne, never scraping OEM configurators.)
- **Regulatory guardrails:** Robinhood confetti/streaks → SEC + $7.5M Massachusetts settlement,
  features stripped → **never gamify near a purchase decision.**

Full source list is in the workflow transcript
(`subagents/workflows/wf_caf21035-938/journal.jsonl`).

## 3. Design directions (adversarially judged, 1–10)

| Direction | Unique | Usability | Perf | Monetiz. | Legal-safe | Effort | Verdict |
|---|---|---|---|---|---|---|---|
| **Living Garage** — app becomes your car | 8 | 7 | 6 | 4 | 6 | 3 | maybe → **build (in Pro)** |
| **Concours** — ownership dossier | 8 | 7 | 7 | 4 | 7 | 3 | maybe → **build (Certificate)** |
| **PATINA** — living data-portrait | 8 | 7 | 6 | 4 | 6 | 3 | maybe (folds into Living Garage) |
| **Cold Start** — sensory/engine-sound | 8 | 6 | 7 | 3 | 6 | 3 | **DROP (IP)** |
| **Chapters** — model clubs / marketplace | 6 | 6 | 6 | 4 | 4 | 2 | **DROP/defer (2nd product)** |

## 4. The moves to build (ranked)

1. **Living Garage theme engine — bundled INTO Pro.** Derive a trademark-free "Livery" (palette,
   type voice, ambient-motion character, abstract archetype glyph) *deterministically* from free
   NHTSA vPIC facts, computed **once** at VIN decode into a cached static token set, personalized
   by the user's own hero photos + one accent choice. Per-model **and** per-user identity, zero
   new StoreKit surface. This is the differentiation moat a spreadsheet competitor can't copy.
2. **Garage Wrapped.** Annual/ownership-period recap (miles, service $, cost-per-mile, track PBs,
   oil-analysis trend) as an identity-affirming, shareable story. Full in Pro; **free 3-card
   teaser** for non-Pro = the conversion flywheel. Rides data the app already owns.
3. **Provenance Score + Certificate of Provenance ($6.99 one-time IAP).** An honest, Oura-style
   completeness metric (rolling window; grace/freeze for stored cars) crowned by a VIN-seeded
   deterministic seal, exported as a prestige resale-ready PDF. **The one SKU with real willingness
   to pay** — stranger-facing, tied to a resale transaction, sits on the PDF export Garage already
   sells. Copy says **"owner-maintained record," never "verified/certified."**
4. **Service-density calendar + milestone medallions.** GitHub-heatmap-style, passive,
   non-punitive, silent-by-default, global off-switch. Ethical gamification for a power-user
   audience (no streak-shaming; maintenance is months/miles, not daily).
5. **Own-crest / accent personalization (free, in Pro).** User configures a generative crest from
   *neutral* primitives + their own paint sample from a photo, seeded by VIN hash. The IKEA-effect
   churn-resistance lever; every install becomes one-of-one.

## 5. Monetization model

| Offering | Model | Price |
|---|---|---|
| Living Garage theme engine + own-crest + density calendar + medallions + base icon/widget set + base Wrapped | **bundled in existing Pro** (Strava perk model) | $0 — retention/differentiation, not a revenue line |
| Garage Wrapped free 3-card teaser | free conversion driver | $0 |
| **Certificate of Provenance** (prestige resale PDF, VIN-seeded seal) | **one-time non-consumable IAP** | **$6.99** — the one real SKU; A/B before building anything else |
| Concours Editions (generic era/segment aesthetic packs, permanent, deterministic) | one-time IAP | $3.99 / $12.99 5-pack — **DEFER** until Certificate+Wrapped prove lift |
| Finish / extra icon packs (generic, strictly outside Pro) | one-time IAP | $2.99–3.99 — **DEFER**; launch 6–10 at once, never a trickle |
| Collector add-on (unlimited vehicles + studio) | add-on sub **above** Pro, **anchored to the vehicle-count limit** (not cosmetic-only) | $14.99–29.99/yr — **DEFER**, gate on retention proof |
| Physical foil-stamped Dossier booklet | one-time physical good | $39 — **manual concierge pilot only**, no built pipeline |
| Engine-sound paid catalog | — | **DROP** (IP). Keep only a free generic earcon set + optional user-recorded private clips w/ rights-warranty. |

Rule (Discord model): every paid item is **strictly outside** what Pro grants, permanently owned,
deterministic — **no loot boxes, no expiring currency** (also an Apple-policy red line). Bundle
the first tranche into Pro so cosmetics never depress Pro's perceived value.

## 6. Hard risks + mitigations

- **Trademark / trade-dress on crests/glyphs** (Ferrari trade dress; Jeep 7-slot mark) → ship
  **only abstract, non-representational** generative primitives from a bounded, reviewable token
  registry; per-asset human IP review, forever; no motif may mimic a proprietary silhouette/grille.
- **Model-name-as-product = infringement** → make/model/trim appears **only as factual descriptive
  text** (nominative fair use — Carfax/KBB footing). Never a brand-named SKU, no OEM
  logos/wordmarks/color names. Ship generic archetypes ("Air-Cooled Era", "Modern Track Coupe").
- **Engine/exhaust sound = triple IP exposure** → drop the catalog; free generic earcons only;
  user-recorded private clips behind a ToS rights-warranty, never pre-populated or exported.
- **VIN is quasi-PII** → vPIC decode backbone; hash VIN for the art seed; keep VIN/plate/nickname/
  resale figures **off** any lock-screen / Live Activity / shared-poster surface (deep-link only).
- **"Certificate/verified" copy = fraud/FTC exposure** → "owner-maintained record" only.
- **Cosmetic cannibalization of Pro** → Discord additive-only rule (above).
- **Gamification near a purchase = regulatory** (Robinhood) → scope strictly to care/maintenance
  behaviors; never a Pro-upgrade/add-vehicle/AI-upsell nudge; score must be hard to game.
- **Perf/accessibility**: `MeshGradient` is **iOS 18+** but the app targets **iOS 17+** → explicit
  static/frosted fallback; animate only foreground; device-tier gate (full motion iPhone 15+/A15+);
  compute themes once at decode; **battery MEASURED on the oldest supported device, never
  simulator**. Contrast-clamp every derived palette to **WCAG AA before render**; Reduce-Motion +
  a global **Plain Mode**; never color-only encoding; VoiceOver narrates art *as data*. Make this a
  `verify-ios`/CI checklist line, not just design guidance.

## 7. Roadmap + governance gates

- **PHASE 0 — GATE (before any code):** Law-4 research-assay graveyard intake ("car
  community/identity/data-portrait app") + Law-1 tri-agent vote on adopting generative per-vehicle
  theming as core UX architecture. *This doc is advisory input to that vote, not a build order.*
- **PHASE 1 — quick unique wins (in Pro, no revenue plumbing):** Living Garage theme engine + own
  crest + density calendar + medallions + base icon/widget set.
- **PHASE 2 — conversion + the one real revenue line:** Garage Wrapped (full/teaser) + Provenance
  Score + **$6.99 Certificate**. **A/B the lift — this is the go/no-go for Phase 3.**
- **PHASE 3 — prove-then-expand (conditional on Phase 2 A/B):** Concours catalog + finish/icon
  packs + collector add-on anchored to the vehicle-count limit; Dossier booklet as a manual pilot.
- **PHASE 4 — deferred:** animated Wrapped video, seasonal drops, signature studio.
- **NEVER build:** engine-sound paid catalog; the Chapters social/marketplace/UGC stack; any
  brand-named pack or OEM-logo/silhouette asset.

**Decisions requiring a Law-1 vote (+ Law-4 intake / instrument-audit as noted):** (1) adopting
generative per-vehicle theming as core UX architecture; (2) the standing IP guardrail ("abstract
primitives + per-asset review"); (3) launching any StoreKit/IAP catalog (money-path, T2+ +
adversarial review + operator gate); (4) bundle-into-Pro vs new SKU + the collector-tier anchor;
(5) VIN-as-seed + the no-PII-on-glanceable-surface rule (instrument-audit); (6) the physical Dossier
pilot; (7) IF ever pursued, any aggregated-cohort/social surface (k-anonymity + consent + moderation).
