# Receipt-credit IAP top-ups — implementation spec (2026-07-30, rev 3)

> Extends `2026-07-30_RECEIPT_QUOTA_REFACTOR_SPEC.md` (shipped; reservation model live).
> Product: `com.writes.harrysplayhouse.credits.receipts10` ($0.99, +10 credits), created by
> `scripts/release/create_receipt_credits_iap.py` (operator).
> Tri-votes (DECISION_LEDGER 2026-07-30): Q1 scan-coupling **A unanimous**; Q2 clawback
> **A unanimous**; Q3 audience **C majority** (details rev 1 header, unchanged).
> Review chain: rev 1 NO-GO ×3 (Sol 15 / Gemini 6 / Grok 19 findings); rev 2 NO-GO ×3 —
> all rev-1 remediations held EXCEPT the reviewers converged on: (a) the two-state txn
> ledger was not order-independent, (b) the txn poll could not address the ledger, (c) the
> hardcoded PRODUCTION filter contradicted the sandbox launch gate; plus Sol-r2 #2/#4–#14
> and Grok-r2 #4–#7 detail findings. Rev 3 incorporates all of them. Reviews in session
> scratchpad `{sol,gemini,grok}-iap-review*.txt`.

## Model (unchanged from rev 2)

| | grant | scan pool | period |
|---|---|---|---|
| Credits | +10 confirmed per $0.99 pack | +40 (4x ratio) | lifetime, never expires |

Aggregates on `usage_quotas/${uid}_receipt_credits`: `{uid, kind, granted, clawed, count,
reserved, updatedAt}`; scan pool on `usage_quotas/${uid}_receipt_credit_scans`
(`{uid, kind, count, updatedAt}`, base scan-count semantics).

- `eff = max(0, granted − clawed)` gates NEW admissions and confirms.
- **Credit scan ceiling = `4 × granted`** (monotonic — refund→rebuy always adds real scan
  capacity). Honest residual bound: a refunded pack whose scans were fully dumped costs
  ≤ 40 × per-scan API cost (~$0.20 at the current DERIVED ~$0.005/scan estimate) — the
  dump path, not just in-flight TTL. Accepted and documented.
- Balance `= max(0, eff − count − reserved)`; deficit `= max(0, count + reserved − eff)`.
- Confirm-time integrity: credit-funded confirm re-checks `count < eff` in-transaction;
  failure releases the reservation, voids the token, errors `failed-precondition
  {reason: "receipt_credits_revoked"}` — **returned from the transaction as a result kind
  and thrown only AFTER commit** (throwing inside the callback would roll the release
  back; matches the live admission/confirm pattern). Token records
  `releaseReason: "revoked"`, and every retry replays the SAME stable error (see 14).

## Purchase transaction ledger — order-independent fact fold

`receipt_credit_txns/{docId}`, docId = **sha256 hex of
`${appId}|${store}|${environment}|${transactionId}`** (collision-resistant; no
sanitization aliasing). Raw `appId`, `store`, `environment`, `transactionId` retained as
fields (lookup + invariant checks). Server-only; explicit rules deny pin; purged in
deleteAccount by `uid ==` batched query.

Fields: `uid` (beneficiary — pinned from the FIRST event that creates the doc; every
fold for this txn targets that uid forever), `productId`, `packDelta` (0 until the
purchase fact arrives; then `10 × clamp(quantity ?? 1, 1, 10)`), fact timestamps
`purchaseAtMillis?`, `refundAtMillis?`, `reversalAtMillis?` (from `event_timestamp_ms`;
refund/reversal keep the MAX seen — supports refund→reverse→refund cycles), applied
markers `grantApplied`, `clawApplied`, `eventIds[]` (cap 20), `createdAtMillis`,
`updatedAtMillis`.

**Fold algorithm** — run inside every credits-event transaction after recording the
event's fact; deterministic in the FACTS (event timestamps), independent of arrival
order:

```
refundEffective = refundAtMillis != null
               && (reversalAtMillis == null || reversalAtMillis < refundAtMillis)
if purchase fact present && !grantApplied:
    credits.granted += packDelta            // once, monotonic — scan ceiling intact
    grantApplied = true
targetClaw = grantApplied && refundEffective
if targetClaw && !clawApplied:  credits.clawed += packDelta;              clawApplied = true
if !targetClaw && clawApplied:  credits.clawed  = max(0, clawed − packDelta); clawApplied = false
```

Event → fact mapping (credits product only): `NON_RENEWING_PURCHASE` → purchase fact
(+packDelta, min timestamp wins if duplicated); `CANCELLATION` (ANY cancel_reason — a
consumable cancellation is always a refund) → refund fact; `REFUND_REVERSED` → reversal
fact; any other type → event recorded on `revenuecat_events`, `logger.error`, NO fact.
This resolves every rev-2 hole: refund-before-purchase nets zero but leaves the ledger
whole (late purchase applies grant AND claw together), a later reversal restores +10;
purchase→reversal→late-cancellation compares TIMESTAMPS so the stale refund never claws.
**Tests: all 6 arrival permutations of {purchase, cancellation, reversal} + duplicates
+ refund→reverse→refund, asserting final aggregates per the fold.**

## revenueCatWebhook.ts

1. Parser: standard events normalize `entitlement_ids: null`/missing → `[]` (exact-shape
   `null` tests). Parse optional `product_id`, `transaction_id`, `environment`, `store`,
   `app_id`, `quantity`. Subscription payload regression suite passes byte-identical.
2. **Source filter — config-driven, fail-closed** (env/params, not hardcoded):
   `RC_EXPECTED_APP_ID`, `RC_EXPECTED_STORE` (=`APP_STORE`), `RC_EXPECTED_ENVIRONMENT`
   (`PRODUCTION` in the prod project; `SANDBOX` in the staging project — the sandbox
   launch gate runs against staging with its own RC webhook). Credits events where any
   of the three mismatches OR `app_id`/`transaction_id` is missing/empty (RC documents
   both as present — missing = malformed, fail closed): 200-acknowledged, recorded,
   `logger.warn` for environment mismatch / `logger.error` otherwise, ZERO ledger
   mutation. All rejection cases pinned.
3. **Credits branch = separate handler + transaction** (never threaded through the
   subscription branch). Reads, ALL before any write: `revenuecat_events/{event.id}`
   (duplicate → no-op), `deleted_users/{uid}` tombstone (see 12 — present → record event
   inert, no ledger/quota writes), `receipt_credit_txns/{docId}`, beneficiary's
   `${uid}_receipt_credits`. Then fact update + fold + event record. Emulator test: two
   CONCURRENT identical deliveries → exactly one grant.
4. Never a subscription write from the credits branch, even with
   `entitlement_ids ∋ "pro"` (grant credits, skip entitlement, `logger.error`; pinned).
5. Lifetime-grant hardening: `lifetimeGrantEventTypes` → explicit EMPTY allowlist (no
   lifetime SKU exists); `NON_RENEWING_PURCHASE` + pro + no expiry now
   `skipped_no_expiration` + error log. Deliberate behavior change, pinned.
6. `revenuecat_events` records gain `productId`, `transactionId`, `environment`,
   `store`, `packDelta` when present (no PII).
7. `granted`/`clawed`/`packDelta`/fact-timestamps all through `safeQuotaCount`-class
   numeric hardening.
8. TRANSFER: no credits movement; txn-pinned beneficiary keeps refund/reversal
   attribution stable across alias churn. Support-docs note: account merge ≠ credits.

## receiptQuota.ts

9. **Sweep**: `expirySweepWrites` returns post-release `statesByBucket` for EVERY
   bucket; **`${uid}_receipt_credits` is ALWAYS force-included in the sweep read set**
   (even with zero expired tokens) so admission/status read credit state exclusively
   from the post-release map (Grok-r2-4; Sol-r1-8 pin: expired credit token + fallback
   admission in one transaction ends `reserved == 1`). When the expired-token query
   returns a full `limit(10)` page, the transaction result carries
   `sweepIncomplete: true` → status echoes it and the client immediately re-fetches
   (cap 5 rounds) so a paid account with >10 expired reservations converges instead of
   staying latched (Sol-r2-10). Regression: 12 expired credit tokens → two status
   calls fully reconcile.
10. **Admission fallback** (reads add: credits + credit-scans + tombstone-free... no —
    admission needs no tombstone; reads add the two credit docs only, all before
    writes): base route exactly as today; else credits route iff
    `creditScans.count < 4·granted` AND `credits.count + credits.reserved < eff` (both
    post-sweep). Credit admit: `creditScans.count+1`, `credits.reserved+1`, token
    `{confirmedBucketId: ${uid}_receipt_credits, resetAtMillis: null}`, reservation
    `scanBucketId = ${uid}_receipt_credit_scans`. Deny only when both routes deny;
    error payload byte-identical to today (BASE reason/scope/resetAt).
11. **Composite snapshot, always**: legacy five fields = CURRENT-entitlement BASE
    buckets in every response. Additive: `creditsRemaining`, `creditsScanRemaining`
    (`max(0, 4·granted − creditScans.count)`), `creditsGranted` (monotonic),
    `creditsDeficit`. `creditsPurchasingEnabled` and `transactionState` are
    **status-only** fields (documented; admission/confirm responses omit them — the
    offer decision always reads status). `receiptQuotaConfigurationForToken`: credits
    branch FIRST (exact match, either entitlement), carries bucket ids/kinds only —
    allowance never read from configuration.

## confirmReceiptScan.ts

12. Restructured, reads before writes: token → route → `users/{uid}` + base buckets +
    both credit docs. Consumed/idempotent handling as today except: token
    `releaseReason` (`"expired" | "refund" | "revoked"`; absent → legacy expired)
    replays a stable reason-specific error on retry — first `receipt_credits_revoked`
    and every retry after it identical (Sol-r2-11). Credit tokens: `count >= eff` →
    release + void (`releaseReason: "revoked"`) via result-kind, throw post-commit.
    Refund paths that void tokens write `releaseReason: "refund"`; the expiry sweep
    writes `"expired"`. Snapshots composed per 11.

## receiptQuotaStatus.ts

13. One transaction, explicit read order (all reads → all writes): `users/{uid}` →
    base buckets → credits + credit-scans docs → `app_config/receipt_credits` →
    optional txn doc (docId computed from the SERVER's expected
    `{appId, store, environment}` config + caller-supplied `transactionId` — the
    client never supplies the tuple) → expiry query → referenced expired-token
    buckets → sweep writes → composite snapshot. `transactionState` returned only
    when the txn's `uid` == caller: `"granted"` (grantApplied && !refundEffective),
    `"refunded"` (refundEffective), else/foreign/absent `"unknown"`.
    `creditsPurchasingEnabled` echoes `app_config/receipt_credits
    {purchasingEnabled: bool, expiresAtMillis: number}`: true iff enabled AND
    unexpired (operator renews; expiry fails closed on neglect — reduced-scope
    version of Sol-r2-9's readiness lease, with reconciliation as the safety net).

## reconcileReceiptCreditPurchase.ts (NEW export — Sol-r2-2: repair is in scope)

14. `onCall({enforceAppCheck, timeoutSeconds: 30})`, auth required. Input
    `{transactionId}` (validated shape first). Requires `REVENUECAT_SECRET_API_KEY`;
    unset → `unavailable` (fail-soft precedent: RC subscriber erasure). Flow: GET RC
    REST `subscribers/{uid}` (15s AbortSignal) → `non_subscriptions[productId]` →
    find the transaction; found → fold the purchase fact into the ledger through the
    SAME transaction machinery (idempotent — a webhook that later arrives is a
    no-op), recording `eventIds += ["reconcile:" + txnId]`. Not found → `not-found`
    (client shows grant_missing). Per-uid rate limit 10/day via `usage_quotas`
    bucket. Operator queue item (d) — creating the RC secret key — becomes a
    launch-gate prerequisite for flipping the capability flag.

## deleteAccount.ts

15. **Tombstone first** (Sol-r2-7): write `deleted_users/{uid}
    {deletedAtMillis}` as the new FIRST cascade step; the credits webhook and
    reconcile callable read it and go inert for deleted uids (late/queued webhooks
    cannot resurrect ledger or quota docs). Add `receipt_credit_txns` `uid ==`
    batched purge (500/batch). The two quota docs are covered by the `${uid}_`
    prefix purge; test pins all four surfaces + the deletion-races-grant case.
    (The subscription webhook's own late-event resurrection of `users/{uid}` is
    PRE-EXISTING and out of scope; documented.)

## Rules

16. No rules change (catch-alls). Rules tests add explicit client deny pins:
    `${uid}_receipt_credits`, `${uid}_receipt_credit_scans`,
    `receipt_credit_txns/*`, `app_config/*`, `deleted_users/*`.

## Server tests (delta beyond those named inline)
Webhook: `entitlement_ids: null` grant; 6-permutation fold matrix + duplicates +
refund→reverse→refund; concurrent duplicate (emulator) → one grant; source-filter
rejections (SANDBOX-in-prod, PLAY_STORE, wrong/missing app_id, missing
transaction_id); quantity clamp; credits+pro → no subscription write; lifetime
allowlist empty; tombstoned uid inert; subscription regression suite unmodified.
Quota: both-deny payload stability; stranded-reservation pin; scan-pool-on-granted
rebuy pin; refund restores credit scan + reserved; sweepIncomplete convergence.
Confirm: revoked exploit pin (buy→reserve→refund→confirm); revoked-retry stable
error; composite legacy fields = base while debiting credits. Status: read-order,
txn-state own/foreign/absent/refunded, capability expiry. Reconcile: no-key
unavailable; found→grant idempotent with webhook; not-found; rate limit.
deleteAccount: four-surface purge + tombstone + race.

## Client (`Garage/`)

Offerings pipeline untouched (structurally excludes consumables — three gates);
parallel path with the same identity discipline:

17. **Identity-gated purchaser** through the serialized `SubscriptionGateway`
    machinery: requires a current `IdentityLease`; verifies
    `Purchases.shared.appUserID == Firebase uid` (non-anonymous) immediately before
    AND after purchase. SDK 5.67.2: `await Purchases.shared.products([id])`,
    `purchase(product:)`; typed outcome `{completed(transactionId:), cancelled,
    pending, failed(reason)}` — `userCancelled`/Ask-to-Buy-`pending` never succeed,
    never poll. `StoreTransaction.transactionIdentifier` persisted per-uid until a
    TERMINAL observed state: `"granted"` (clear marker, refresh, celebrate) or
    `"refunded"` (clear marker, stop polling, refund-specific message — Sol-r2-12).
18. Offer visibility: `creditsPurchasingEnabled == true` AND product fetch succeeded
    AND (pro: directly on `pro_month` denial · free: on `free_lifetime` denial only
    after ≥1 `paywallDidDismiss(source: .receiptScan)` — Q3-C; funnel gating only).
    Old servers → fields nil → flag false → never shown.
19. Deficit disclosure: `creditsDeficit > 0` → explicit pre-purchase copy ("A
    previous refund left N credits owed; this pack restores those first."). No
    silent absorption; purchase stays available.
20. **Post-purchase poll — exact schedule** (Sol-r2-14): delays 2, 4, 8, 16, 30s
    (≈60s cumulative, matching RC's documented 5–60s delivery) against
    `receiptQuotaStatus{transactionId}`. On `"granted"` → refresh snapshot, clear
    the quota-denial latch: recompute per-route usability, restore `.ready` iff any
    route admissible (retained pages kept). On timeout → analytics
    `receipt_credits_grant_delayed`, then call `reconcileReceiptCreditPurchase`;
    reconcile not-found → `receipt_credits_grant_missing` + "Purchase received —
    credits will appear shortly" + persisted-txn resume on next sheet open (which
    re-polls then re-reconciles). Manual refresh runs the same transition.
21. Footer per-route: usable = `min(confirmedRemaining, scanRemaining) +
    min(creditsRemaining, creditsScanRemaining)`; exhausted iff both terms 0 (nil →
    0). `sweepIncomplete` → immediate refetch (cap 5).
22. Constants `receiptCreditsPackIdentifier`; `AnalyticsProductID.receiptCredits10`
    (PlanIdentifierTests). Inert fake purchaser for demo/UI-test (lazy handles only).
23. Analytics (4-step; contract doc same PR): `receipt_credits_offer_shown{scope}`,
    `_purchase_started`, `_purchase_succeeded`, `_purchase_failed{reason}`,
    `_purchase_pending`, `_grant_confirmed`, `_grant_delayed`, `_grant_missing`,
    `_refund_observed`. The ops alert query is succeeded-without-grant_confirmed
    (noting analytics are consent-gated — the alert is a signal, the reconcile path
    is the repair).

### Client tests
Identity-mismatch refusal (before+after); cancelled/pending/failed never poll; txn
persistence, terminal granted AND refunded handling, resume+reconcile path; offer
matrix (flag off/expired, nil fields, pro direct, free pre/post-dismissal, fetch
failed); grant→latch clear→`.ready` with retained pages; poll schedule (fake
clock); deficit copy; per-route footer matrix; sweepIncomplete refetch cap;
analytics pins. UI journey: demo-mode sheet with inert purchaser.

## Operator gates (launch checklist)
1. ASC: product submitted with a version; review screenshot.
2. RevenueCat: product added WITHOUT entitlement attachment; **In-App Purchase Key
   uploaded + App Store Platform Server Notifications → RevenueCat** (consumable
   refund detection requires both); **"track new purchases from server-to-server
   notifications" OFF** (Sol-r2-8: non-UUID app user ids can grant to an anonymous
   alias); prod webhook production-events-only; staging project webhook for SANDBOX.
3. Staging/sandbox evidence: purchase → grant with **SDK transactionIdentifier ==
   webhook transaction_id** asserted, `receiptQuotaStatus{transactionId}` =
   `granted` for the buyer and `unknown` for another uid; refund → clawback
   observed. Record alongside revisions.
4. Provision `REVENUECAT_SECRET_API_KEY` (queue item (d)) — reconcile prerequisite.
5. Deploy all changed functions together; verify running revisions (landmine #9).
6. Only then set `app_config/receipt_credits {purchasingEnabled: true,
   expiresAtMillis: now+30d}`; renew on cadence; flip false before any webhook
   rollback.
7. Ship server before any TestFlight build carrying the client UI.

## Deferred (explicit)
Additional pack sizes; credits transfer on RC TRANSFER (support-doc note);
scheduled/automatic background reconciliation sweep (manual + client-triggered
reconcile IS in scope); subscription-path deletion tombstone (pre-existing);
Firestore TTL on receipt_scan_tokens (queued); clawback-time voiding of in-flight
credit tokens (residual documented in Model).

## Order & gates
1. Server → `npm test` + `npm run test:rules` green locally (counts reported).
2. Client → full `verify-ios.sh` green.
3. Panel re-review of THIS rev (Sol required; Gemini/Grok cross-checks) before
   implementation. Terra implements; Gemini read-only cross-check; orchestrator
   runs all gates and diffs `Tests/` separately.
4. Operator checklist; ANALYTICS_CONTRACT.md + HANDOFF in the same PR.
