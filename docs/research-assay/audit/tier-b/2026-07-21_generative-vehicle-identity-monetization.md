# Tier B — Generative per-vehicle identity + resale-provenance monetization

- **assay_id:** `2026-07-21_generative-vehicle-identity-monetization`
- **date:** 2026-07-21
- **source:** `docs/research/2026-07-21_DESIGN_PERSONALIZATION_MONETIZATION_RESEARCH.md` (internal-doc, fetched)
- **surface:** ui (secondaries: payments, export)
- **mechanism_source:** real-user-value
- **doctrine_fit:** pass (conditional — see kill/death conditions)
- **composite:** 8 → **Tier B** · retention **SUMMARY**

## core_claim (falsifiable)

Deriving a deterministic, trademark-free per-vehicle "Livery" theme (palette / ambient motion /
abstract archetype glyph) from public NHTSA vPIC VIN facts + the owner's own photos, computed once
at VIN decode and bundled INTO the existing Pro subscription — plus a $6.99 one-time
Certificate-of-Provenance resale PDF and a Garage Wrapped annual recap (free 3-card teaser → Pro) —
**improves Pro retention and adds a resale-driven revenue line via psychological-ownership
differentiation and stranger-facing, dollar-stakes provenance.**

## Scores

| axis | score | why |
|---|---|---|
| mechanism | 2 | Strong first-principles reframe: cosmetics need social visibility to sell (Fortnite/Strava/Duolingo all depend on being SEEN); a private log has none, so theming is correctly re-cast as a bundled RETENTION lever (Strava model) and real WTP is put on the stranger-facing resale surface. IKEA-effect / psychological-ownership is a real named driver. Not 3: the load-bearing magnitude (does theming move retention for a *utility* app — "wallpaper vs workflow") is hypothesis-grade. |
| evidence | 1 | Precedents (Strava icons-as-Pro-perk, Spotify Wrapped conversion) are shipped-at-scale but for SOCIAL products; the doc's own thesis (Garage has no social surface) undercuts direct transfer. Plus generic aggregator stats (McKinsey 10–15%, "87% pay more"). No direct evidence for this de-socialized application; resale-premium claim is explicitly behind an unvalidated kill-test. Analogy > anecdote, but not case-studies-of-THIS. |
| additivity | 2 | Livery engine + Wrapped are clearly new value a spreadsheet competitor can't copy. But the Certificate/resale-monetization sub-part overlaps the already-Tier-A-adopted profit-first Passport/Backfill resale wedge (`docs/research/2026-07-11_PROFIT_FIRST_BLUEPRINT.md`) — partly redundant. Averages to 2. |
| capacity | 2 | Designed to scale: themes computed once at decode into cached static tokens (no per-frame recompute), Wrapped is an annual batch over owned data, Certificate is a PDF export. Bottleneck risk: "per-asset IP review, forever" — scales only if it means reviewing the bounded primitive registry, not each user's generated crest. |
| cost_survival | 2 | $6.99 non-consumable nets ~$5 after Apple cut; deterministic compute ≈ free; NHTSA vPIC free; no Claude-API/recurring infra cost; bundle-into-Pro is anti-cannibalization by design (Discord additive-only rule). App-fee / Firebase / subscription economics all favorable. (Legal carrying cost lives in implementation_cost + biggest_risk, not here.) |
| testability | 2 | The doc pre-registers the go/no-go: A/B the $6.99 Certificate attach/lift; Wrapped teaser→Pro conversion is a clean A/B; theming retention is a cohort delta. Trivial death conditions definable. |
| implementation_cost | −3 | Multi-surface build (generative theme engine + WCAG-AA contrast clamp + MeshGradient-with-iOS-17-fallback + Reduce-Motion/Plain-Mode + device-tier motion gating + battery test on oldest device; VIN decode; crest generator + curated registry; StoreKit/RevenueCat non-consumable + PDF cert; Wrapped engine + teaser gating; density calendar + medallions) **plus a PERMANENT tax**: forever per-asset IP legal review, WCAG/perf CI checklist lines, privacy-manifest upkeep. Quarter-plus + permanent tax = −3. |

Composite = 2 + 1 + 2 + 2 + 2 + 2 − 3 = **8**.

## Tier rationale

Not D (composite 8 > 6, not refuted, not fully redundant, doctrine_fit ≠ fail). Not A (composite < 11).
Composite 8 sits squarely in B's 7–10 band, and this is a concrete, buildable, testable proposal
with a phased A/B gate — a **backlog item behind a validation gate**, not a filed-away reference
lesson. → **Tier B, SUMMARY.**

## biggest_risk

A quarter-plus build plus a PERMANENT IP-review + WCAG/perf tax is spent on differentiation whose
two load-bearing payoffs are both **unvalidated for this non-social utility audience** — theming may
be "wallpaper not workflow" (no retention lift), and the $6.99 Certificate's resale-premium WTP
rides the **same still-open profit-first kill-test** — so if either fails, the spend does not return.

## revisit_trigger

The 2026-07-11 profit-first resale kill-test concludes (it directly determines whether the
Certificate/provenance monetization pillar has any evidentiary basis — a PASS promotes Phase-2
Certificate + Wrapped to a fresh tri-vote + StoreKit money-path intake; a FAIL kills the Certificate
rationale, leaving only the bundled-in-Pro theming/Wrapped retention lever to stand on its own),
**OR** a cheap Phase-1 in-Pro theming cohort A/B shows a measurable retention lift over the
no-theme baseline.

## Kill / death conditions to carry forward (operator-flagged)

These are hard gates, not design suggestions — any build must treat them as CI/legal blockers:

- **Trademark / trade-dress on generated crests** — a generated glyph inadvertently mimics a
  protected mark (Ferrari trade dress, Jeep 7-slot grille) → litigation + Apple Guideline 5.2
  takedown. Mitigation: abstract, non-representational primitives from a bounded, human-reviewed
  registry only; drop the crest entirely before shipping anything representational.
- **VIN-as-quasi-PII** — hash the VIN for the art seed; keep VIN/plate/nickname/resale figures OFF
  any lock-screen / Live Activity / shared-poster surface; declare in the privacy manifest.
- **MeshGradient is iOS 18+, app targets iOS 17+** — explicit static/frosted fallback required;
  animate foreground only; device-tier motion gate; battery MEASURED on the oldest supported device
  (never simulator).
- **WCAG contrast** — contrast-clamp every derived palette to AA before render; Reduce-Motion +
  global Plain Mode; never color-only encoding; VoiceOver narrates art as data.
- **"Certificate/verified" copy = FTC/fraud exposure** — "owner-maintained record" ONLY.
- **Cosmetic cannibalization of Pro** — bundle-into-Pro + Discord additive-only rule; no expiring
  currency / loot boxes (also an Apple red line).
- **Gamification near a purchase decision** — Robinhood/SEC precedent; scope density/medallions to
  care behaviors, never a Pro-upgrade / add-vehicle / AI-upsell nudge.

## Durable lesson (reference value)

The reusable strategic tradeoff this names: **cosmetic monetization requires a social-visibility
surface; without one, personalization is a retention/differentiation lever (bundle it into the
sub), and the only real willingness-to-pay lives on stranger-facing, dollar-stakes surfaces**
(resale). Meet this again on any future "let users customize / buy cosmetics" idea.

## Governance note

Per the source doc §7, this is PHASE-0 GATE material: it still requires a Law-1 tri-agent vote to
adopt generative per-vehicle theming as core UX architecture, and any StoreKit/IAP catalog is a
money-path change (T2+ implementation + adversarial review + operator gate). This assay is the
Law-4 intake half of that gate — advisory, not a build authorization.
