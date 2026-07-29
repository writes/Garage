# Enterprise optimization roadmap — 2026-07-29

> Product of a 19-agent full-project audit (7 dimensions: iOS architecture, Cloud Functions,
> tests/CI, docs freshness, security/privacy, performance, production ops) with an adversarial
> verification pass over every critical/high finding, plus an independent re-run of the security
> dimension. Every finding below carries file:line evidence that was read, not guessed; items
> marked **VERIFIED** survived a dedicated refuter pass.
>
> **Supersedes the open items of `2026-07-27_OPTIMIZATION_BACKLOG.md`** — that doc's
> "Deliberately not done" list is now largely done (receipt parsing shipped, offline writes
> local-first, strict tool use live); its still-open items are absorbed here. This doc is the
> single current backlog.

---

## §0 Operator queue (nothing below unblocks these; ordered by leverage)

1. **Lift the GitHub Actions spending cap.** CI has been fully dark since ~2026-07-29 14:43 —
   every run dies in ~10s with zero steps. Merges are landing on local verification only.
   While in billing settings: set a **spend alert well below the hard cutoff** so the next
   cutoff is a warning, not an outage.
2. **Approve the scoped prod deploy**: `firebase deploy --only functions:receiptQuickAdd
   --project prod` (the only 1 of 9 exports not live; client already merged — see §1.2).
   Verify the running revision after (landmine #9).
3. **Confirm receipt quota shape**: Pro 20 confirmed receipts **per month** (not per day —
   a 30x difference). The build (§1.1) starts on this confirmation.
4. **Add `ios` + `functions` as required status checks** (strict/branches-up-to-date) on the
   main ruleset. Closes the accepted gap left by removing the `push: main` trigger. Both jobs
   now report skipped (not missing) on filtered PRs, so required checks will not wedge.
5. **PROTECTED patch — `verify-ios.sh` must fail closed on CI** (VERIFIED high). Lines 53–57
   silently skip ALL tests when simulator detection returns empty — the exact bug class that
   once silently lost 278 tests. Patch (GitHub Actions sets `CI=true`):
   ```zsh
   if [[ -n "${SIMULATOR_NAME}" ]]; then
     xcodebuild -project Garage.xcodeproj -scheme Garage -destination "platform=iOS Simulator,name=${SIMULATOR_NAME}" test
   elif [[ "${CI:-}" == "true" ]]; then
     echo "ERROR: no available iOS simulator on a CI runner — tests would be silently skipped."
     exit 1
   else
     echo "No available iOS simulator found; skipping simulator tests (local run)"
   fi
   ```
   While editing the same PROTECTED file, add the already-queued wedge-guard to line 54:
   `-test-timeouts-enabled YES -default-test-execution-time-allowance 120` (governs the XCTest
   UI-journey files; Swift Testing files need `.timeLimit` traits — see §2.4).
6. **Repo Settings, if unused (API refuses to disable them — HTTP 422, dynamic workflows):**
   *Settings → Copilot → coding agent* (ran once, 2026-07-28) and *Settings → Advanced
   Security → Dependabot* (its runs are unbilled but have wedged at exactly 24h five times
   since 07-16). As of 2026-07-29 Dependabot PRs no longer trigger the macOS gate (the
   `changes` filter skips CloudFunctions-only PRs), so keeping Dependabot security updates ON
   is now cheap and is the recommended posture.
7. **RevenueCat secret key** — unblocks subscriber erasure in `deleteAccount` (§1.6) and the
   TRANSFER-destination healing already scoped in the 07-22 audit.
8. **Do not press release** — app is still under the uncleared placeholder name.

---

## §1 Verified defects (fix next, in this order)

### 1.1 Build the receipt-quota refactor (designed 2026-07-29, agreed, unwritten)
Unit = confirmed, cleared receipt. Free 5 lifetime / Pro 20 per month (pending §0.3) /
+10 per $1 IAP; scan ceiling 4x confirmed allowance. Save on the prefilled entry form IS the
acceptance — no confirmation screen. Order: server counters → client Save-as-confirm →
correction instrumentation (field edited/unchanged, no values — turns every real scan into a
golden-set entry) → IAP top-ups last. Fold in two VERIFIED server findings while in there:
- **No request-level timeout on the Anthropic fetch** (`claudeProxy.ts:500-554`): a platform
  kill mid-call permanently burns a reserved quota unit. Add `AbortSignal.timeout(...)` and
  refund on abort.
- **429s never refund the reserved unit** (`receiptQuickAdd.ts:553-561`, test-pinned): refund
  is `>=500`-only, but Anthropic doesn't bill a 429 either. Refund both; if abuse is the
  worry, cap per-uid refunds instead.

### 1.2 Ship-consistency: receiptQuickAdd server (operator §0.2)
Client merged to main; server code-complete (98.1% field-level eval) but not deployed. Until
deployed, the shipped client's scan path dead-ends. This is the single largest
feature-completeness gap.

### 1.3 Cloud Functions monitoring + alerting (VERIFIED — zero exists)
40 structured `logger.error/warn` sites, and nothing reads them. Minimum viable: Cloud
Monitoring log-based metric + alert policy on `severity=ERROR`, email/Slack channel. Next
rung: a scheduled synthetic heartbeat calling each callable with a known-good payload.
Nothing tells us today that receiptQuickAdd is failing in prod except a user complaint.

### 1.4 Rollback runbook (VERIFIED — zero hits for "rollback" across all ops docs)
Add to `DEPLOY_RUNBOOK.md`: functions rollback (`git checkout <prev-sha> -- CloudFunctions &&
firebase deploy --only functions:<name>`), a server-side kill switch the client checks before
AI calls, and the app-side story (expedited review / phased-release halt).

### 1.5 lookupRecalls has no quota or rate limit (`nhtsaRecalls.ts:134-139`)
The only cost-bearing callable without a per-uid bucket (deliberately not Pro-gated — safety —
but ungated ≠ unmetered). Reuse the `usage_quotas` pattern + short-TTL VIN cache.

### 1.6 Account deletion leaves the RevenueCat subscriber record (`deleteAccount.ts:18`)
Only the Firestore mirror is deleted; email + purchase history persist at a third party after
the user deletes their account. Add the RevenueCat erasure REST call to the cascade. Blocked
on §0.7.

### 1.7 Test-suite hardening (all VERIFIED)
- Suite-default time limits: 2 of ~17 async-timing test files got `.timeLimit` reactively
  after the 2h14m runner hang; the other 15 are exposed. Swift Testing default trait +
  the XCTest flag in §0.5.
- `AuthViewModel` (nonce, timeout race, sign-in funnel classification) has **zero** tests —
  mirror the `ActivationFunnelAnalyticsTests` fake-injection pattern.
- `policy-checks.sh` force-unwrap regex only matches `\w+!\.` — bare `!`, `as!`, `try!` pass;
  2 live bare force-unwraps exist today (`SubscriptionReconciliationStoreTests.swift:10,42`).
  SwiftLint already subsumes this check correctly → delete the redundant weaker gate
  (PROTECTED file, bundle with §0.5) or fix the regex.

---

## §2 Performance (verified, ranked by measured read/render cost)

1. **Vehicles collection read 3x per cold launch/account switch**
   (`VehicleSwitcher.swift:84-137`): two duplicate live listeners + one one-time fetch.
   Collapse to one listener. (Verify pass downgraded severity — correctness is fine, cost is
   real.)
2. **Log tab fetches 500 entries per page** (`LogViewModel.swift:53-101`), refetched on every
   revision bump and again on Load More. Page size ~50 with progressive Load More; keep the
   tolerant-decode cursor semantics.
3. **Non-lazy TabView** fires Dashboard + Log + Stats fetches concurrently at launch
   (`ContentView.swift:26-50`). Defer each tab's initial fetch to first selection.
4. **Attachment thumbnails decode the full 2048px source for a 44pt row**
   (`AttachmentDetailRow.swift:82-97`). Serve downsampled thumbnails
   (`CGImageSourceCreateThumbnailAtIndex`).
5. **Image downsampling runs on the main actor** (`AttachmentPicker.swift:112-122`) while the
   PDF path in the same file is already detached. Move to `Task.detached` for consistency.

---

## §3 Code-hygiene quick wins (one small PR)

Dead code, all zero-caller-verified: `TireSet` model + its orphaned path constant,
`CardView` (superseded by its own `.garageCard()` modifier), `SkeletonLoader` +
`ShimmerModifier` (built for the loading-state bug class fixed twice, never wired — either
adopt in Dashboard/Stats or delete), `SecureStoreService` (placeholder
`com.yourcompany` Keychain identifier; if kept, use `WhenUnlockedThisDeviceOnly`).
Plus: `resolvedDate(default:)` byte-duplicated across `VoiceQuickAddService.swift:96` /
`ReceiptQuickAddService.swift:126` — extract one shared implementation; align
`MAX_PDF_BASE64_BYTES` (10 MiB, zero headroom) with receiptQuickAdd's 9 MiB envelope
headroom; pick one ViewModel file-placement convention (flat for single-VM features).

---

## §4 Enterprise maturity ladder (build later, in rough order of value)

**Reliability/ops**
- Synthetic heartbeat per callable + alert (extends §1.3).
- Staged/canary rollout for functions + TestFlight groups (large).
- Git-tag every shipped build (`build-N`) from `testflight_build.sh` — today "what code is in
  build N" is only answerable from HANDOFF prose; repo has exactly one tag.
- Extend `CrashReporter.record` beyond the 4 decode-failure sites to write-failure catches,
  so Crashlytics velocity alerts reflect real failure rates once alerting exists.
- Move `ScreenshotCaptureTests` (15s of fixed sleeps) out of the gated scheme into the
  release pipeline.

**AI cost/quality**
- Anthropic prompt caching for static system prompt + few-shot blocks (voice prompt alone is
  large; caching is a pure win at current call volume).
- Retry-with-backoff on transient 5xx before surfacing failure.
- `maxInstances`/concurrency caps on client-callable AI functions (blast-radius bound).
- Content-hash short-circuit for identical re-uploaded images (~1h TTL) + duplicate-receipt
  detection on vendor+date+total (both already agreed in the quota design).
- Skewed-photo odometer loss reproduces 2/2 in the golden eval — a prompt/preflight fix, and
  likely the top real-world failure mode.

**CI/tests**
- Code-coverage collection + a modest threshold gate.
- Snapshot/visual regression tests for SwiftUI views (contrast bugs were invisible to every
  existing gate until `ColorContrastTests`).
- Deterministic-clock test doubles as the standard for timing-sensitive tests.
- Periphery (or scripted) dead-code sweep — this audit's grep sweep found 4 dead files that
  survived every review pass.
- CI check that fails if `Configuration/Secrets.swift`, `GoogleService-Info.plist`, or
  `CloudFunctions/.env*` is ever staged (turns gitignore hygiene into a guarantee).
- Privacy-manifest lint: grep required-reason API usage vs `PrivacyInfo.xcprivacy`
  declarations so an SDK bump can't silently drift out of compliance.
- `dependabot.yml` with grouped monthly npm updates — now that CloudFunctions-only PRs skip
  the macOS gate, keeping deps fresh costs ~2 ubuntu minutes per month.

**Product**
- Guided onboarding + permission priming — still a product bet; decide from `form_opened` →
  complete numbers, which are now instrumented.
- GDPR/CCPA full-data-export endpoint (JSON dump of every user-owned collection), distinct
  from the curated resale exports.
- Mileage-based reminder date prediction from logged history (the honesty disclosure shipped;
  the prediction didn't).
- Trial length 7→14 A/B (ASC-config, no code) and onboarding-paywall placement — both still
  ⏸ pending onboarding data.
- Subscription-domain sequence diagram (15 files, 2,376 lines of distributed state machine;
  discoverable from no single file).
- CHANGELOG.md keyed to build tags once tagging exists.

---

## §5 Audited clean — do not re-open without new evidence

- **Security/privacy posture** (re-verified 2026-07-29 by a dedicated sweep): Firestore rules
  default-deny with owner-uid checks and the getAfter vehicle-cap counter; Storage scoped to
  `users/{uid}` with content-type/size limits; App Check enforced on all 6 callables (debug
  provider correctly gated); RevenueCat webhook uses a timing-safe shared-secret, fail-closed;
  `PrivacyInfo.xcprivacy` matches actual required-reason API usage; analytics consent gate
  holds/discards correctly and the event enum structurally forbids free-form PII; no committed
  secrets; functions never log user content. Nothing above low severity.
- **Crash-hardening, Dynamic Type, accessibility labels** — audited clean 2026-07-27, still
  clean; the 300-line cap + zero force-unwrap/`try!` policy holds in app code (the 2 bare `!`
  in §1.7 are test files).
- **iOS architecture** — 100% @Observable, @MainActor-consistent singletons, careful listener
  lifecycle. The audit's verdict: "reads as a codebase that has been through repeated
  adversarial review." Findings were all low-severity hygiene (§3).
