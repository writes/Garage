# Tier D — Consumer OBD hardware/dongle integration

- **assay_id:** `2026-07-11_consumer-obd-dongle-integration`
- **date:** 2026-07-11 · **tier: D** (graveyard — evidence-dated exclusion) · **retention:** TERSE
- **composite:** 2 · **doctrine_fit:** pass (killed on economics + score, not the gate)
- **source:** `docs/research/2026-07-10_PRODUCT_EXPANSION_RESEARCH.md` §13 (Sol correction #5, R6 named-corpse queue)

## Core claim
Integrating consumer OBD hardware/dongles improves log completeness and engagement via
auto-captured mileage, diagnostics, and trip data flowing into the service history.

## Kill reason
- **Named corpse:** Automatic Labs died in 2020 — the best-funded consumer OBD-dongle play,
  killed by exactly this model.
- **Hardware COGS breaks asset-light economics:** sourcing, fulfillment, returns, firmware, and
  support are a permanent cost structure incompatible with Garage's subscription/SKU economics
  (`cost_survival` 0, `implementation_cost` −3).
- **Reputation contamination:** FIXD/Carly's "subscription trap" reputation shows the category
  actively damages consumer trust — the one asset the Passport wedge depends on.
- Auto-captured data would be genuinely additive (`additivity` 2) but nothing else survives:
  composite 2.

## Biggest risk
Hardware economics sink the P&L while category reputation poisons the trust brand — a double
loss with a documented corpse proving both.

## Reconsideration trigger (evidence-dated exclusion, per Sol correction #5)
**Hardware-free OBD data access becomes platform-native on iOS** (e.g., Apple exposes vehicle
diagnostics/odometer via a public framework — no dongle, no COGS). Only that removes the kill
mechanism; do not re-assay otherwise.
