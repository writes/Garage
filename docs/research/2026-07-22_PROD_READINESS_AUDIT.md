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

## 🚧 Remaining — OPERATOR-ONLY (cannot be done by an agent)

1. **[BLOCKER] Real Privacy Policy + Terms URLs** — `Constants.swift` ships
   `https://OPERATOR-REPLACE-*.invalid`; they render as live Links in the subscription sheet →
   guaranteed **App Store 3.1.2 rejection**. Review the drafts in `docs/legal/`, host them, set the
   constants. `release-checks.sh` enforces this.
2. **Deploy wiring** — `firebase login`, set the two secrets, deploy functions (incl. the new
   `deleteAccount`) + rules, App Check backend enforcement, real `Secrets.swift`, RevenueCat webhook
   URL+token, ASC metadata + privacy labels. Full steps: `docs/DEPLOY_RUNBOOK.md`.

## 🔨 Remaining — CODE (recommended next PRs, not done this session)

- **#4 MAJOR — Vehicle cap is client-only** (primary Pro upsell bypass). Needs a server-authoritative
  `getAfter()` counter (blueprint RULES-1 / Mechanism A′): maintain `users/{uid}.vehicleCount`,
  write it in the same batch as vehicle create, and gate the create rule on
  `count <= limitFrom(subscription)`. Client + rules + tests; deferred because a wrong rule can lock
  out legit users — deserves its own reviewed PR. (Client also hard-codes `limit(to: 5)` = #15.)
- **#8 MAJOR — Record PDF export** fetches only the 200 newest entries then date-filters client-side
  → silently drops entries for vehicles with >200 logs. Push the date range into the Firestore query
  or cursor-paginate (like CSV).
- **#9 MAJOR — `appState.vehicles/currentVehicle`** are not driven by the live snapshot listener
  (only bootstrap + post-add). Drive them from the listener stream, or refresh after entry saves.
- **#11 MINOR — Webhook perpetual-Pro** when a renewable grant/transfer omits `expiration_at_ms`
  (null-expiry=lifetime should be NON_RENEWING only). Also: REFUND/CHARGEBACK/BILLING_ISSUE/PAUSED
  events unhandled (gap).
- **#13/#14/#19/#23 — Observability**: CFs have zero server logging on money/AI paths; Crashlytics
  has no dSYM upload phase (unsymbolicated crashes) and records no non-fatals; vehicle decode
  failures are silent; Crashlytics runs without the consent gate Analytics has.
- **#12 MINOR — `ITSAppUsesNonExemptEncryption`** absent (every upload → "Missing Compliance").
  One line in `project.yml` (PROTECTED).
- **#18/#20/#22 — Perf/scale**: Stats over newest 100, Log search over newest 500 (comment claims
  full history); Dashboard re-runs 5 Firestore fetches on every tab switch; up to 500 docs decoded
  on the main actor.
- **#24/#25/#26 — Accessibility**: wear health is color-only (WCAG 1.4.1); charts have no VoiceOver
  labels; theme rows lack `.isSelected` + are sub-44pt.
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
