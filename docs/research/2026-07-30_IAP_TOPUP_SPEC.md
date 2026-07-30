# Receipt-credit IAP top-ups — implementation spec (2026-07-30, rev 5)

> Extends `2026-07-30_RECEIPT_QUOTA_REFACTOR_SPEC.md` (shipped; reservation model live).
> Product: `com.writes.harrysplayhouse.credits.receipts10` ($0.99, +10 credits), created by
> `scripts/release/create_receipt_credits_iap.py` (operator).
> Tri-votes (DECISION_LEDGER 2026-07-30): Q1 scan-coupling **A unanimous**; Q2 clawback
> **A unanimous**; Q3 audience **C majority** (details rev 1 header, unchanged).
> Review chain: rev 1 NO-GO ×3; rev 2 NO-GO ×3 (order-dependent ledger, unaddressable
> poll, hardcoded env filter); rev 3 NO-GO ×3 — the monetary fold was VALIDATED by all
> three reviewers (six permutations + refund cycle walked independently), remaining
> findings: beneficiary arrival-order pinning, reconcile provenance (v1 merged-customer
> history), txn-purge replay hole, App-Review sandbox conflict (resolved by tri-vote Q4:
> **A unanimous** — prod accepts PRODUCTION+SANDBOX, flagged + warn-logged), packDelta
> freezing, rejected-event replay poisoning, tombstone PII, sweep drain ceiling, secret
> binding, checked arithmetic. Rev 4: Gemini GO (2 fixes), Grok+Sol NO-GO — converged on
> multi-environment docId addressing, the v2 reconcile contract being unimplementable as
> sketched, alias/tombstone bypass, quantity contradiction, sweep ceiling, plus Sol's
> live find: the SHIPPED expiry query needs a composite index absent from
> FirestoreIndexes.json (pre-existing; blocks the queued functions deploy). Rev 5
> incorporates every round-4 finding. Reviews in session scratchpad
> `{sol,gemini,grok}-iap-review*.txt`.

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
- Accepted residual (documented — Grok-r3-5): a confirm revoked post-clawback keeps its
  credit-scan unit spent (the scan happened; consistent with non-refund-failure
  semantics). One scan slot of the rebuy pool; not repaired.
- Confirm-time integrity: credit-funded confirm re-checks `count < eff` in-transaction;
  failure releases the reservation, voids the token, errors `failed-precondition
  {reason: "receipt_credits_revoked"}` — **returned from the transaction as a result kind
  and thrown only AFTER commit** (throwing inside the callback would roll the release
  back; matches the live admission/confirm pattern). Token records
  `releaseReason: "revoked"`, and every retry replays the SAME stable error (see 14).

## Purchase transaction ledger — order-independent fact fold

`receipt_credit_txns/{docId}`, docId = **sha256 hex of
`${appId}|${store}|${environment}|${transactionId}`** (collision-resistant; no
sanitization aliasing). ALL FOUR components pass one shared `canonicalizeSource`
helper (upper-case env/store, trimmed) BEFORE hashing AND before any allowlist
comparison — RC v2 emits lower-case (`sandbox`) while webhooks emit `SANDBOX`, and
canonicalizing only at comparison time would let the two ingress paths hash two
different docIds for one transaction = double grant (Grok-r5-1; the reconcile
fixture must use v2-canonical lower-case input). **The environment component comes
ONLY from purchase provenance**
— the webhook event's own `environment`, or the RC lookup's environment in reconcile;
never from a server default (Grok-r4-1: under Q4's two-environment allowlist, a
defaulted env desyncs status/reconcile from the webhook's doc and can double-grant;
emulator pin: SANDBOX webhook followed by a reconcile → exactly ONE grant). Raw `appId`,
`store`, `environment`, `transactionId` retained as fields (lookup + invariant checks).
Server-only; explicit rules deny pin. **NEVER purged**
— these docs are global idempotency keys for App Store transactions and must OUTLIVE the
account (Gemini-r3 CRIT: purge + reconcile = cross-account replay of the same Apple
transaction); deleteAccount ANONYMIZES them instead (see 15).

Fields: `uid` (beneficiary — **set ONLY by the purchase fact's `app_user_id`**, never by
refund/reversal-only events; a refund-first doc keeps `uid` unset and the fold applies
nothing until the purchase fact arrives and pins it — Sol-r3 CRIT-1: first-arrival
pinning made attribution arrival-order-dependent under alias churn), `productId`,
`packDelta` (**frozen once set** by the first purchase fact; quantity contract
(Sol-r4-11): only missing or `1` is accepted → `packDelta = 10`; ANY other quantity
(0, negative, ≥2) rejects the event with a logged error and NO ledger mutation —
multi-quantity is formally unsupported end-to-end and the in-app UI always buys 1;
a later purchase fact with a different quantity is a logged no-op), fact
timestamps `purchaseAtMillis?`, `refundAtMillis?`, `reversalAtMillis?` (from
`event_timestamp_ms`, validated by `isTimestampMillis` — NOT `safeQuotaCount`, which is
count-shaped; refund/reversal keep the MAX seen — supports refund→reverse→refund
cycles), applied markers `grantApplied`, `clawApplied`, `eventIds[]` (cap 20),
`createdAtMillis`, `updatedAtMillis`.

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

Event → fact mapping (**exact product-id allowlist predicate, pinned**:
`CREDITS_PRODUCT_IDS = {com.writes.harrysplayhouse.credits.receipts10}`; the branch runs
BEFORE the subscription path on exact `product_id` membership only — Grok-r3-2):
`NON_RENEWING_PURCHASE` → purchase fact (+packDelta, min timestamp wins if duplicated);
`CANCELLATION` (ANY cancel_reason — a consumable cancellation is always a refund) →
refund fact; `REFUND_REVERSED` → reversal fact; any other type → event recorded on
`revenuecat_events`, `logger.error`, NO fact.
Tie semantics, documented intentional: `reversalAtMillis == refundAtMillis` →
`refundEffective == false` (equal timestamps favor the customer). Fold arithmetic is
CHECKED with a domain max (`QUOTA_DOMAIN_MAX = 1_000_000`): any add/ceiling computation
that would exceed it fails closed (logged error, no write) — `safeQuotaCount` alone
admits values up to MAX_SAFE_INTEGER (Sol-r3-10).
This resolves every rev-2 hole: refund-before-purchase nets zero but leaves the ledger
whole (late purchase applies grant AND claw together), a later reversal restores +10;
purchase→reversal→late-cancellation compares TIMESTAMPS so the stale refund never claws.
**Tests: all 6 arrival permutations of {purchase, cancellation, reversal} + duplicates
+ refund→reverse→refund, asserting final aggregates per the fold; the SAME 6
permutations with purchase uid A and refund/reversal alias B asserting the per-UID
quota docs (not just global totals — beneficiary must be A in every ordering);
conflicting-quantity duplicate purchase facts in both orders (no-op + error log);
boundary tests at QUOTA_DOMAIN_MAX.**

## revenueCatWebhook.ts

1. Parser: standard events normalize `entitlement_ids: null`/missing → `[]` (exact-shape
   `null` tests). Parse optional `product_id`, `transaction_id`, `environment`, `store`,
   `app_id`, `quantity`. Subscription payload regression suite passes byte-identical.
2. **Source filter — config-driven, fail-closed** (env/params, not hardcoded):
   `RC_EXPECTED_APP_ID`, `RC_EXPECTED_STORE` (=`APP_STORE`),
   `RC_ALLOWED_ENVIRONMENTS` (comma list). **Tri-vote Q4, unanimous A**: prod =
   `PRODUCTION,SANDBOX` — App Store reviewers purchase with sandbox Apple IDs against
   the production backend, and Apple's receipt guidance requires production servers to
   tolerate sandbox during review; a strict filter breaks the review flow (Gemini-r3
   CRIT-2). SANDBOX grants are accepted, ledger-flagged (`environment` field),
   `logger.warn`ed, and bounded by the 4x ratio (TestFlight-tester minting accepted:
   2 trusted testers). Staging (if used) = `SANDBOX`. Credits events where app_id/
   store mismatch, environment ∉ allowed set, or `app_id`/`transaction_id` is
   missing/empty (RC documents both as present — missing = malformed, fail closed):
   200-acknowledged, `logger.warn` (environment) / `logger.error` (otherwise), ZERO
   ledger mutation — and the event record carries a **retryable disposition**
   `rejected_source_config` (Sol-r3-5): a later re-send of the SAME event id may
   transition it atomically to applied once the current config accepts it, so a
   temporary config error is not a permanent grant/claw loss. **Webhook-required
   config = `RC_EXPECTED_APP_ID`, `RC_EXPECTED_STORE`, `RC_ALLOWED_ENVIRONMENTS`;
   any of those unset/empty → credits events answered 503** (fail closed AND
   RC-retryable — Grok-r4-4: a 200-ack on a config gap would burn RC's five retries
   and permanently lose CANCELLATIONs; per-event source mismatches stay 200 +
   disposition, with the manual RC-dashboard claw replay documented in the runbook).
   `RC_PROJECT_ID` and the v2 secret are RECONCILE-required only (missing →
   `unavailable` on the callable; they must NOT gate webhook grants/claws —
   Grok-r5-4). All rejection + retry cases pinned.
3. **Credits branch = separate handler + transaction** (never threaded through the
   subscription branch). Reads, ALL before any write: `revenuecat_events/{event.id}`
   (duplicate → no-op unless `rejected_source_config`, which is retryable per 2),
   `receipt_credit_txns/{docId}` (read BEFORE tombstones so the pinned beneficiary is
   known), then `deleted_users/{sha256(uid)}` tombstones for BOTH the incoming
   `app_user_id` AND the txn's pinned beneficiary (Sol-r4-3: a refund carrying alias B
   must not bypass beneficiary A's tombstone), and the literal sentinel
   `uid == "__deleted__"` is terminal (Gemini-r4-2). ANY hit → **log non-identifying
   metadata only (event id + type), write NOTHING** — not even the event record: a
   user-linked `revenuecat_events` doc after the purge would resurrect deleted-user
   data (Sol-r3-6). Otherwise read beneficiary's `${uid}_receipt_credits`, then fact
   update + fold + event record. Emulator tests: purchase-A → delete-A →
   refund-alias-B writes nothing;
   two CONCURRENT identical deliveries → exactly one grant; webhook delivered AFTER a
   completed deletion purge → no user-linked document reappears.
4. Never a subscription write from the credits branch, even with
   `entitlement_ids ∋ "pro"` (grant credits, skip entitlement, `logger.error`; pinned).
5. Lifetime-grant hardening: `lifetimeGrantEventTypes` → explicit EMPTY allowlist (no
   lifetime SKU exists); `NON_RENEWING_PURCHASE` + pro + no expiry now
   `skipped_no_expiration` + error log. Deliberate behavior change, pinned.
6. `revenuecat_events` records gain `productId`, `transactionId`, `environment`,
   `store`, `packDelta` when present (no PII).
7. Numeric hardening split by shape: `granted`/`clawed`/`packDelta`/counts through
   `safeQuotaCount` + the checked `QUOTA_DOMAIN_MAX` arithmetic; fact timestamps
   through `isTimestampMillis` (Grok-r3-8).
8. TRANSFER: no credits movement; txn-pinned beneficiary keeps refund/reversal
   attribution stable across alias churn. Support-docs note: account merge ≠ credits.

## receiptQuota.ts

9. **Sweep**: `expirySweepWrites` returns post-release `statesByBucket` for EVERY
   bucket; **`${uid}_receipt_credits` is ALWAYS force-included in the sweep read set**
   (even with zero expired tokens) so admission/status read credit state exclusively
   from the post-release map (Grok-r2-4; Sol-r1-8 pin: expired credit token + fallback
   admission in one transaction ends `reserved == 1`). When the expired-token query
   returns a full page, STATUS drains SERVER-SIDE: the sweep queries `limit(11)`,
   processes 10, and uses the 11th row purely as a `hasMore` probe (Sol-r4-5: a full
   final page is otherwise indistinguishable from done); it runs further bounded sweep
   transactions (10 rounds/call) and responds with `sweepIncomplete = hasMore` — and
   the client keeps re-fetching until `sweepIncomplete == false` with NO fixed round
   cap (each round is cheap; convergence is guaranteed because every round strictly
   consumes expired tokens). Admission keeps its single sweep page (denial heals via
   status refresh). Regressions at 10, 12, 50, 51, 100 (exact boundary), and 520
   expired reservations.
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
    The `"refund"` releaseReason's writer is the EXISTING refund machinery
    (`refundReceiptQuota`/`voidReceiptReservation` already void tokens on upstream
    failures — this rev adds the field there, in scope; clawback-time mass-voiding
    remains the separately-deferred item). The expiry sweep writes `"expired"`. Snapshots composed per 11.

## receiptQuotaStatus.ts

13. One transaction, explicit read order (all reads → all writes): `users/{uid}` →
    base buckets → credits + credit-scans docs → `app_config/receipt_credits` →
    optional txn docs — **one candidate docId PER allowed environment**, each
    `sha256(canonicalize(RC_EXPECTED_APP_ID | RC_EXPECTED_STORE | env |
    transactionId))` (the client supplies ONLY transactionId; app and store come
    from server config; batch-read; the doc that exists wins —
    Gemini-r4-1: a single-environment default makes sandbox review purchases poll
    `"unknown"` for the full 60s schedule; the client never supplies the tuple) →
    expiry query → referenced expired-token buckets → sweep writes → composite
    snapshot. `transactionState` returned only when the txn's `uid` == caller:
    `"granted"` (grantApplied && !refundEffective), `"refunded"` (refundEffective),
    else/foreign/absent `"unknown"`.
    `creditsPurchasingEnabled` echoes `app_config/receipt_credits
    {purchasingEnabled: bool, expiresAtMillis: number}`: true iff enabled AND
    unexpired (operator renews; expiry fails closed on neglect — reduced-scope
    version of Sol-r2-9's readiness lease, with reconciliation as the safety net).

## reconcileReceiptCreditPurchase.ts (NEW export — Sol-r2-2: repair is in scope)

14. `onCall({enforceAppCheck, timeoutSeconds: 30, secrets: [revenueCatSecretApiKey]})`,
    auth required. **The secret is a defined param bound to this function AND to
    `deleteAccount`** (Sol-r3-8: v2 functions receive Secret Manager values only when
    the secret is defined and bound per function — a bare `process.env` read can pass
    the operator checklist yet stay permanently `unavailable`; read via the param API
    with `process.env` fallback for `.env` deployments; deploy verification asserts
    the binding on the running revisions). ONE coherent v2 credential (Sol-r4-7):
    provision a v2 secret key with permissions `customer_information:purchases:read`,
    `project_configuration:products:read`, `customer_information:customers:read_write`,
    and MIGRATE deleteAccount's subscriber erasure from the v1 endpoint to v2
    `DELETE /projects/{RC_PROJECT_ID}/customers/{uid}` in the same commit (else two
    versioned secrets must be defined and bound — pick the migration). Input
    `{transactionId}` (shape-validated first). Key unset → `unavailable` (fail-soft
    precedent: RC erasure).
    **Provenance — transaction-addressed, never merged-customer history** (Sol-r3
    CRIT-2/3; contract pinned per Sol-r4-1/6/10 + Grok-r4-3): RC **v2 API** under
    `RC_PROJECT_ID`, purchase search by store transaction identifier (15s
    AbortSignal; implementer verifies the exact endpoint path against current RC v2
    docs at build time — REQUIRED capabilities: owner customer ids, product ref,
    store, environment, status, quantity). Normalize v2's lower-case enums
    (`app_store`/`production`/`sandbox`) into the webhook's canonical upper-case
    before comparison. Require EXACTLY ONE result and ALL of:
    `original_customer_id === customer_id === caller uid` (rejects outbound AND
    inbound transfers — `original == caller` alone passes an outbound transfer),
    `status == "owned"` (not refunded/removed — a lost CANCELLATION must not be
    resurrect-granted; claw stays webhook-primary), the purchase's product resolved
    to its App Store `store_identifier` (via the v2 product endpoint or pinned
    internal ids — v2 returns RC-internal product ids, NOT the ASC identifier) ∈
    `CREDITS_PRODUCT_IDS`, app matches, environment ∈ `RC_ALLOWED_ENVIRONMENTS`
    (docId env = the LOOKED-UP environment — provenance, never a default),
    quantity missing/1. Error mapping (Sol-r4-10): `not-found` ONLY for 404/empty/
    ambiguous/provenance failures; 429/5xx/timeout/malformed → retryable
    `unavailable` honoring Retry-After (never `grant_missing` analytics from an
    outage). Success → fold the purchase fact through the SAME transaction
    machinery (idempotent with any later webhook),
    `eventIds += ["reconcile:" + txnId]`. The returned `transactionState` is
    derived from the POST-FOLD ledger by the same rules as status — v2
    `status == "owned"` only ADMITS the fold; a ledger already refund-effective
    reports `"refunded"`, never `"granted"` (Grok-r5-6). If the v2 API cannot
    satisfy the capability list at build time, STOP and escalate (no silent v1
    merged-history fallback).
    Returns typed `{transactionState, quota: snapshot}` and the client routes it
    through the SAME terminal transition as polling (`granted` / `refunded` /
    `unknown` — Sol-r3-9). Rejection tests: sandbox-not-allowed, wrong app/store,
    transferred, refunded, foreign-uid. Per-uid rate limit 10/day via `usage_quotas`.
    Operator queue item (d) — the RC secret key — is a launch-gate prerequisite for
    flipping the capability flag.

## deleteAccount.ts

15. **Tombstone first** (Sol-r2-7): write `deleted_users/{sha256(uid)}
    {deletedAtMillis}` — **keyed by one-way UID hash, no raw uid field** (Sol-r3-6)
    — as the new FIRST cascade step; the credits webhook and reconcile callable hash
    the incoming uid and go inert on a hit (late/queued webhooks cannot resurrect
    ledger, quota, or event docs). Tombstone-first + mid-cascade failure is benign:
    deletion retry is idempotent against an existing tombstone (pinned — Grok-r3-7);
    the user's credits path being inert during a failed-deletion window is accepted
    (they asked for deletion). `receipt_credit_txns` are **NOT purged** — batched
    UPDATE sets `uid: "__deleted__"` AND deletes the raw `transactionId` and
    `eventIds` fields (Sol-r4-12: raw store identifiers are re-identifiable via RC —
    the sha256 doc key plus monetary facts alone are what replay prevention needs;
    Gemini-r3 CRIT-1). The two quota docs are covered by the `${uid}_`
    prefix purge; tests pin tombstone + anonymization + quota purge + the
    deletion-races-grant case. (The subscription webhook's own late-event
    resurrection of `users/{uid}` is PRE-EXISTING and out of scope; documented.)

## Rules

16. No rules change (catch-alls). Rules tests add explicit client deny pins:
    `${uid}_receipt_credits`, `${uid}_receipt_credit_scans`,
    `receipt_credit_txns/*`, `app_config/*`, `deleted_users/*`.

## Server tests (delta beyond those named inline)
Webhook: `entitlement_ids: null` grant; 6-permutation fold matrix + duplicates +
refund→reverse→refund; concurrent duplicate (emulator) → one grant; source-filter
cases per Q4-A: SANDBOX on the prod allowlist is an ACCEPTANCE pin (grant + flagged
environment + warn log + poll-addressable); rejections = environment ∉ allowlist,
PLAY_STORE, wrong/missing app_id, missing transaction_id, unset webhook config → 503;
**quantity reject (≠1)**: zero ledger writes, event recorded with a disposition,
HTTP 200 (same family as unknown types — a 500 would burn RC's retries, a bare 200
without the record would lose forensics); credits+pro → no subscription write; lifetime
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
    `receipt_credits_grant_delayed`, then call `reconcileReceiptCreditPurchase` and
    route its typed `{transactionState, quota}` through the SAME terminal transition
    as polling: `granted` → clear marker, refresh, celebrate; `refunded` → terminal
    refund handling; `unknown`/not-found → `receipt_credits_grant_missing` +
    "Purchase received — credits will appear shortly" + persisted-txn resume on next
    sheet open (which re-polls then re-reconciles). **The persisted marker carries a
    72-hour TTL from purchase** (Gemini-r5: a deterministic provenance rejection
    would otherwise re-poll forever on every sheet open; a wire-visible
    "foreign/rejected" state was REJECTED as an existence oracle — the uniform
    `unknown`/not-found stays, and expiry is client-local): past the TTL the marker
    clears terminally with a support-reference message and a final
    `receipt_credits_grant_missing`. Manual refresh runs the same transition.
    Ask-to-Buy `pending` purchases that are approved later surface via the next
    status refresh (no push channel; documented — Grok-r3-10).
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
0. **URGENT, precedes even the ALREADY-QUEUED functions deploy (operator item b)**:
   `firebase deploy --only firestore:indexes` and wait READY — the SHIPPED expiry
   sweep queries `receipt_scan_tokens(uid ==, consumed ==, expiresAtMillis <)`,
   which requires the composite index added to `Configuration/FirestoreIndexes.json`
   in this branch (Sol-r4-4: without it, scan admission starts throwing
   failed-precondition in prod as soon as the first token expires — the emulator and
   the in-memory double never catch a missing production index).
1. ASC: product submitted with a version; review screenshot.
2. RevenueCat: product added WITHOUT entitlement attachment; **In-App Purchase Key
   uploaded + App Store Platform Server Notifications → RevenueCat** (consumable
   refund detection requires both); **"track new purchases from server-to-server
   notifications" OFF** (Sol-r2-8: non-UUID app user ids can grant to an anonymous
   alias); prod webhook receives both environments (tri-vote Q4-A) — no separate
   staging RC project required.
3. Sandbox E2E evidence against the PROD backend (SANDBOX allowed per Q4-A), inside a
   short-lived capability window (flag enabled with a short `expiresAtMillis` for the
   session): TestFlight purchase → grant with **SDK transactionIdentifier == webhook
   transaction_id** asserted AND the **actual RC event type recorded**
   (allowlist only what RC really sends — Grok-r3-6), `receiptQuotaStatus
   {transactionId}` = `granted` for the buyer and `unknown` for another uid;
   refund → clawback observed. Record alongside revisions.
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
