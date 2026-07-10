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

- 2026-07-10 · **Tier A** · Pin Gemini lanes to exact agy roster label "Gemini 3.1 Pro (High)"; operator-requested "Gemini Pro Preview" DOES NOT EXIST in the roster (all preview-style names silently downgrade to 3.5 Flash — landmine #12). · composite 17 · adopted: death = pinned label vanishes from roster or a stronger Pro label passes intake · → tier-a/2026-07-10_gemini-3.1-pro-high-pin.md
- 2026-07-10 · **Tier A** · Route strategy/votes/review to GPT-5.6 Sol and implementation to GPT-5.6 Terra via codex CLI ≥0.144.1 (0.143.0 400-ed on 5.6 — stale CLI is a proven single point of failure). · composite 16 · adopted: death = Sol/Terra off subscription tier or measured quality regression vs GPT-5.5 · → tier-a/2026-07-10_gpt-5.6-sol-terra-routing.md
- 2026-06-29 · **Tier C** · Adopting 10x (agentic NL→SwiftUI app builder; client-side Claude tool-loop + XcodeGen + Simulator preview) as Garage's build tool. · composite 6 · keep-as-REFERENCE: doctrine-compatible & likely this repo's progenitor, but PolyForm-Noncommercial license blocks commercial adoption (and is a possible existing exposure) → redesign-required · → tier-c/2026-06-29_10x-agentic-ios-app-builder.md
- 2026-06-29 · **Tier D** · Rewriting the Garage app as a React PWA (React + Tailwind + Supabase + Vercel) per blueprint.md's stack would improve velocity/cost via a web stack, replacing native SwiftUI + Firebase. · composite 2 · kill: doctrine_fit=fail (native iOS architecture is LOCKED per README.md; blueprint is product truth, not stack truth) · → tier-d/2026-06-29_react-pwa-supabase-rewrite.md
<!-- newest assays are PREPENDED above this line; keep this comment last -->
