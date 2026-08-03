# Idea Graveyard — research-assay audit registry

This is the **human-readable idea graveyard** for the Garage iOS app. Every
inbound idea, library, SDK, paper, blog, or feature request that gets assayed by
the `research-assay` agent leaves a one-line headstone here, **newest first**.

Its machine-readable twin is `index.jsonl` (one JSON row per assay, validated by
`index.schema.json`). Full reasoning lives in `tier-<a|b|c|d>/<assay_id>.md`.

## The law: SEARCH BEFORE EVALUATING

A dead idea is dead. Each idea is assayed **once**. Re-running a buried idea to
"double-check" is p-hacking the graveyard and inflates the decision count for no
reason. If an idea already has a headstone here, return its verdict and stop.

## Tiers

- **Tier A** — `composite ≥ 11`, real mechanism, testable, passes doctrine.
  Validate now; gets a pre-registered spec in `docs/research/` with a death
  condition. Retention FULL.
- **Tier B** — `composite 7–10`. Backlog with a concrete `revisit_trigger`.
  Retention SUMMARY.
- **Tier C** — high reference value even if not adopted (teaches a durable
  tradeoff). Retention FULL.
- **Tier D** — `composite ≤ 6`, refuted, redundant, or **doctrine_fit = fail**.
  Graveyard. Retention TERSE.

`doctrine_fit = fail` is a hard gate: it forces Tier D regardless of composite.
Doctrine = native iOS-only (no PWA/web/cross-platform rewrite), Swift 6 strict
concurrency, real Firebase backend, no secrets in client, App Store + privacy
manifest compliance.

## How to search (do this BEFORE assaying anything)

Grep this file and `index.jsonl` for the idea's keywords — try several aliases
(library name, vendor, technique, feature noun):

```bash
grep -iE 'react|pwa|supabase|<keyword>' docs/research-assay/audit/REGISTRY.md
grep -iE 'react|pwa|supabase|<keyword>' docs/research-assay/audit/index.jsonl
```

If you find a match, you are done — report the prior tier and stop.

## Assays (newest first)

- 2026-08-02 · **Tier D** · Adopting Qwen 3.8 as challenger/replacement for the pinned claude-haiku-4-5-20251001 in CloudFunctions typed extraction (receipt/PDF, voice quick-add) improves extraction economics via a cheaper frontier open-weight model served through OpenRouter/DashScope. · composite 6 · kill: secondary evidence confirms frontier-range capability (Arena Frontend Code #4 at 1668 Elo — weakest admissible class; independent 80/100 architecture eval, zero failed tool calls) but NONE of it is extraction task-completion; intake-blocked at stage 1 (no standalone API, no pricing, no license, no model card — 7-stage protocol cannot reach the plumbing probe; primary announcement unreachable JS shell); quality axis saturated (pinned Haiku 100% CORE, floors met with margin, failures are deterministic omissions); cost mechanism fails even on paper (Qwen-Max family $1.25/$3.75 ≈ Haiku $1/$5 at quota-capped volume); sprint-plus qualification cost (new vendor secret in protected CloudFunctions/.env, data-processor privacy disclosure, Haiku-tuned few-shots don't transfer); observation-only — verdict rests on the volume/economics legs, so the evidence upgrade is NOT an adoption signal; the Qwen/OpenRouter roster question belongs to the trading repo · → tier-d/2026-08-02_qwen3-8-extraction-challenger.md
- 2026-08-02 · **Tier A** · One-tap Warranty-Proof Pack (claim-oriented preset of the existing dossier engine: mileage-stamped services + embedded receipts + warranty-contract cover + interval-compliance summary) improves Pro conversion and owner outcomes via targeting the documented top extended-warranty denial reason — missing proof of maintenance. · composite 11 · keep: validate now — honest dossier VARIANT (additivity 1; the shipped section export already produces maintenance+receipts+warranty PDF) but a direct dollar-quantified pain, a during-ownership moment independent of the open resale kill-test, sprint-cost on the existing DossierContent/PDFExportService engine; positioning A/B + fake-door death condition armed in docs/research/2026-08-02_warranty-proof-pack.md · → tier-a/2026-08-02_warranty-proof-pack.md
- 2026-08-02 · **Tier A** · A True-Cost-of-Ownership layer on Stats (whole-garage total spend, 12-month spend trajectory, per-vehicle comparison, full-history-correct totals) improves Pro conversion and engagement via turning already-captured entry costs into the ownership-economics answer competitor users ask for by name. · composite 11 · keep: validate NOW — data already on hand, sprint-level cost, doctrine-clean; per-vehicle totals/per-mile ALREADY shipped (OwnershipCostCard), the new value is the garage-wide + trajectory + full-history layer; v1 EXCLUDES keep-vs-replace/depreciation (licensed-valuation risk; fresh intake required); death condition armed in docs/research/2026-08-02_true-cost-of-ownership-dashboard.md · → tier-a/2026-08-02_true-cost-of-ownership-dashboard.md
- 2026-08-02 · **Tier B** · "Ask Garage" history-aware AI mechanic chat (advisory Q&A grounded in VIN + full in-app service history, metered on the existing receipt-credits consumable + Pro quota plumbing) improves Pro conversion & engagement via vehicle-specific answers. · composite 10 · backlog: plumbing verified real (claudeProxy/creditLedger/quota/RC webhook) and grounding is first-principles-strong for the maintenance-guidance slice, but headline hooks (noise, quote-fairness) outrun the owned data → generic-advice liability + FIXD-style advisory-upsell reputation that dilutes the trust wedge; WTP unvalidated (competitor shipping ≠ traction); queued 5.1.2(i)/AI-consent decision gates all new AI surfaces; multi-turn chat = quarter-class, not "just a new prompt"; revisit = consent UI ships + golden-set eval shows grounded ≫ ungrounded, or real competitor traction evidence · → tier-b/2026-08-02_ask-garage-history-aware-ai-chat.md
- 2026-08-02 · **Tier B** · Per-household subscription tier with a shared multi-member garage improves ARPU/retention via family-circle pricing (Life360 model) capturing multi-driver households per-uid Pro cannot serve. · composite 7 · backlog: real family-admin pain + Life360 circle-pricing proof at scale, but the analogy is imperfect (safety is intrinsically multi-member; logging is single-admin, already served by Pro-5) and direct evidence points at SLOTS not sharing, while cost = full protected-surface firestore.rules rewrite (per-uid single-owner everywhere) + invites + pooled getAfter counters + shared-record deletion semantics + permanent ACL tax; revisit = fake-door "Family garage" teaser >=5% Pro conversion in 30d OR >=10 organic multi-member-access requests OR 5-cap telemetry showing distinct drivers · → tier-b/2026-08-02_household-tier-shared-garage.md
- 2026-07-24 · **Tier B** · "Garage Continuity" full product/brand/IA redesign (Today/Ledger/Record/Vehicle IA, Record Stamp provenance, Correction Branch, Commit-to-Ledger drafts, Disclosure-Preview Dossier, quiet-stewardship brand, contextual monetization) improves comprehension/trust/dossier conversion via explicit owner-controlled record semantics. · composite 7 · keep-UNBUNDLED: provenance/dossier core = the governing blueprint's wedge as UX (Dossier ≈ voted Wave-3 iOS-7; Record Stamp concretizes the binding no-"verified" taxonomy) but the IA+brand swap half is weak-mechanism, zero-outcome-evidence, quarter-plus cost, riding the open resale kill-test; native-SwiftUI (NOT the Tier-D re-platform); revisit = Wave-3 scheduling OR kill-test PASS OR operator opens Q5 naming workstream · → tier-b/2026-07-24_garage-continuity-full-redesign.md
- 2026-07-23 · **Tier B** · Adopting XcodeBuildMCP (MCP server + CLI wrapping xcodebuild/simulator/device tooling) improves this repo's machine-brain agent build/test/simulate loops via structured, typed MCP tool calls in place of raw-shell xcodebuild invocation and manual log parsing. · composite 9 · backlog: real dx-velocity mechanism, MIT license, 6.1k-star adoption, but everything it does is already reachable via Bash+xcodebuild+scripts/ci (additivity 1) and unverified against this repo's exact XcodeGen/Swift-6 setup; revisit = a pilot shows real turn/token win with zero CI-gate interference, or agents log measurable xcodebuild-parsing friction · → tier-b/2026-07-23_xcodebuildmcp-agent-build-tooling.md
- 2026-07-21 · **Tier B** · Generative per-vehicle 'Livery' identity from NHTSA vPIC VIN facts + owner photos (bundled in Pro) + $6.99 Certificate-of-Provenance PDF + Garage Wrapped recap improves Pro retention & adds resale revenue. · composite 8 · backlog: strong reframe (cosmetics need social visibility → theming = retention lever, real WTP only on stranger-facing resale surface) but retention-lift & resale-WTP both unvalidated for this non-social audience + quarter-plus build + permanent IP/WCAG tax; revisit = profit-first resale kill-test concludes OR Phase-1 theming retention A/B shows lift · → tier-b/2026-07-21_generative-vehicle-identity-monetization.md
- 2026-07-11 · **Tier A** · External profit-first strategy review of Garage (operator-supplied) — evidence-quality/trust wedge + sale-time Backfill & Passport SKU + corrected offer ladder. · composite 12 · adopted-with-corrections: ALREADY PROCESSED (verification + re-votes + adoption doc `docs/research/2026-07-11_PROFIT_FIRST_BLUEPRINT.md`; 8 claims accepted, naming substantially-correct, ToS accurate, Motorkeep-app claim overstated — web-only); kill-test gate armed, do not re-assay · → tier-a/2026-07-11_profit-first-strategy-review.md
- 2026-07-11 · **Tier D** · Consumer OBD hardware/dongle integration improves log completeness/engagement via auto-captured mileage & diagnostics. · composite 2 · kill: evidence-dated exclusion — Automatic Labs dead 2020; hardware COGS breaks asset-light economics; FIXD/Carly subscription-trap reputation; reopen ONLY if hardware-free OBD access becomes platform-native on iOS · → tier-d/2026-07-11_consumer-obd-dongle-integration.md
- 2026-07-11 · **Tier D** · Home/asset maintenance vault vertical improves TAM via homeowners keeping provenance-priced maintenance records. · composite 1 · kill: evidence-dated exclusion — Centriq dead 2026-01; homes fail all three adjacency tests (appraisal pricing, ~13-yr holds, no provenance-priced resale market); reopen ONLY on material new evidence of provenance-priced home resale behavior · → tier-d/2026-07-11_home-maintenance-vault-vertical.md
- 2026-07-10 · **Tier A** · Pin Gemini lanes to exact agy roster label "Gemini 3.1 Pro (High)"; operator-requested "Gemini Pro Preview" DOES NOT EXIST in the roster (all preview-style names silently downgrade to 3.5 Flash — landmine #12). · composite 17 · adopted: death = pinned label vanishes from roster or a stronger Pro label passes intake · → tier-a/2026-07-10_gemini-3.1-pro-high-pin.md
- 2026-07-10 · **Tier A** · Route strategy/votes/review to GPT-5.6 Sol and implementation to GPT-5.6 Terra via codex CLI ≥0.144.1 (0.143.0 400-ed on 5.6 — stale CLI is a proven single point of failure). · composite 16 · adopted: death = Sol/Terra off subscription tier or measured quality regression vs GPT-5.5 · → tier-a/2026-07-10_gpt-5.6-sol-terra-routing.md
- 2026-06-29 · **Tier C** · Adopting 10x (agentic NL→SwiftUI app builder; client-side Claude tool-loop + XcodeGen + Simulator preview) as Garage's build tool. · composite 6 · keep-as-REFERENCE: doctrine-compatible & likely this repo's progenitor, but PolyForm-Noncommercial license blocks commercial adoption (and is a possible existing exposure) → redesign-required · → tier-c/2026-06-29_10x-agentic-ios-app-builder.md
- 2026-06-29 · **Tier D** · Rewriting the Garage app as a React PWA (React + Tailwind + Supabase + Vercel) per blueprint.md's stack would improve velocity/cost via a web stack, replacing native SwiftUI + Firebase. · composite 2 · kill: doctrine_fit=fail (native iOS architecture is LOCKED per README.md; blueprint is product truth, not stack truth) · → tier-d/2026-06-29_react-pwa-supabase-rewrite.md
<!-- newest assays are PREPENDED above this line; keep this comment last -->
