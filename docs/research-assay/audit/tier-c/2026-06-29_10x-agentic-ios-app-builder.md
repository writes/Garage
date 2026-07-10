# Assay — 10x (agentic AI iOS app builder)

- **assay_id:** `2026-06-29_10x-agentic-ios-app-builder`
- **date:** 2026-06-29
- **source:** https://github.com/10x-app-builder/10x
- **source_type:** repo · **fetch_status:** fetched
- **tier:** **C** (REFERENCE) · **composite:** 6 · **doctrine_fit:** redesign-required
- **surface:** infra (dev tooling / build) · **mechanism_source:** dx-velocity

## Core claim (falsifiable)
> Adopting **10x** — an agentic natural-language → SwiftUI app builder for macOS — as Garage's
> build tool raises development velocity via a **client-side Claude tool-loop** that generates
> SwiftUI code, scaffolds an Xcode project with **XcodeGen**, and previews it in the **iOS
> Simulator**.

## What it is
A macOS app (Swift 94.8%, Swift 5.9, macOS 14+/Xcode 16+) that turns a natural-language app
description into production-ish SwiftUI. Three phases: **describe → plan mode** (research +
architecture Qs) → **build mode** (codegen). The agent runs Claude's full tool loop client-side,
parsing tool-use blocks and executing local file ops until done. Modular services:
`GenerationService` (orchestrates the tool loop), `ToolExecutor` (file I/O), `XcodePreviewService`
(XcodeGen scaffolding), `SimulatorPreviewService` (device sim + screenshots), `LocalProjectStore`
(local persistence). Calls Claude through an **API proxy**; **Supabase** auth. Repo carries a
`10x-evals/` evaluation framework and CI. ~192★ / 43 forks. **License: PolyForm Noncommercial
1.0.0.**

## Why this is REFERENCE, not "adopt" and not "graveyard"
**This is almost certainly the progenitor of *this* repo.** Garage's fingerprints match 10x's
output exactly: native SwiftUI + **XcodeGen** (`project.yml`), a **Claude proxy** Cloud Function
(`claudeProxy.ts`) instead of a client-side key, and a `simulator-local-demo` branch — the precise
shape 10x produces. So 10x is not a hypothetical tool to evaluate cold; it is the likely **origin
of the codebase the machine brain now governs.** That makes it durably worth *remembering* even
though we will not "adopt" it going forward.

It is also a clean reference for our own **machine brain** (Organ II): 10x is a single-vendor,
single-agent, client-side codegen loop; our brain is a multi-vendor (claude+codex+agy),
consensus-gated, sandboxed loop with an immutable promoter. 10x is the thing our motor is the
governed, adversarial evolution of.

## Scoring (sum = composite, −3…+15)
| axis | score | justification |
|---|:--:|---|
| mechanism | **2** | dx-velocity is real and named for *greenfield* iOS scaffolding (NL → compiling SwiftUI). Weaker for a mature 141-file app where marginal generation value is low. |
| evidence | **2** | 192★, a dedicated evals harness, and — strongest of all — this repo is plausibly its shipped output. No rigorous external correctness/quality benchmark, so not a 3. |
| additivity | **1** | Garage is already built; ongoing feature work is Claude-Code + machine-brain driven. 10x mostly re-covers ground we already hold. |
| capacity | **1** | A dev tool, orthogonal to runtime scale; generated-code quality at scale is unproven. Neutral. |
| cost_survival | **0** | **PolyForm Noncommercial license vs a commercial RevenueCat subscription app.** Using 10x to build Garage is plausibly unlicensed commercial use; the economics/compliance do not survive without a commercial license grant. |
| testability | **1** | Falsifiable but not trivial — would need a real feature built by 10x vs by hand, scored on correctness + velocity with a pre-set death condition. |
| implementation_cost | **−1** | A separate macOS app + workflow to integrate with an existing hand-curated codebase and the brain; ~a sprint of friction, not free. |
| **composite** | **6** | |

**doctrine_fit = redesign-required.** It does **not** fail the locked-architecture gate (it
*is* native iOS / XcodeGen / Claude-proxy — fully on-stack, the opposite of the React/PWA reject
`2026-06-29_react-pwa-supabase-rewrite`). The blocker is the **license**: commercial use must be
cleared (commercial license or written grant) before 10x may be used to build a paid app.

## Biggest risk
The **PolyForm Noncommercial 1.0.0** license against Garage being a **commercial** subscription
product — this is both a forward blocker (can't adopt for paid-app dev without a commercial
grant) **and** a possible *existing* exposure worth checking if 10x generated this repo.

## The tradeoff to remember (why we keep this on file)
**Build-by-agent vs build-by-hand for a commercial iOS app.** Agentic codegen wins on greenfield
speed and loses on (a) license/IP provenance of generated code, (b) marginal value once a
codebase is mature, and (c) the lack of an adversarial/consensus check that our machine brain
adds. When this tradeoff resurfaces (e.g. "regenerate module X with an agent"), reread this entry
before re-litigating.

## Disposition
**Keep as REFERENCE. Do not adopt as Garage's build tool** unless the license question is
resolved. No pre-registered validation spec (Tier C, not A). If a commercial-license path opens
*and* a concrete high-velocity need appears, that is a new, sharper idea — assay it fresh then.

## Verification flag for the operator (separate from this assay)
If 10x (noncommercial) did generate this repo, confirm there is no licensing conflict with
shipping Garage commercially. This is a compliance check, not a tiering input.
