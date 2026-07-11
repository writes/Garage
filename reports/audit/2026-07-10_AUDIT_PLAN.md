# Garage Full-App Audit & Hardening Plan (operator directive 2026-07-10)

- **Status:** Fable draft → Sol strategic co-review (routing v3 planning lane)
- **Evidence base:** `reports/audit/2026-07-10_coverage-matrix.md` (5-agent discovery sweep,
  250k tokens, 168 tool calls) + baseline CI run.
- **Branch:** `audit/app-hardening` (worktree). Merge to `main` only via tri_review + operator
  gate (Law 5). Implementation: Terra (+ Gemini cross-check). Doctrine: no solo decisions on
  substance; CI gate is the sole promoter.

## Baseline (verified live 2026-07-10)

- Build: GREEN. Unit tests: 20/20 GREEN (thin). UI tests: 2 launch-only stubs.
- Policy gate was RED on main (AppState.swift 381 > 300) — **fixed** on this branch
  (seed-data extraction, pure refactor; full test re-run pending).
- Coverage: 2/~30 surfaces GOOD; every trust-boundary surface at NONE.

## Phase P0 — Trust-boundary correctness (unit + service tests, plus 3 real code fixes)

| # | Work item | Kind |
|---|---|---|
| P0.1 | `handleRevenueCatWebhook` unit tests (entitlement grant/revoke, idempotency, bad secret, malformed events) — CloudFunctions/`vitest`/`jest` per existing tooling | tests |
| P0.2 | **Webhook auth hardening**: HMAC signature verification (RevenueCat `X-RevenueCat-Signature`) replacing/augmenting static shared secret; rename misleading `stripeWebhook.ts` | fix + tests |
| P0.3 | **`parseOilAnalysis` App Check enforcement** (`enforceAppCheck: true`) + basic per-uid rate limiting — paid-API cost-abuse surface | fix + tests |
| P0.4 | `AuthService` tests: mode gating, sign-out state, uid propagation (protocol-mock Firebase seams; service already injectable) | tests |
| P0.5 | `VehicleService` free-tier cap + `PurchaseService.isPro` gate tests (the paywall write path — already injectable) | tests |
| P0.6 | `SyncService` tests: enqueue/flush/failure-retention — the "failed items never dropped" durability promise | tests |
| P0.7 | `EntryFormViewModel` save pipeline + `EntryService` write/query tests (details AnyCodable encoding, odometer pushback, `in`-clause subsetting) | tests |
| P0.8 | **`CSVExportService` fix**: RFC-4180 quoting/escaping + formula-injection sanitization (`=`,`+`,`-`,`@` prefixes) + tests proving both | fix + tests |
| P0.9 | `PDFExportService.shouldInclude` section-gating tests; temp-file cleanup fix | fix + tests |
| P0.10 | Replace fake `SecureStoreServiceTests` (`#expect(true)`) with real keychain round-trip (save/read/delete/missing-key) | tests |
| P0.11 | `AppIntegrityService` provider-selection matrix tests (debug/device/release) | tests |
| P0.12 | `AppError` remaining domain mappings + `Validators` edge cases (negative/non-numeric/regressive odometer) | tests |

## Phase P1 — Functional defects found by the audit

| # | Work item |
|---|---|
| P1.1 | **ProfileViewModel persistence bug** — profile edits are never persisted; wire to FirestoreService/UserProfile save + tests |
| P1.2 | Dead code `OilAnalysisViewModel` (unwired ClaudeService path): **tri-vote** delete-vs-wire (substantive product decision, Law 1) |
| P1.3 | Reminder nil-dueDate branch, WearService nil-valuePct drop, Dashboard load/refresh/error paths — tests |

## Phase P2 — Real E2E (XCUITest, hermetic via UI_TEST_MODE/seed data)

Wave 1 (risk-ranked): J1 real auth flow (login visible → demo sign-in → shell; sign-out),
J3 entry CRUD (add → appears in Log + Dashboard → detail; regressive odometer rejected),
J7 paywall (ProGate from all 4 features → subscription sheet; mocked isPro unlock).
Wave 2: J2 vehicle CRUD + free-cap paywall, J4 log search/filter, J5 reminders gate,
J6 export flow, J8 settings/profile persistence (locks P1.1), J9 offline sync badge,
J10 Garage Pro screens.
All hermetic: no live Firebase — launch args + seed data; every test asserts real UI elements
(accessibility identifiers added to product code where missing — additive only).

## Phase P3 — Gate & promote

Full CI gate (`verify-ios.sh`) green with the expanded suite → CloudFunctions test suite green
→ tri_review on the branch (per-area scope if evidence >200KB — lesson from routing-v3) →
operator gate → merge → push.

## Loop protocol

Terra implements in this worktree in phase-sized passes; each pass ends with
policy+lint+build+test verification (one xcodebuild at a time on this machine); failures loop
back to Terra with the log. Gemini cross-checks each pass read-only. Fable verifies
independently and owns triage of every review finding (full-brief reads — session lesson).
Fixes at the trust boundary (P0.2, P0.3, P0.8, P1.1) get an async-commit-review brief
(Law 5) in addition to unit tests.

## Explicit non-goals (this audit)

Re-platforming, new features, RevenueCat live-sandbox purchase tests (mocked at the service
seam instead), OS-level lane isolation (standing limitation), visual snapshot testing (assay
separately if wanted).

## Sol co-review disposition (v2, 2026-07-10 — all 8 blockers + improvements)

| # | Sol blocker | Disposition |
|---|---|---|
| 1 | Verify RevenueCat contract before P0.2 (HMAC assumption unverified) | **ACCEPTED — Sol was right**: characterized the code; RevenueCat's contract is a static `Authorization` header (no HMAC scheme exists). P0.2 rescoped: timing-safe compare + **stale-event ordering guard** (found live: `event_timestamp_ms` never compared to stored state — an out-of-order event overwrites newer entitlement) + strict schema validation + rename. Scheme goes to tri-vote TV-A1 |
| 2 | Firestore/Storage RULES emulator suite missing — the real authorization boundary | **ACCEPTED → NEW P0.0**: `@firebase/rules-unit-testing` emulator suite — owner/other-user/unauthed × read/write/list, privilege-field (`subscription`) client-write denial, storage path isolation. Rule *changes* (if any come out red) are PROTECTED → operator-gated |
| 3 | Law-1 votes for P0.2/P0.3/P0.8/P1.1 | **ACCEPTED**: tri-votes TV-A1 (webhook auth+ordering), TV-A2 (parseOilAnalysis abuse controls), TV-A3 (CSV neutralization semantics), TV-A4 (profile persistence schema) — run before implementation |
| 4 | Baseline unverified | **MOOT** — full suite re-ran green (TEST_EXIT=0) post-split before this disposition |
| 5 | Hermetic XCUITests overstated as trust-boundary evidence | **ACCEPTED**: renamed "UI-routing journeys"; trust-boundary evidence comes from P0.0 emulator suite + unit seams; briefs label layers honestly |
| 6 | Scope-guard preflight / protected-surface manifest | **ACCEPTED**: manifest kept in this doc (below); audit runs orchestrator-supervised (routing-v3 §4.6 precedent); protected touches listed for the operator at review |
| 7 | Rate-limit design underspecified | **ACCEPTED**: folded into TV-A2 with concrete atomic-quota options |
| 8 | Deployment ≠ merge | **ACCEPTED → NEW P4**: separately operator-gated deploy (functions + rules): `firebase deploy` steps, post-deploy probe of the RUNNING revision (landmine #9), rollback command, cost/abuse monitoring notes |

Improvements folded: characterization-before-remediation ordering; webhook test breadth (stale
/out-of-order/duplicate/unknown-user/fail-closed config); server-authoritative entitlement
invariant (client cannot write `subscription` — P0.0 rules test); SecureStore injectable seam +
unique account names; bootstrap/router state-machine tests precede broad XCUITest waves; CSV
policy consumer-aware (numeric fields exempt from prefixing — preserves negative numbers);
per-phase exit criteria (each P0 item: happy + ≥2 negative cases; E2E: 2× consecutive green
runs; zero flaky budget). Queued as separate follow-up programs (not silently dropped):
account-deletion/data-lifecycle suite, supply-chain/dependency checks, observability
acceptance criteria, Swift-6 concurrency hazard suite.

### Protected-surface manifest (preflight, Sol blocker #6)
- Expected to touch: `CloudFunctions/src/**` (allowed), `Tests/**` (allowed),
  `Garage/**` accessibility identifiers + ProfileViewModel wiring (allowed),
  `CloudFunctions/package.json` + test config (outside `src/` — flagged, low risk),
  `Garage.xcodeproj` via `xcodegen generate` (generated artifact of protected `project.yml`;
  `project.yml` itself is NOT expected to change — new test files ride existing globs).
- NOT expected: `firebase.*.rules` changes (tests only; red results → operator),
  `Configuration/Secrets.swift`, `scripts/ci/*`. Any deviation halts for operator review.
