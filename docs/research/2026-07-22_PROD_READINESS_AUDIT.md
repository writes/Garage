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

## ✅ 4th pass (2026-07-23 — perf cluster + verified external-audit fixes)

- **#18/#18b/#20/#22 perf/scale** — mutation-driven `VehicleDataRevisionStore` gates
  Dashboard/Stats/Log reloads (zero fetches on tab flip-flops; live-runtime only);
  Stats/Log honesty captions; Log cursor Load More + limit+1 sentinel; 500-doc decode
  yields every 50. Adversarial review: 4 confirmed findings fixed (incl. compensating
  revision bump on late backend rejection of the fire-and-forget entry batch).
- **External Codex audit (2026-07-23) verified-engineering fixes** — vehicles composite
  index DECLARED (was a production app-breaker: userId+displayOrder query undeclared);
  voiceQuickAdd failure refund (claudeProxy policy, CF 75/75); CI toolchain pinned
  (XcodeGen 2.45.3 / SwiftLint 0.63.2 — brew-floating was the audit's "nondeterminism");
  MPG computed on fuel save (chart was reading a never-written field); offerings
  auto-load; real StoreKit manageSubscriptionsSheet for active Pro.
- **External-audit items NOT acted on (operator decisions per the audit itself):** device
  scope (iPhone-only vs universal), truthful-v1 contract (attachments/dossier/edit-delete
  scope), naming clearance + icon, packaging/pricing, signing/ASC/legal/ops. Product-shape
  builds (zero-vehicle activation, entry edit/correction, attachments upload, PDF share)
  await the v1-contract call.

## ✅ 5th pass (2026-07-23 evening — conservative product-completion, external-audit closure sprint)

- **Zero-vehicle activation** — router-level gate (entryPicker/voice/entryForm → vehicleForm)
  with a load-completed tri-state (cold launch never misroutes), Dashboard "Add Your First
  Vehicle" CTA, reminder-config empty state, scaffold "Select a vehicle first" banner. The
  first-use dead-end is closed.
- **Entry DELETE** (correction path) — EntryService.deleteEntry across modes, revision-bumped,
  vehicle.currentOdometer reconciled when the backing entry is deleted; detail + swipe delete
  with confirmation. **Edit-in-place was built and CUT by review** (3 BLOCKERs: silent
  details-map wipe, odometer block/corruption, createdAt reset) — deferred until per-form
  details seeding exists; delete + re-add is the v1 correction path.
- **PDF share** — session-disciplined temp artifact + ShareLink (CSV-parallel); "unavailable
  in this beta" copy gone. The paid output is now save/shareable.
- **Reminders lifecycle** — completedAt, delete/markCompleted, list with swipe actions;
  upcoming excludes completed.
- **AttachmentPicker** — confirmed UNWIRED dead code (zero call sites); warning comment added
  so nobody ships filename-only "attachments". *(Superseded in the 8th pass: rebuilt as the
  real pipeline below.)*

## ✅ 6th–7th pass (2026-07-23/24 — edit-in-place rebuilt, a11y sweep)

- **Entry EDIT-IN-PLACE rebuilt correctly** per the review that cut it: per-form details
  seeding across all 12 forms (decodedDetails + scaffold onEditEntry), edit-aware odometer
  (floor excludes the edited entry; vehicle odometer = fresh-max re-fetch at save, closing the
  ghost-value race; delete reconcile relaxed to >=), createdAt preserved, cross-vehicle
  reparenting blocked, fuel MPG previous-lookup date-bounded. Second adversarial round: 4
  confirmed findings fixed, 1 refuted.
- **Bounded a11y sweep** (20 files, modifiers only): combined VoiceOver rows, 44pt targets,
  identifiers on new surfaces, switcher announces vehicle NAME not UUID.

## ✅ 8th pass (2026-07-24 — real attachments pipeline + CF hardening; gate GREEN @ cc94164)

- **Attachments SHIPPED end-to-end (Pro)** — EntryAttachmentService (live/hermetic/demo),
  rewritten AttachmentPicker wired into the scaffold (Pro-gated, hidden in demo/UI-test),
  pending-queue upload-BEFORE-entry-write (failed uploads clean up their own batch),
  EntryDetailView rendering, service-layer delete cascade, 20MB PDF cap with pre-read size
  check, image downsample to 2048px/JPEG 0.8 with **pixel-scale normalization** (3x-retina
  captures no longer upload 9x bytes — unit-pinned, incl. a scale-1 fixture fix and a
  Release-only `#if DEBUG` use-site fix that the archive phase caught).
- **CF `recomputeVehicleOdometer`** — onDocumentWritten trigger, authoritative odometer
  self-heal (update() never resurrects a deleted vehicle; gRPC NOT_FOUND handled). The former
  "deploy-phase backlog" item is now BUILT; deploy still operator-gated.
- **CF `deleteVehicle` storage purge** — vehicle-scoped `users/{uid}/entry-attachments/
  {vehicleId}/` prefix delete, fail-soft with structured logging (Firestore purge stays
  hard-fail); claim-first ordering unchanged.
- **CF `enforceAttachmentProGate`** — onObjectFinalized reaper deletes non-Pro uploads
  (Storage rules can't read Firestore; the client gate alone is cosmetic). CF suite 102/102.

## ✅ 9th pass (2026-07-24 — reminders fire, PDF preview, review hardening)

- **Reminders DELIVER now (local notifications)** — UNUserNotificationCenter behind a fakeable
  `NotificationScheduling` protocol; schedule/replace/cancel wired into every ReminderService
  mutation; lazy auth prompt (non-blocking save); date field added to reminder config (default
  tomorrow 09:00, past days unpickable, canonical-instant normalization). Adversarial review
  caught + fixed: silent past-due default (BLOCKER), stale notifications after vehicle/account
  deletion (cancelAll on sign-out + pre-tombstone per-vehicle cancel seam), repeat reminders
  never rescheduling (successor minted on markCompleted), permission dialog blocking save,
  cross-vehicle hint leaks. Push/APNs remains operator-gated; local-only is the v1 lane.
- **PDF attachments open in QuickLook** — downloadData on EntryAttachmentService (25MB cap =
  storage-rules ceiling), single-owner preview state in EntryDetailView. Review caught + fixed:
  concurrent-tap temp-file race (BLOCKER), late-download sheet reopen, temp-file residue across
  process death/sign-out (removeAll at launch + sign-out).
- **Verified-null sweeps:** perf items #18/#20/#22 confirmed ALREADY SHIPPED (pass-4 commit
  `3d99bfb` — revision-gated refetch, honest cap footers + Load More, chunked decode); the 3
  open Dependabot alerts (all medium, npm transitive) are upstream-blocked (MCP SDK, pubsub,
  google-gax chains; two of three under devDep firebase-tools) — no non-major fix exists;
  `overrides` forcing is a documented-but-unapplied operator option.

## 🔨 Remaining — CODE (recommended next PRs)

- **PDF export scale** (from the pass-3 adversarial review): export accumulates the full
  date-window history in memory and renders synchronously on the MainActor — fine at current
  scale, needs chunked/off-main rendering for multi-thousand-entry vehicles.
  (~~#18/#20/#22 Dashboard/Stats/Log perf~~ — confirmed shipped in pass 4, see 9th pass.)
- **TRANSFER destination healing** (pass-3 review, operator-keyed): a transfer destination grant
  is fail-closed skipped when no expiration is available (correct vs perpetual Pro), and the skip
  is now retryable + alerted — but the durable heal is a RevenueCat REST lookup
  (`GET /v1/subscribers`) with the secret key, same key as the deleteAccount subscriber-erase
  follow-up. Until wired, a transferred annual subscriber regains server-side Pro only at the
  next expiry-bearing event.
- ~~#4/#15, #8, #9, #11, #12, #13/#14/#19/#23, #24, #25/#26~~ — all closed (3rd pass above +
  earlier passes).
- **Completeness gaps** to schedule: no push-notification delivery wired (Messaging linked,
  unused) so reminders/recalls never fire; Dynamic Type unaudited; currency/rounding unaudited;
  client StoreKit purchase lifecycle (pending/deferred/cancel) unaudited; App Check **backend**
  enforcement is a console toggle to verify; QuickLook preview for PDF attachments (thumbnails
  render, PDFs list-only). ~~Firestore cascade delete~~ (deleteVehicle recursiveDelete +
  deleteAccount, 8th pass) and ~~photo downsampling unmeasured~~ (bounded + unit-pinned, 8th
  pass) are closed.
- **Deploy list (operator-gated):** 3 new/updated CFs — `recomputeVehicleOdometer`,
  `enforceAttachmentProGate`, `deleteVehicle` (storage purge) — plus rules + composite indexes
  per `DEPLOY_RUNBOOK.md` (backfill → rules → binary order).

---

## Path to prod (suggested order)
1. Operator: publish Privacy/Terms pages + set URLs; confirm/add Restore Purchases.
2. Build in-app account deletion + Firestore cascade-delete function (release blocker).
3. Server-side vehicle cap (#4) — protects the core Pro upsell.
4. Observability (Crashlytics dSYM + non-fatals + CF logging) before you have live users.
5. Export/scale + a11y polish (#8, #18, #24–26).
6. Deploy per `DEPLOY_RUNBOOK.md` (dev → verify → prod), run `release-checks.sh` + `test:rules`.
