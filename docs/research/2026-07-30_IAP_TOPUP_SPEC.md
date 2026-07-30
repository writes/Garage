# Receipt-credit IAP top-ups — implementation spec (2026-07-30, rev 2 after 3-provider NO-GO)

> Extends `2026-07-30_RECEIPT_QUOTA_REFACTOR_SPEC.md` (shipped; reservation model live).
> Product: `com.writes.harrysplayhouse.credits.receipts10` ($0.99, +10 credits), created by
> `scripts/release/create_receipt_credits_iap.py` (operator).
> Tri-votes (DECISION_LEDGER 2026-07-30): Q1 scan-coupling **A unanimous** (dedicated
> lifetime credits bucket + 4x scan pool); Q2 clawback **A unanimous** (granted/clawed
> lifetime accumulators, debt carries); Q3 audience **C majority** (both tiers; free users
> see the offer only after ≥1 Pro-paywall dismissal).
> Rev 1 was NO-GO'd independently by Sol (15 findings, 4 CRIT), Gemini (6, 2 CRIT), Grok
> (19, 2 CRIT) — reviews in session scratchpad `sol-iap-review.txt` /
> `gemini-iap-review.txt` / `grok-iap-review.txt`. Rev 2 incorporates every accepted
> finding; the headline changes vs rev 1 are: a **per-transaction purchase ledger with a
> state machine** (grant attribution is transaction-bound, not alias-bound), an
> **environment/store/app fail-closed filter**, `entitlement_ids: null` normalization,
> confirm-time `eff` re-check, scan ceiling on `granted` not `eff`, composite snapshots
> (legacy five fields ALWAYS base), sweep returning post-release states for all buckets,
> identity-lease-gated purchases, a server capability flag, and txn-state polling.

## Model

| | grant | scan pool | period |
|---|---|---|---|
| Credits | +10 confirmed per $0.99 pack | +40 (4x ratio) | lifetime, never expires |

Aggregates on `usage_quotas/${uid}_receipt_credits`: `granted`/`clawed` lifetime
accumulators (webhook-only), `count`/`reserved` with standard bucket semantics.

- **Effective allowance** `eff = max(0, granted − clawed)` — gates NEW admissions and
  confirms.
- **Credit scan ceiling = `4 × granted`** (NOT eff — Gemini CRIT-2: a monotonic scan
  counter checked against `4·eff` permanently bricks scans after refund→rebuy; `granted`
  only grows, so every purchase adds real scan capacity; refund exposure is ≤ ~$0.20 of
  API spend per refunded pack, accepted residual).
- Balance (spendable) `= max(0, eff − count − reserved)`. Deficit
  `= max(0, count + reserved − eff)` (debt after refund-of-spent-credits; Q2-A).
- Confirm-time integrity (Grok CRIT-1): a credit-funded confirm re-checks
  `count < eff` in-transaction; on failure the reservation is released, the token voided
  (`released: true`), and the call fails `failed-precondition
  {reason: "receipt_credits_revoked"}` — buy→scan→refund→confirm converts nothing.

## Purchase transaction ledger (Sol CRIT-4 — the attribution backbone)

`receipt_credit_txns/{docId}`, docId = `${store}_${environment}_${transactionId}`
(components sanitized `[A-Za-z0-9._-]`, joined with `__`; RC `transaction_id` from the
event). Fields: `{uid (beneficiary, recorded at grant), productId, packDelta,
state: "granted" | "refunded", eventIds: string[], createdAtMillis, updatedAtMillis}`.
Server-only (rules catch-all; explicit deny pin). Purged in deleteAccount by
`uid ==` query (batched, same pattern as receipt_scan_tokens).

State machine — aggregates change ONLY on state transitions, always applied to the
RECORDED beneficiary uid (never the current event's alias-selected `app_user_id`):

| event (credits product) | txn absent | state: granted | state: refunded |
|---|---|---|---|
| NON_RENEWING_PURCHASE | create granted; `granted += packDelta` on event's app_user_id (recorded as beneficiary) | no-op (dup/replay) | record eventId only (out-of-order refund already seen: net zero, no grant) |
| CANCELLATION (any cancel_reason — a consumable "cancellation" is always a refund; Gemini-6) | create refunded with `packDelta: 0` (refund-before-purchase: nothing granted, nothing clawed; late purchase then nets zero) | → refunded; `clawed += packDelta` on beneficiary | no-op |
| REFUND_REVERSED (Sol-5/Grok-8) | record eventId only | no-op | → granted; `clawed = max(0, clawed − packDelta)` on beneficiary |
| any other type | record on `revenuecat_events` only; `logger.error`; NO aggregate change (pre-registered matrix — Grok-5) | same | same |

`packDelta = 10 × clamp(quantity ?? 1, 1, 10)` (RC `quantity` if present; capped).
Missing `transaction_id` on a credits event → record event, `logger.error`, no grant
(fail closed; store purchases always carry one).

## revenueCatWebhook.ts

1. **Parser**: standard events normalize `entitlement_ids: null`/missing → `[]`
   (Sol CRIT-1 / Grok CRIT-2 — an entitlement-less consumable arrives with `null` and
   today 400s forever). Additionally parse optional `product_id`, `transaction_id`,
   `environment`, `store`, `app_id`, `quantity`. Existing rejection behavior for
   malformed core fields unchanged; regression suite must pass byte-identical for
   subscription payloads.
2. **Source filter** (Sol CRIT-2): credits processing requires
   `environment === "PRODUCTION"` AND `store === "APP_STORE"` (+ `app_id` equality when
   RC sends it). Failing events: acknowledged 200, recorded on `revenuecat_events`,
   `logger.warn` for SANDBOX (expected from TestFlight), `logger.error` otherwise,
   ZERO ledger mutation. Tests pin all rejection cases. (Operator: prod webhook should
   also be dashboard-configured production-only; the filter is defense in depth.)
3. **Credits branch is a separate handler**, not threaded through the subscription
   branch: `event.productId === RECEIPT_CREDITS_PRODUCT_ID` → `handleCreditsEvent` with
   its OWN transaction — reads first, all of: `revenuecat_events/{event.id}`,
   `receipt_credit_txns/{docId}`, beneficiary's `${uid}_receipt_credits` doc — then
   writes per the state machine (Sol-10: the existing standard-event transaction writes
   its idempotency record immediately after two reads; do not extend it). Event-id
   duplicate → no-op. Emulator test: two concurrent identical deliveries → exactly one
   grant.
4. **Never a subscription write from the credits branch**, even if the event carries
   `entitlement_ids ∋ "pro"` (dashboard misconfiguration): grant credits, skip
   entitlement processing, `logger.error`. Test pins subscription untouched.
5. **Lifetime-grant hardening** (Grok-7): `lifetimeGrantEventTypes` becomes an explicit
   empty allowlist — this app has NO lifetime SKU, so `NON_RENEWING_PURCHASE` + `pro` +
   no expiration now fails closed (`skipped_no_expiration` + error log) instead of
   minting perpetual Pro. Subscription tests updated; behavior change is deliberate and
   pinned.
6. `revenuecat_events` records gain `productId`, `transactionId`, `environment`,
   `store`, `packDelta` when present (support forensics — Grok-15; no PII).
7. `granted`/`clawed`/`packDelta` all read through `safeQuotaCount`-class hardening
   (Grok-16).
8. TRANSFER: no credits movement; the txn ledger's recorded beneficiary keeps
   refund/reversal attribution correct across alias/transfer churn (Sol CRIT-4).
   Support-docs note: account merge does not move credits.

## receiptQuota.ts

9. Bucket ids: `${uid}_receipt_credits` (confirm bucket) +
   `${uid}_receipt_credit_scans` (scan bucket, `{uid, kind, count, updatedAt}` — reuses
   base scan-count semantics so refund works unmodified).
10. **Sweep restructure** (Sol-8 / Grok-11): `expirySweepWrites` returns the
    post-release `statesByBucket` map for EVERY affected bucket, not just the current
    confirmed bucket. Admission and status pull each bucket's reconciled state from
    that map. Regression pin (Sol's exact scenario): expired credit token released in
    the same transaction as a fallback admission must end with credit `reserved == 1`,
    not 2.
11. **Admission fallback** (one transaction; reads add: credits doc, credit-scans doc —
    all before any write):
    - Base route admissible iff `scan.count < ceiling` AND
      `confirmed.count + reserved < allowance` (post-sweep states). If admissible →
      exactly today's behavior.
    - Else credits route admissible iff `creditScans.count < 4·granted` AND
      `credits.count + credits.reserved < eff` (post-sweep). Admit: `creditScans.count
      + 1`, `credits.reserved + 1`, token `confirmedBucketId = ${uid}_receipt_credits`,
      reservation `scanBucketId = ${uid}_receipt_credit_scans`, `resetAtMillis: null`,
      `entitlementUsed` = actual entitlement.
    - Deny only when both routes deny; error payload byte-identical to today (reason/
      scope/resetAt from BASE state) — old clients unaffected.
12. **Snapshot is composite, always** (Gemini CRIT-1 / Grok-3 / Sol-9): the legacy five
    fields describe the CURRENT-entitlement BASE buckets in every response (admission,
    confirm, status). Additive fields, all optional-decoded client-side:
    `creditsRemaining` (balance), `creditsScanRemaining` (`max(0, 4·granted −
    creditScans.count)`), `creditsGranted` (lifetime, monotonic — poll aid),
    `creditsDeficit`, `creditsPurchasingEnabled` (see 15). Zero-values when no credits
    docs exist.
13. `receiptQuotaConfigurationForToken`: credits branch FIRST (exact match on
    `${uid}_receipt_credits`, valid for either `entitlementUsed` — Grok-4: the existing
    free/pro branches both reject the credits id, so ordering is correctness, not
    style). The credits configuration carries bucket ids + kinds only; allowance is
    never taken from it (snapshot composition reads real docs — kills rev 1's
    static/dynamic contradiction, Gemini-4/Sol-9).

## confirmReceiptScan.ts

14. Restructured transaction, reads before writes: token doc → route via
    `receiptQuotaConfigurationForToken` → read `users/{uid}` (current entitlement for
    the composite snapshot's base fields) + current-entitlement base buckets + both
    credits docs. Then:
    - consumed/idempotent/expired handling unchanged (but snapshots composed per 12);
    - **credit tokens**: if `credits.count >= eff` → release reservation, void token,
      `failed-precondition {reason: "receipt_credits_revoked"}` (Grok CRIT-1). Current
      clients treat the unknown reason as `receipt_confirm_sync_failed` fire-and-forget
      — safe;
    - else debit the ROUTED bucket (`count+1, reserved−1`), compose the snapshot with
      legacy fields from BASE.

## receiptQuotaStatus.ts

15. Composite snapshot per 12; reads both credits docs + `app_config/receipt_credits`
    (`{purchasingEnabled: boolean}`, server-written only, absent → false) and echoes it
    as `creditsPurchasingEnabled` (Sol-11: optional-field presence is not a capability
    signal; Cloud Functions deploys are not atomic — the operator flips the flag only
    after webhook revision + product mapping + refund prerequisites are verified, and
    flips it off before any webhook rollback).
    Optional request param `{transactionId}`: when the caller's uid matches the txn's
    beneficiary, response adds `transactionState: "granted"|"refunded"`; otherwise/absent
    `"unknown"` (no foreign-txn oracle). This is the client's post-purchase poll target
    (Sol-12 / Gemini-5: balance can be legitimately absorbed by debt or concurrent
    spend; txn state is the truth).

## deleteAccount.ts

16. Add `receipt_credit_txns` `uid ==` batched purge (500/batch). The two quota docs
    are already covered by the `${uid}_` id-prefix purge; test pins all three.

## Rules

17. No rules change (catch-alls). Rules tests add explicit client-deny pins:
    `${uid}_receipt_credits`, `${uid}_receipt_credit_scans`, `receipt_credit_txns/*`,
    `app_config/*`.

## Server tests (delta)

- Webhook: `entitlement_ids: null` grant (exact shape — null, not `[]`); state-machine
  matrix incl. out-of-order refund-before-purchase nets zero; duplicate event id;
  concurrent duplicate (emulator) → one grant; REFUND_REVERSED restores exactly once;
  clawback targets recorded beneficiary, not current alias; env/store filter rejection
  cases (SANDBOX, PLAY_STORE, wrong app_id); quantity clamp; credits+pro-entitlement →
  no subscription write + error; lifetime-allowlist-empty regression (NON_RENEWING +
  pro + no expiry → skipped); missing transaction_id → no grant; subscription payload
  regression suite unmodified.
- Quota: fallback admission both denial shapes; both-deny payload byte-stable; the
  Sol-8 stranded-reservation pin; credit reservation blocks over-eff admission; scan
  pool on `granted` not `eff` (post-refund rebuy admits — Gemini CRIT-2 pin); refund
  restores credit scan count + reserved; deficit math.
- Confirm: credit-token consume; `receipt_credits_revoked` on post-clawback confirm
  (full buy→reserve→refund→confirm exploit pin); composite snapshot legacy fields =
  base while debiting credits; free→pro mid-flight unchanged.
- Status: composite fields; txn-state param (own/foreign/absent); capability echo.
- deleteAccount: three-surface purge pin.

## Client (`Garage/`)

The offerings pipeline structurally excludes consumables (three gates:
`period?.isSupportedRenewal` ×2 + closed `AnalyticsProductID`). Do NOT widen it; the
credits purchase is a parallel path with the SAME identity discipline:

18. **Identity-gated purchaser** (Sol CRIT-3 / Grok-6): route product fetch + purchase
    through the existing serialized `SubscriptionGateway` identity machinery (a new
    gateway op alongside `registerPurchase`) — requires a current `IdentityLease`,
    verifies `Purchases.shared.appUserID == Firebase uid` (non-anonymous) immediately
    before AND after the purchase call; mismatch → typed failure, analytics reason, no
    poll. SDK 5.67.2 APIs: `await Purchases.shared.products([id])` +
    `purchase(product:)` (Sol-15); typed outcome
    `{completed(transactionId:), cancelled, pending, failed(reason)}` — `userCancelled`
    and Ask-to-Buy `pending` are NEVER success and never start polling (Grok-12);
    `pending` shows the deferred-purchase message. Transaction id persisted per-uid
    (UserDefaults) until observed `granted`, so re-opening the sheet resumes the poll —
    a lost webhook stays visible instead of silently eaten (Sol-7; full REST
    auto-reconcile stays deferred, gated on REVENUECAT_SECRET_API_KEY — operator queue
    (d) — with the RC-dashboard re-send runbook as the interim heal, idempotent by txn
    ledger).
19. Offer visibility = `creditsPurchasingEnabled == true` AND product fetch succeeded
    AND (pro: directly on `pro_month` denial · free: on `free_lifetime` denial only
    after ≥1 prior `paywallDidDismiss(source: .receiptScan)` — Q3-C, persisted per-uid;
    funnel gating only, not anti-abuse — Grok-17). Old servers (fields absent → decode
    nil → flag false) never show the offer.
20. **Deficit disclosure** (Gemini-3 / Apple 3.1.1): when `creditsDeficit > 0`, the
    purchase row shows explicit pre-purchase copy ("A previous refund left N credits
    owed; this pack restores those first."). No silent absorption; purchase remains
    available (permanent lockout would strand the debt forever).
21. **Post-purchase flow**: poll `receiptQuotaStatus{transactionId}` (5 × 2s backoff)
    for `transactionState == "granted"`; then refresh the composite snapshot and
    **clear the quota-denial latch** — recompute per-route usability and restore
    `.ready` iff any route is admissible (Sol-13: today `quotaFailure` latches and
    `canSubmit` requires nil; a paid user must not stay bricked). Manual refresh runs
    the same transition. Poll timeout → "Purchase received — credits will appear
    shortly" + persisted txn resume; never blocks the sheet.
22. **Footer arithmetic per-route** (Sol-14): usable saves =
    `min(confirmedRemaining, scanRemaining) + min(creditsRemaining,
    creditsScanRemaining)`; exhaustion iff both route terms are 0 (nil credits → 0).
23. Constants: `receiptCreditsPackIdentifier`; `AnalyticsProductID.receiptCredits10`
    (PlanIdentifierTests updated). Inert fake purchaser for demo/UI-test bootstraps
    (no `Purchases.configure` there; lazy handles only — preconfigure-crash class).
24. Analytics (4-step pattern; ANALYTICS_CONTRACT.md same PR):
    `receipt_credits_offer_shown{scope}`, `receipt_credits_purchase_started`,
    `receipt_credits_purchase_succeeded`, `receipt_credits_purchase_failed{reason}`,
    `receipt_credits_purchase_pending`, `receipt_credits_grant_confirmed`,
    `receipt_credits_grant_timeout` (ops signal for lost webhooks — Grok-10/Sol-7:
    succeeded-without-grant_confirmed is the alert query). Booleans/enums only.

### Client tests
Purchaser: identity-mismatch refusal (before + after), cancelled/pending/failure
outcomes never poll, txn persistence + resume. ViewModel: offer matrix (flag off / nil
fields / pro direct / free pre- vs post-dismissal / product fetch failed), grant→latch
clear→`.ready` with retained pages, poll timeout path, deficit copy trigger, per-route
footer matrix (incl. Sol-14's mixed-pool cases). Analytics pins. UI journey: demo-mode
receipt sheet with inert purchaser.

## Operator gates (launch checklist — additions from review)
1. ASC: product submitted with a version (script exists); review screenshot.
2. RevenueCat dashboard: product added WITHOUT entitlement attachment; **In-App
   Purchase Key (ASC) uploaded** and **App Store Platform Server Notifications pointed
   at RevenueCat** — consumable REFUND detection does not work without them (Sol-6);
   prod webhook configured production-events-only.
3. End-to-end sandbox check on a sandbox/staging target: purchase → grant; refund →
   clawback event observed. Record alongside revisions.
4. Deploy all changed functions together; verify each running revision (landmine #9).
5. Only then set `app_config/receipt_credits.purchasingEnabled = true` (and flip false
   before any webhook rollback).
6. Ship server before any TestFlight build carrying the client UI (safe either way by
   19, but the offer stays hidden until the flag flips).

## Deferred (explicit)
REST auto-reconciliation (needs REVENUECAT_SECRET_API_KEY — operator (d)); additional
pack sizes; credits transfer on RC TRANSFER (support-doc note instead); Firestore TTL
on receipt_scan_tokens (already queued); clawback-time voiding of in-flight credit
tokens (Grok-14 — bounded residual: confirm-time eff check caps conversion; scan spend
until token TTL ≤ ~$0.20/pack, accepted + documented).

## Order & gates
1. Server (webhook + ledger + quota + confirm + status + deleteAccount + tests) →
   `npm test` AND `npm run test:rules` green locally, counts reported.
2. Client → full `verify-ios.sh` green.
3. Sol re-review of this rev BEFORE implementation (routing v3: NO-GO ⇒ remediate &
   rerun). Then Terra implements; Gemini read-only cross-check; orchestrator runs all
   gates and diffs `Tests/` separately.
4. Operator checklist above; ANALYTICS_CONTRACT.md + HANDOFF in the same PR.
