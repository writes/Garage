# Assay: Warranty-Proof Pack — claim-ready maintenance evidence export

- **assay_id:** `2026-08-02_warranty-proof-pack`
- **date:** 2026-08-02
- **source:** operator-paste: 2026-08-02 feature-innovation research sweep (operator-directed)
- **source_type:** feature-request · **fetch_status:** paste-only — two primary-source fetch
  attempts failed (endurancewarranty.com guessed URL 404; cartalk.com 403 bot-block); the
  operator paste supplied the substance, and the pain claim is independently consistent with
  standard industry/FTC guidance (keep maintenance records + receipts; claims denied without
  proof of required maintenance).
- **tier:** **A** · **retention:** FULL · **composite:** 11 · **doctrine_fit:** pass
- **validation spec:** `docs/research/2026-08-02_warranty-proof-pack.md` (death condition armed)

## Core claim

A one-tap Warranty-Proof Pack export (claim-oriented preset of the existing dossier engine:
dated, mileage-stamped, itemized services with embedded receipts, a warranty-contract cover
page, and an interval-compliance summary) improves Pro conversion and owner outcomes via
directly targeting the documented top denial reason for extended-warranty claims: missing
proof of maintenance.

## Graveyard check (Stage 0)

No prior assay. Nearest ground, all distinct:

- `2026-07-11_profit-first-strategy-review` (Tier A, adopted) — iOS-7 Wave-3 "PDF evidence
  dossier" targets the **buyer-at-sale** audience; this idea is the **adjuster-during-ownership**
  audience on the same engine.
- `2026-07-24_garage-continuity-full-redesign` (Tier B) — Disclosure-Preview Dossier is again
  the resale surface; its revisit trigger (Wave-3 scheduling) is adjacent but not this idea.

## Surface & mechanism (Stage 2)

- **surface:** `export` (secondaries: `payments` for the gate/SKU, `ui` for the preset flow)
- **mechanism_source:** `real-user-value` — extended-warranty claims are denied specifically
  for missing proof of maintenance; a denied claim costs hundreds to thousands of dollars.
  Concrete, dollar-quantified willingness-to-pay, felt **during** ownership (urgent, adversarial
  moment) rather than only at sale. Adjacent support: CARFAX data errors jeopardizing coverage
  strengthen the owner-controlled-records angle Garage already adopted (trust-wedge, ledger
  2026-07-24).
- **doctrine_fit: pass.** Native SwiftUI on the existing stack; local PDF render (TPPDF
  pipeline); gate via RevenueCat (Pro or one-time IAP — StoreKit-compliant); no secrets, no
  privacy-manifest impact. **Framing constraint (binding, from this assay):** all copy must say
  "organized/formatted for warranty claims" — never "guaranteed accepted" / "satisfies your
  provider." A guarantee is a liability exposure and an App Review misrepresentation risk, and
  it would violate the repo's own no-"verified"-claims provenance taxonomy.

## Codebase ground truth (verified this assay)

- The rendering engine is **not** hypothetical: `Garage/Core/Services/Export/DossierContent.swift`
  + `PDFExportService.swift` were recently rebuilt — per-service **odometer stamps**, embedded
  receipts (`ReportSection.receipts`), and `warranties`/`recalls`/`costSummary` sections all
  render today via the section-selectable export.
- The warranty write path exists: `WarrantyService.saveWarranty` + `WarrantyRecordForms.swift`
  (the older "no write path" memory note is stale). The `Warranty` model already carries
  `providerName`, `planName`, `contractNumber`, `deductible`, coverage windows, `exclusions` —
  everything a claim cover page needs.

## Scores (Stage 3)

| axis | score | justification |
|---|---|---|
| mechanism | 3 | Direct first-principles chain: documented denial reason = "no proof of maintenance" → the artifact compiles exactly the requested proof (dated, mileage-stamped, itemized, receipt-attached). Garage's receipt-parsing wedge means its users disproportionately *have* the receipts that make the pack evidentiary rather than assertive. |
| evidence | 2 | Pain side: multi-source, consistent industry guidance (warranty-provider education content + FTC-style keep-your-records advice) that claims are denied without maintenance proof — case-study grade, though the cited URLs could not be fetched this session. Solution side: **zero** evidence adjusters accept an app-generated PDF or that owners pay for it. Scored on the pain; capped by the absent solution evidence. |
| additivity | 1 | Honest answer to the operator's question: this is a dossier **VARIANT**, not a new capability. The shipped section-selectable export can already produce maintenance history + receipts + warranty info. Genuinely new: the interval-compliance analysis (computed, not reachable today), the claim-oriented one-tap preset + contract cover page, and the during-ownership monetization moment/positioning. |
| capacity | 2 | Local render on an engine that already embeds receipts; scales per-user with no server cost curve. |
| cost_survival | 2 | No marginal API cost; favorable economics either as a Pro-conversion driver or a one-time SKU (RevenueCat + ASC tooling already exist, consumable landmines catalogued). |
| testability | 2 | Trivially pre-registerable: the Option-A A/B stack (PR #23) can run a positioning experiment; a fake-door preset tile measures intent before any engine work. Clear death condition (see spec). |
| implementation_cost | −1 | A sprint, because the engine exists: preset + cover page (model fields present), interval-compliance table from **user-configured** intervals (v1 must NOT attempt manufacturer schedules — that is a data-licensing rabbit hole), disclaimer copy, paywall wiring. |

**Composite = 3+2+1+2+2+2−1 = 11.** Gates: mechanism ≥2 ✓, testability ≥1 ✓, doctrine pass ✓
→ **Tier A**. Note the tier is robust to the harsh additivity reading — even scored as a
variant it clears the bar, because the engine already being built collapses the cost side.

## Why Tier A rather than folding silently into Wave-3

The warranty audience is a **hedge independent of the open resale kill-test**. The resale
dossier's load-bearing premise (buyers pay a premium for owner-authored records) is still
unvalidated; the warranty pack's premise (providers demand maintenance proof and owners fear
denial) does not depend on it. Cheap validation NOW tells us whether the same engine has a
second paying audience before Wave-3 design locks its shape. Per Law 1, actually scheduling
the build (and choosing Pro-bundled vs one-time SKU) remains a tri-vote decision; this assay
authorizes only the pre-registered validation.

## Risks

1. **(Biggest)** Solution-side efficacy and WTP both unvalidated: no evidence an adjuster
   accepts an owner-authored app PDF as sufficient — many extended contracts require
   licensed-shop service, so DIY self-logs without shop receipts may not move a claim — and no
   evidence owners pay for packaging the existing free section-export already approximates.
2. **Overpromise liability:** any drift from "organized for" toward "accepted by providers" is
   a legal exposure and an App Review risk; copy discipline is a binding constraint above.
3. **Interval-compliance can indict:** a compliance table computed over an incomplete log shows
   *gaps* — the feature can document non-compliance. UX must frame gaps honestly (the repo's
   own honesty taxonomy) and never fabricate adherence; this is also why manufacturer-schedule
   inference is out of scope for v1.
4. **Cannibalization ambiguity:** if bundled into Pro it may just re-label existing export value;
   if sold one-time it may undercut the Wave-3 dossier SKU. The positioning experiment reads on
   this before pricing is chosen.
