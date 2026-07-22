# Prod-Readiness Audit + Remediation — 2026-07-22

Source: an 8-dimension adversarially-verified audit (53 agents, prod-readiness-audit workflow) of
the Garage iOS app + Cloud Functions. **Verdict: NOT_READY** at audit time — 1 App Store BLOCKER,
11 MAJOR, 20 MINOR, +14 completeness gaps. This doc records the verdict, what was **fixed this
session** on `feature/prod-hardening`, and the **remaining path to prod**.

---

## ✅ Fixed this session (branch `feature/prod-hardening`, gated + rules-tested)

| Audit | Area | Fix |
|---|---|---|
| #2 MAJOR | Dark mode broken (white-on-white) | Lock app to light via `.preferredColorScheme(.light)` on the root (no asset dark variants exist). Verified via sim screenshot under system-dark. |
| #3 MAJOR | Vehicle update allowed `userId` reassignment (cross-account injection) | `firestore.rules`: owner is immutable on update. **Rules test added.** |
| #5 MAJOR | `lookupRecalls` missing App Check | `enforceAppCheck: true` + strict VIN validation (`normalizeVin`, 4 unit tests). |
| #6 MAJOR | `ProfileViewModel.save()` wiped fields after a failed/in-flight load | Added `guard hasSuccessfullyLoadedProfile`. |
| #7 MAJOR | SparePart/Detailing saves swallowed errors + dismissed as success | `do/catch` + `ErrorBanner` + `isSaving`, dismiss only on success. |
| #10 MAJOR | Privacy manifest missing UserDefaults required-reason | Added `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`. |
| #16 MINOR | Vehicle create allowed unauthenticated `{userId:null}` orphan | `request.auth != null && uid is string`. **Rules test added.** |
| #17 MINOR | Storage rules had no size/type limits | ≤25 MB + image/PDF content-type (delete still allowed). **Rules test added.** |
| #21 MINOR | Log list non-lazy (up to 500 rows eager) | `VStack` → `LazyVStack`. |
| — | Wear rows crowded (large mono) | caption-mono + secondary + `lineLimit(1)`. |
| — | CF deps (1 HIGH `fast-uri`) | firebase-admin 12→13.10, firebase-functions 5→6.6. |
| — DEPLOY BLOCKER | v2 functions read `process.env` secrets with no `secrets: []` → undefined in prod | `defineSecret` + bind `ANTHROPIC_API_KEY` / `REVENUECAT_WEBHOOK_AUTH`. |
| #1 (guard) | `.invalid` URLs must not ship | `scripts/ci/release-checks.sh` blocks `.invalid`/`OPERATOR-REPLACE` + missing export key. |

Verification: full `verify-ios.sh` gate + CF `tsc`/52 tests + `test:rules` 13 tests.

---

## ✅ Also fixed in the 2nd hardening pass (account/compliance)

- **[was BLOCKER] In-app account deletion** — BUILT + adversarially reviewed (verdict FIX_THEN_SHIP;
  all review fixes applied) + gated green (311u/21ui/archive). CF `deleteAccount` cascade
  (data-first/auth-last, DI-tested, idempotent on retry) + iOS Settings destructive flow with
  confirmation. Cascade covers `users/{uid}`, all `vehicles` (9 subcollections via recursiveDelete),
  `usage_quotas` (uid-prefixed), `revenuecat_events` (appUserId==uid), and Storage `users/{uid}/**`.
  Review caught + fixed a launch crash (the service was eagerly constructed at tab-build →
  Functions.functions() before Firebase config in demo). **Remaining (needs your RevenueCat secret
  key):** server-side RevenueCat `deleteSubscriber` REST call + client `Purchases.logOut()` on
  sign-out, so the RevenueCat subscriber record is also erased. Deploy the CF.
- **[was VERIFY] Restore Purchases** — ALREADY EXISTS (`SubscriptionView` "Restore Purchases" →
  `PurchaseService.restore()` → `Purchases.shared.restorePurchases()`). The audit gap was wrong.
- **#12 export compliance** — `ITSAppUsesNonExemptEncryption=false` added to `project.yml`.
- **#24 wear a11y** — non-color status + VoiceOver value on `WearItemBar`.
- **Legal drafts** — `docs/legal/{PRIVACY_POLICY,TERMS_OF_USE}_DRAFT.md` (grounded in real data
  flows) for you to review + host.

## ✅ Also fixed in the 3rd pass (follow-up PRs from the list below — 2026-07-22 evening)

- **#4 MAJOR vehicle cap server-authoritative** — RULES-1 / Mechanism A′ implemented in full:
  counted-create rules (batch-bound `vehicleCount == prior+1 ≤ tierCap` + `lastVehicleOp`
  binding; counter keys server-authoritative like `subscription`), client batch create
  (`FieldValue.increment` + binding, permission-denied mapped to `vehicleLimitReached`),
  soft-delete tombstone + new `deleteVehicle` CF (transactional decrement + recursiveDelete,
  idempotent) + swipe-to-delete UI + bootstrap purge sweep, backfill script + mandated
  rollout order (backfill → rules → binary) in `DEPLOY_RUNBOOK.md`. Rules tests 13 → 23.
  Also closes **#15** (hard-coded `limit(to: 5)` → cap+1 bound).
- **#8 MAJOR PDF export truncation** — date-bounded, cursor-paginated fetch (CSV-style);
  no more silent drop past 200 entries.
- **#9 MAJOR live vehicle listener** — `AppState.vehicles/currentVehicle` now driven by the
  existing snapshot listener (envelopes were previously discarded by the sync reducer).
- **#11 MINOR webhook gaps** — verified against RevenueCat's official docs: renewable grant
  with no expiration fails closed (perpetual-Pro leak closed); refund = `CANCELLATION` with
  `cancel_reason CUSTOMER_SUPPORT` revokes immediately; `REFUND_REVERSED` re-grants;
  `SUBSCRIPTION_EXTENDED` extends; `BILLING_ISSUE`/`SUBSCRIPTION_PAUSED` stay no-ops per
  RevenueCat guidance (grace period / revoke-on-EXPIRATION).
- **#13/#14/#19/#23 observability** — structured `firebase-functions/logger` on every
  money/AI CF path (webhook rejections+outcomes, Anthropic failure causes, per-step
  deleteAccount cascade); Crashlytics wired for the first time: consent-gated
  (`FirebaseCrashlyticsCollectionEnabled=false` + AppState lifecycle mirror of Analytics),
  Release-only fail-soft dSYM upload phase, non-fatal recording; vehicle decode is now
  per-document tolerant (one corrupt doc no longer blanks the garage) and recorded.
- **#25/#26 a11y** — VoiceOver labels/values on the MPG + cost charts; theme rows gained
  `.isSelected` + 44pt tap targets.
- **Client `Purchases.logOut()` on sign-out** — implemented as a QUEUED gateway op (serializes
  behind in-flight logIn, generation-guarded against superseding sign-ins; skipped when
  anonymous). The RevenueCat-side `deleteSubscriber` REST call still needs the secret key.

## 🚧 Remaining — OPERATOR-ONLY (cannot be done by an agent)

1. **[BLOCKER] Real Privacy Policy + Terms URLs** — `Constants.swift` ships
   `https://OPERATOR-REPLACE-*.invalid`; they render as live Links in the subscription sheet →
   guaranteed **App Store 3.1.2 rejection**. Review the drafts in `docs/legal/`, host them, set the
   constants. `release-checks.sh` enforces this.
2. **Deploy wiring** — `firebase login`, set the two secrets, deploy functions (incl. the new
   `deleteAccount`) + rules, App Check backend enforcement, real `Secrets.swift`, RevenueCat webhook
   URL+token, ASC metadata + privacy labels. Full steps: `docs/DEPLOY_RUNBOOK.md`.

## 🔨 Remaining — CODE (recommended next PRs)

- **#18/#20/#22 — Perf/scale**: Stats over newest 100, Log search over newest 500 (comment claims
  full history); Dashboard re-runs 5 Firestore fetches on every tab switch; up to 500 docs decoded
  on the main actor.
- ~~#4/#15, #8, #9, #11, #12, #13/#14/#19/#23, #24, #25/#26~~ — all closed (3rd pass above +
  earlier passes).
- **Completeness gaps** to schedule: no Firestore cascade delete; no push-notification delivery
  wired (Messaging linked, unused) so reminders/recalls never fire; Dynamic Type unaudited; photo
  downsampling/caching unmeasured; currency/rounding unaudited; client StoreKit purchase lifecycle
  (pending/deferred/cancel) unaudited; App Check **backend** enforcement is a console toggle to
  verify.

---

## Path to prod (suggested order)
1. Operator: publish Privacy/Terms pages + set URLs; confirm/add Restore Purchases.
2. Build in-app account deletion + Firestore cascade-delete function (release blocker).
3. Server-side vehicle cap (#4) — protects the core Pro upsell.
4. Observability (Crashlytics dSYM + non-fatals + CF logging) before you have live users.
5. Export/scale + a11y polish (#8, #18, #24–26).
6. Deploy per `DEPLOY_RUNBOOK.md` (dev → verify → prod), run `release-checks.sh` + `test:rules`.
