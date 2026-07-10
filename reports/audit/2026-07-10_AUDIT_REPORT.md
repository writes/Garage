# Garage Full-App Audit — Final Report (2026-07-10)

**Verdict: merge-ready on `audit/app-hardening`** pending the final review + your gate. Full CI
gate GREEN (build + archive + all suites). The plan (`2026-07-10_AUDIT_PLAN.md`) ran fully
through the machine's rituals: **6 Law-1 audit tri-votes + 5 product tri-votes**, **8 Terra
implementation passes (A–H)**, **3 Gemini cross-checks + 5 three-provider merge-review rounds**,
Sol plan co-review (8 blockers dispositioned). Every implementer green was independently
re-verified by the orchestrator on a clean simulator.

## Before → After

| Dimension | Before | After |
|---|---|---|
| CI gate on main | **RED** (AppState 381-line policy breach, merged via ungated PR) | **GREEN incl. archive + Release build** |
| Unit tests (iOS) | 20 (2 surfaces GOOD; 1 fake `#expect(true)`) | **~59** — every P0 trust-boundary surface; fake test → real keychain round-trip |
| Backend tests | **0** (no framework) | **31** vitest + **8** emulator-backed Firestore/Storage **rules** tests |
| E2E / UI tests | 2 launch-only stubs (UI_TEST_MODE cannot even show the app) | **19 real journey tests / 10 journeys**, double-run flake-checked |
| Accessibility identifiers | 1 (dead-end harness view) | **63+** deliberate test contract |
| Full iOS suite | 22 | **78+**, independently green |

## Defects found & FIXED (all with regression tests; the review loop found most of these)

**Trust boundary / payments**
1. Entitlement **inversion** — EXPIRATION listing "pro" *re-granted* Pro → type-aware.
2. Entitlement **scope** — renewing/expiring an *unrelated* product revoked Pro → non-pro
   events never touch state.
3. **Stale-event overwrite** — out-of-order events clobbered newer state → ordering guard.
4. **Transaction read-after-write** (prod-only critical) — `set(eventRef)` before
   `get(userRef)`; real Firestore throws → every event would have failed in production. 78
   green tests missed it because the fake was lenient. Reordered **and the fake now enforces
   read-before-write** so the bug class can't recur.
5. **Webhook auth** — non-timing-safe compare, no fail-closed → timing-safe, 503 on missing
   config, strict schema, file renamed (`stripeWebhook`→`revenueCatWebhook`).
6. **Missing-user race** — webhook 400'd (RevenueCat retries exhaust, entitlement lost) →
   durable upsert.
7. **TRANSFER events** rejected as malformed → handled.
8. **Paid-API abuse** — `parseOilAnalysis` had no App Check / size cap / quota → all added;
   refund only on infrastructure failure, **not** on a billed unrecognized response.
9. **Firestore rules self-grant Pro** — any user could client-write `subscription` → denied;
   rules test flipped from expected-failure to **enforced**. *(Protected surface — see gate.)*

**Data integrity / correctness**
10. **CSV export** — lossy comma-mangling + formula injection (leading-space bypass,
    unsanitized attachment paths) → RFC-4180 + OWASP neutralization, numerics exempt.
11. **ProfileViewModel persisted nothing**, then (Pass E) persisted to literal dotted keys the
    loader never read → nested-map `setData(merge:)`, forward-compat preserved.
12. **PDF temp-file leak** → cleanup on success and failure.
13. **DashboardView stale on vehicle switch** → reloads on `currentVehicle` change.

**Release hygiene**
14. **Demo store + test-injection initializers compiled into Release** → `#if DEBUG`; Release
    build verified.
15. Dead `OilAnalysisViewModel` removed (tri-vote).

## OPERATOR-GATED — your switches (Law 5)

1. **Deploy Firestore rules** — the self-grant-Pro fix lives in `firebase.firestore.rules` (a
   PROTECTED surface I edited under supervision; the emulator suite proves it). It protects
   production only after you publish it. `firebase deploy --only firestore:rules`.
2. **Deploy CloudFunctions** — the webhook/entitlement/quota/transaction fixes protect
   production only after `firebase deploy --only functions` + a probe of the **running**
   revision (landmine #9). Rollback = redeploy previous revision.
3. **Fill placeholder policy URLs** — `Constants.privacyPolicyURLString` /
   `termsOfUseURLString` are `OPERATOR-REPLACE-*.invalid`; App Store review needs real ones.
4. **Merge `audit/app-hardening` → main** after the final review brief.

## Known limitations / queued (documented, not hidden)

- **Free-tier vehicle COUNT is still client-enforced** (`PurchaseService.isPro` /
  `VehicleService`). The `subscription` field is now server-protected, but enforcing the count
  itself in rules is a dedicated data-model + rules design pass — queued.
- E2E journeys are hermetic UI-routing evidence (demo mode); live trust-boundary evidence is
  the emulator rules suite + unit seams (per Sol's labeling requirement).
- Simulator xctrunner needs erase-before-UI-tests + occasional stale-host cleanup — CI note.
- Node engine pinned 22; pin CI to 22.
- Queued programs: account-deletion/data-lifecycle suite, supply-chain checks, observability
  acceptance criteria, Swift-6 concurrency hazard suite (Sol's plan-review improvements).

## Ritual compliance

Tri-votes TV-A1–A6 (audit) + Q1–Q5 (product) + the operator-override merge in
`DECISION_LEDGER.jsonl`; scope fenced to the plan's protected-surface manifest — `project.yml`
and `scripts/ci` untouched, the one rules edit flagged for your deploy gate; every pass
orchestrator-verified on a clean simulator; all review rounds triaged from full outputs.
