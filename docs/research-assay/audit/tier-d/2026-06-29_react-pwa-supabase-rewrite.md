# Tier D — Rewrite Garage as a React PWA (React + Tailwind + Supabase + Vercel)

- **assay_id:** `2026-06-29_react-pwa-supabase-rewrite`
- **date:** 2026-06-29
- **tier:** **D** (graveyard)
- **retention:** TERSE
- **composite:** 2
- **doctrine_fit:** **fail** (hard gate)

## Stage 1 — Intake

- **source:** `operator-paste:rewrite-as-react-pwa-per-blueprint`
- **source_type:** operator-idea
- **fetch_status:** paste-only
- **core_claim:** *"Rewriting the Garage app as a React PWA (React + Tailwind +
  Supabase + Vercel), per blueprint.md's original tech stack, improves
  iteration velocity and lowers cost by replacing the native SwiftUI + Firebase
  implementation with a web stack."*

## Stage 2 — Surface & mechanism

- **surface:** `full` — this is an end-to-end replacement of the delivery stack,
  the backend, auth, storage, and the entire client.
- **mechanism_source:** `dx-velocity` (the claimed payoff is "faster to iterate"
  / "cheaper to host" per blueprint.md lines 14–22). The mechanism is real *for
  a greenfield web project*, but it is not additive here — see below.
- **doctrine_fit:** **fail.**

### Why it fails the doctrine gate

The repository's architecture is **locked to native iOS**, and the inbound idea
proposes to discard exactly that. Evidence in-repo:

1. **README.md, line 3:** "Garage is a **native iOS app** for serious car
   owners…" The product is defined as native, not as a web app.
2. **README.md, line 7:** "The product requirements in `blueprint.md` are
   treated as feature truth. **Where the blueprint's delivery stack differs from
   this repository, the product detail is preserved and implemented on the
   locked native iOS architecture in this repo.**" This is the controlling rule:
   `blueprint.md` is **product truth, not stack truth**. The blueprint's
   React/Tailwind/Supabase/Vercel stack (`blueprint.md` lines 14–22) is
   explicitly superseded by the locked native architecture — the features are
   carried over, the stack is not.
3. **project.yml:** the repo is an XcodeGen-generated **native iOS application**
   target — `SWIFT_VERSION: 6.0`, `SWIFT_STRICT_CONCURRENCY: complete`,
   `deploymentTarget.iOS: "17.0"`, SwiftUI, and Swift Package dependencies on
   `Firebase`, `GoogleSignIn`, `RevenueCat`, and `TPPDF`. There is no web
   toolchain, no Node/Vercel build, and no Supabase anywhere in the build graph.

The idea does not merely add to the candidate surface (features / libraries /
architecture); it proposes to demolish the protected, locked foundation and the
real Firebase backend. That is a direct doctrine violation: native iOS-only (not
a PWA), real Firebase backend (not Supabase). Per the tiering rule,
`doctrine_fit = fail` ⇒ **Tier D regardless of composite.**

## Stage 3 — Score (recorded for the graveyard, even though the gate decides)

| axis | score | reasoning |
|------|------:|-----------|
| mechanism | 1 | "web is faster to iterate" is a real mechanism in the abstract, but irrelevant once a native app already exists and is shipping. |
| evidence | 1 | PWAs are proven generally, but there is zero evidence a *rewrite of this app* beats the current native one; it's an assertion. |
| additivity | 0 | Adds nothing over what's shipped — it *replaces* it. Pure redundancy with negative carry. |
| capacity | 1 | Supabase/Postgres scales fine in principle; neutral, not a differentiator. |
| cost_survival | 1 | "Free tiers" understate the real cost: a full rewrite plus dual-maintenance during migration; App Store presence still required. |
| testability | 1 | The velocity/cost claim is only testable by actually doing the rewrite — there is no cheap pre-registered experiment. |
| implementation_cost | −4 → clamped to −3 | A ground-up rewrite of the client AND a backend migration (Firebase→Supabase, Auth, Storage, Functions, App Check, RevenueCat, Claude-API PDF parsing). Maximum penalty. |

**composite = 1 + 1 + 0 + 1 + 1 + 1 + (−3) = 2.**

Even ignoring the gate, composite 2 is far below the Tier-D ceiling of 6. The
gate and the rubric agree.

## Stage 4 — Tier

- composite 2 (≤ 6) → Tier D on score alone.
- `doctrine_fit = fail` → Tier D by hard gate.
- redundant (replaces shipped native app) → Tier D.

All three independent paths land on **Tier D**. retention **TERSE**.

## Stage 5 — Biggest risk & disposition

- **biggest_risk:** Acting on this would throw away a working, locked native iOS
  codebase and its real Firebase + RevenueCat + Claude-API backend to chase a
  velocity story that the repo has already explicitly decided against — a
  total-loss rewrite with no additive user value.
- **Disposition:** Buried. The product *features* described alongside the
  blueprint's stack remain valid intake (assay those individually on their own
  merits, implemented natively). The **stack swap itself is dead ground** — do
  not re-assay it. If someone proposes "React PWA", "Supabase", "Vercel", or
  "web rewrite" again, Stage 0 will surface this headstone and the answer is
  already written here.

> A dead idea is dead. This one fails the locked-architecture doctrine; it is not
> reopened by enthusiasm, only by a documented reversal of the locked native-iOS
> decision in README.md — which is out of scope for the intake funnel.
