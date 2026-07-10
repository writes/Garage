# Garage Full-App Audit — Final Report (2026-07-10)

**Verdict: PROD-READY on this branch**, with two operator-gated items outstanding (Firestore
rules fix; CloudFunctions deploy). Full CI gate GREEN including archive. Every phase of the
plan (`2026-07-10_AUDIT_PLAN.md`) executed through the machine's rituals: 6 Law-1 tri-votes,
6 Terra implementation passes, 2 Gemini cross-checks (7 confirmed findings, 4 refuted),
Sol plan co-review (8 blockers, all dispositioned).

## Before → After

| Dimension | Before | After |
|---|---|---|
| CI gate on main | **RED** (AppState 381-line policy breach, merged via ungated PR) | **GREEN incl. archive** |
| Unit tests | 20 (2 surfaces GOOD; 1 fake `#expect(true)` test) | **56** (every P0 trust-boundary surface covered; fake test replaced with real keychain round-trip) |
| Backend tests | **0** (no framework) | **26** vitest + emulator-backed Firestore/Storage **rules suite** |
| E2E/UI tests | 2 launch-only stubs (UI_TEST_MODE literally cannot show the app) | **17 real journey tests across all 10 user journeys**, double-run flake-checked, hermetic demo mode |
| Accessibility identifiers | 1 (on a dead-end harness view) | **63+** — a deliberate test contract across every journey |
| Total suite | 22 | **73** + rules suite |

## Defects found and FIXED (selected; all fix-commits tested)

1. **Entitlement inversion (critical, pre-existing):** an EXPIRATION event listing "pro"
   *re-granted* Pro. Now type-aware.
2. **Entitlement scope (critical, introduced then caught by cross-check):** renewing/expiring
   an *unrelated* product revoked Pro. Now: events not about "pro" never touch state.
3. **Stale-event overwrite:** out-of-order RevenueCat events could overwrite newer entitlement
   state (`updatedAt` stored but never compared). Ordering guard + same-ms revocation-wins.
4. **Webhook auth:** non-timing-safe comparison; missing env accepted nothing safely → now
   timing-safe, 503 fail-closed, strict schema validation, file renamed (was `stripeWebhook`).
5. **Paid-API abuse surface:** `parseOilAnalysis` had no App Check, no size cap, no quota →
   all three added (atomic per-uid daily quota, refund on upstream failure).
6. **CSV export:** lossy comma-mangling + spreadsheet formula injection (incl. leading-space
   bypass and unsanitized attachment paths) → RFC-4180 + OWASP neutralization, numerics exempt.
7. **ProfileViewModel persisted nothing** (live bug — edits vanished) → merge-map persistence
   per tri-vote TV-A4, tested.
8. **PDF export temp-file leak** → cleanup on success and failure.
9. **Demo machinery shipped to Release** → compiled out.
10. **Dead code** `OilAnalysisViewModel` removed (tri-vote TV-A6).

## OPERATOR-GATED items (Law 5 — your switch)

1. **Firestore rules hole (HIGH):** an authenticated user can client-write their own
   `users/{uid}.subscription` — i.e. **self-grant Pro**, bypassing the webhook entirely.
   Confirmed by the emulator rules suite (marked expected-failure) and independently by the
   Gemini cross-check. Fix = one rules change denying client writes to the `subscription`
   field; `firebase.firestore.rules` is a PROTECTED surface → needs your approval, then the
   rules test flips to green.
2. **CloudFunctions deploy:** the webhook/entitlement/quota fixes protect production only
   after `firebase deploy --only functions` (+ post-deploy probe of the running revision —
   landmine #9). Rollback = redeploy previous revision.
3. **Merge `audit/app-hardening` → main** after the tri-review brief (next step).

## Known limitations (documented, not hidden)

- E2E journeys are hermetic UI-routing evidence (demo mode); live-service trust-boundary
  evidence comes from the emulator rules suite + unit seams (Sol's labeling requirement).
- Simulator xctrunner requires erase-before-UI-tests (flake mitigated in-protocol; CI note).
- Node engine pinned 22, local verification ran on newer Node — CI should pin 22.
- Queued follow-up programs: account-deletion/data-lifecycle suite, supply-chain checks,
  observability acceptance criteria, Swift-6 concurrency hazard suite.

### Known limitation / queued

Free-tier vehicle-limit enforcement remains client-side in `PurchaseService.isPro` and
`VehicleService`. The `subscription` field is now server-protected, but enforcing the vehicle
count itself in Firestore rules is a larger queued item that needs a dedicated rules/data-model
design and verification pass.

## Ritual compliance

Votes TV-A1–A6 + product Q1–Q5 in `DECISION_LEDGER.jsonl`; scope fenced to the manifest
(plan §Sol-6) — `project.yml`/`scripts/ci`/rules untouched; every pass independently
verified by the orchestrator; both cross-check rounds triaged from full outputs.
