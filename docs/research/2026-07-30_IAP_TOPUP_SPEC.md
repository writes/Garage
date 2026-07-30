# Receipt-credit IAP top-ups — implementation spec (2026-07-30, rev 1)

> Extends `2026-07-30_RECEIPT_QUOTA_REFACTOR_SPEC.md` (shipped; reservation model live on main).
> Product `com.writes.harrysplayhouse.credits.receipts10` exists as an idempotent creation
> script (`scripts/release/create_receipt_credits_iap.py`, operator-run); this spec is the
> server ledger + webhook grants + refund clawback + client purchase UI.
> Tri-votes 2026-07-30 (DECISION_LEDGER): Q1 scan-coupling = **A unanimous** (dedicated
> lifetime credits bucket with its own 4x scan pool); Q2 clawback = **A unanimous**
> (lifetime granted/clawed accumulators, debt carries); Q3 audience = **C majority 2/3**
> (both tiers; free users see the offer only after ≥1 Pro-paywall dismissal).

## Model

| | grant | scan pool | period |
|---|---|---|---|
| Credits | +10 confirmed per $0.99 purchase | +40 (4x, same spend-bound ratio) | lifetime, never expires |

Money-math: $0.99 − Apple 15% ≈ $0.84 net per pack; worst-case API spend 40 scans ×
~$0.005 ≈ $0.20 ≈ 24% of net. Bounded per pack, forever, because both pools are lifetime.

**Effective allowance** `eff = max(0, granted − clawed)`. Balance shown/spent =
`max(0, eff − count − reserved)`. Credit scan ceiling = `4 × eff`. A refund after spending
drives balance to 0 and the deficit persists (next grant raises `eff`, paying debt first) —
buy→spend→refund→rebuy nets zero free credits (Q2-A).

## RevenueCat configuration invariant (CRITICAL — operator step, documented here)

The credits product must be added to the RevenueCat project **WITHOUT attaching it to the
`pro` entitlement** (or any entitlement). `revenueCatWebhook.ts` treats
`NON_RENEWING_PURCHASE` + `entitlementIds ∋ "pro"` as a **lifetime Pro grant** (the one
legitimately expiration-less type). A mis-mapped consumable would mint perpetual server-side
Pro for $0.99. The webhook additionally hard-guards this (below), but the dashboard mapping
must still be correct. The product is purchased via the RC SDK's direct-product path, NOT an
offering, so no offering config is needed.

## Server (`CloudFunctions/src`)

### Firestore docs (both in `usage_quotas` — inherits the rules catch-all client deny, the
### `${uid}_` id-prefix purge in deleteAccount, and the generic expiry-sweep machinery)

- `usage_quotas/${uid}_receipt_credits` — the confirm bucket for credit-funded scans:
  `{uid, kind: "receipt_credits", granted, clawed, count, reserved, updatedAt}`.
  `granted`/`clawed` are lifetime accumulators (webhook-only writes); `count`/`reserved`
  have exactly the same semantics as every other confirmed bucket (confirm/expiry/refund
  machinery reuses them unchanged).
- `usage_quotas/${uid}_receipt_credit_scans` — the scan bucket:
  `{uid, kind: "receipt_credit_scans", count, updatedAt}`. Same `count` semantics as the
  base scan buckets, so `refundReceiptQuota`'s scan-count decrement works unmodified.

Two docs (not one) is deliberate: every existing code path (admission writes, refund,
sweep, confirm) addresses buckets as `{count, reserved}` refs — uniform field semantics
mean zero special-casing in the shared machinery.

### revenueCatWebhook.ts

1. `parseRevenueCatEvent` additionally extracts optional `product_id` →
   `productId?: string` on `StandardRevenueCatEvent` (absent/non-string → undefined;
   never rejects an event for lacking it).
2. New constant `RECEIPT_CREDITS_PRODUCT_ID = "com.writes.harrysplayhouse.credits.receipts10"`
   and `RECEIPT_CREDITS_PER_PACK = 10`.
3. **Credits branch runs INSTEAD OF the subscription branch** when
   `event.productId === RECEIPT_CREDITS_PRODUCT_ID` (standard events only):
   - Grant: `type === "NON_RENEWING_PURCHASE"` → in the SAME idempotent transaction that
     creates `revenuecat_events/{event.id}` (existing exists-check = duplicate no-op),
     read `${uid}_receipt_credits`, write `granted: prior + 10` (merge; doc created with
     zeros if absent).
   - Clawback: `type === "CANCELLATION" && cancelReason === "CUSTOMER_SUPPORT"` →
     `clawed: prior + 10`, same idempotency. (Implementer: verify against current RC docs
     whether consumable refunds can also arrive as any other type; unknown types stay
     recorded-but-inert as today.)
   - Any OTHER event type for this product: record event, change nothing.
   - **Hard guard**: the credits branch NEVER writes `users/{uid}.subscription`, even if
     the event also carries `entitlementIds ∋ "pro"` (RC dashboard misconfiguration). In
     that case grant credits per the rules above, skip entitlement processing, and
     `logger.error` (a consumable mapped to an entitlement should page). Test pins this.
   - `isStaleSubscriptionEvent` does NOT apply to credits (grants/clawbacks are
     commutative additions; event-id idempotency is the only ordering control needed).
4. TRANSFER events: credits do NOT move (they key off our uid, not the RC subscriber).
   Documented accepted behavior; no code change.

### receiptQuota.ts

5. New helpers: `creditsEffectiveAllowance(granted, clawed)`; bucket ids
   `receiptCreditsBucketId(uid)` / `receiptCreditScansBucketId(uid)`.
6. **Admission fallback** in `consumeReceiptQuota` (one transaction, all reads first —
   add reads of both credit docs alongside the existing reads):
   - Try the base entitlement bucket exactly as today. If it admits → unchanged behavior
     (token bound to the base confirmed bucket).
   - If the base denies (either reason), try credits: admit iff
     `creditScans.count < 4·eff` AND `credits.count + credits.reserved < eff`.
     Admitted-on-credits writes: `creditScans.count + 1`, `credits.reserved + 1`, token
     with `confirmedBucketId = ${uid}_receipt_credits`; reservation's
     `scanBucketId = ${uid}_receipt_credit_scans` (so the existing refund path decrements
     the right scan counter). `entitlementUsed` stays the user's actual entitlement.
     `resetAtMillis: null`.
   - Deny only when BOTH base and credits deny. Error payload UNCHANGED (reason/scope/
     resetAt from the BASE bucket state) — old clients keep working; new clients decide
     whether to show the top-up from Q3 logic + snapshot, not the error payload. Denial
     now implies effective credits are unusable (zero balance or credit scan pool dry).
   - The expiry sweep already releases credit-bucket reservations: tokens carry their
     `confirmedBucketId`, `releasedByBucket` is generic, and the credits doc lives in
     `usage_quotas`. No sweep change; test pins it.
7. **Snapshot is additive**: existing five fields keep base-bucket-only semantics
   byte-for-byte (old-client compat + existing tests). New fields:
   `creditsRemaining` (= balance) and `creditsScanRemaining` (= max(0, 4·eff −
   creditScans.count)); both 0 when no credits doc exists.
   `receiptQuotaSnapshot(...)` gains optional credit inputs; all three callables return
   the extended shape.
8. `receiptQuotaConfigurationForToken` gains a credits branch: exact match
   `confirmedBucketId === ${uid}_receipt_credits` → configuration with the two credit
   bucket ids, `resetAt: null`, kinds as above, valid for either `entitlementUsed`. The
   static `confirmedAllowance` in that configuration is computed from the credits doc
   read inside the confirm transaction (eff), not from a constant — confirm already reads
   the confirmed bucket before building its snapshot, so eff is available where needed.

### confirmReceiptScan.ts
9. No structural change: token routing via `receiptQuotaConfigurationForToken` picks up
   the credits branch; `count + 1, reserved − 1` semantics identical. Snapshot for a
   credit-bucket token reports the extended shape with eff-based numbers.

### receiptQuotaStatus.ts
10. Reads the two credit docs in the same transaction; returns the extended snapshot.

### deleteAccount.ts
11. Zero change — the `${uid}_` documentId-prefix purge already deletes both credit docs.
    Test pins that both doc ids fall inside the purge range.

### Rules
12. No rules change (usage_quotas catch-all). `tests/rules/firestore.rules.test.ts` adds
    explicit client-deny pins for `${uid}_receipt_credits` and
    `${uid}_receipt_credit_scans`.

### Server tests
- Webhook: grant (+10, doc created), duplicate event id (no double grant), clawback
  (+10 clawed), clawback exceeding balance (debt: eff < count, balance floors at 0, next
  grant pays down), credits product + pro entitlementIds → credits granted, subscription
  UNTOUCHED, error logged (the misconfiguration pin), other event types inert for the
  product, product_id absent → existing behavior byte-identical (regression suite passes
  unmodified).
- Admission: base-first ordering (credits untouched while base has room), fallback admit
  on base-scan-exhausted and on base-confirm-exhausted, both-deny error payload identical
  to today's, credit reservation blocks over-allowance (5 unconfirmed credit scans with
  eff=5... i.e. reservation exploit pin replayed against the credits bucket), credit
  scan-pool exhaustion denies even with balance (and vice versa), refund path restores
  `${uid}_receipt_credit_scans.count` and `credits.reserved`, expiry sweep releases
  credit reservations.
- Confirm: credit token consume (count+1/reserved−1 on the credits doc), idempotent
  retry, expired credit token self-heal, free→pro upgrade mid-flight still debits the
  credits bucket the token stored.
- Status: extended snapshot with/without credit docs; legacy shape fields unchanged.
- deleteAccount: purge-range pin for both docs.

## Client (`Garage/`)

The offerings pipeline structurally excludes consumables (three independent gates:
`period?.isSupportedRenewal` in `LiveRevenueCatClient.install()` and
`PurchaseServiceState.makeSelection`, plus the closed `AnalyticsProductID` enum). Do NOT
widen it. The credits purchase is a parallel direct path:

13. `ReceiptCreditsPurchasing` protocol (`purchaseCreditsPack() async throws`,
    `creditsProductAvailable() async -> Bool`) + `LiveReceiptCreditsPurchaser` over
    `Purchases.shared.getProducts([RECEIPT_CREDITS_PRODUCT_ID])` +
    `Purchases.shared.purchase(product:)`. Product-not-found → unavailable (the
    ASC-mismatch failure mode stays silent-but-safe: offer simply hidden). Inert fake for
    demo/UI-test bootstraps (those never call `Purchases.configure` — an eager handle
    would be firebase-preconfigure-crash #5; hold it `@ObservationIgnored lazy` behind
    the runtime check like the established pattern).
14. Constants: `receiptCreditsPackIdentifier`. `AnalyticsProductID` gains
    `.receiptCredits10` (PlanIdentifierTests updated — the enum is pinned).
15. Purchase→grant latency UX: RC purchase resolves client-side before the webhook lands.
    After a successful purchase, show a transient "Adding your credits…" state and poll
    `receiptQuotaStatus` (e.g. 5 attempts, 2s backoff) until `creditsRemaining` rises;
    on timeout show "Purchase received — credits will appear shortly" with a manual
    refresh. Never block the sheet.
16. Offer placement (Q3-C):
    - Pro user hitting `receipt_confirmed_exhausted`/`receipt_scan_exhausted`
      (`scope == pro_month`): denial view offers the top-up directly alongside the
      reset-date banner.
    - Free user (`scope == free_lifetime`): denial view shows the Pro upsell as today;
      the top-up appears as a secondary option ONLY once the user has dismissed the
      receipt-scan paywall at least once. Track via the existing
      `paywallDidDismiss(source: .receiptScan)` hook → a per-uid persisted flag
      (UserDefaults through the established settings-store pattern).
    - Both gated on `creditsProductAvailable()` AND server capability (see 17).
17. Old-server tolerance: `ReceiptQuotaSnapshot` decodes `creditsRemaining`/
    `creditsScanRemaining` as optionals. `nil` (old server) → purchase UI hidden
    entirely (buying against a server that can't grant would eat money). Footer treats
    nil as 0.
18. Footer copy with credits: total saves left = `confirmedRemaining + creditsRemaining`,
    same scan-zero override logic extended: scans exhausted only when BOTH base and
    credit scan pools are dry.
19. Analytics (4-step AnalyticsEvent pattern; ANALYTICS_CONTRACT.md updated same PR):
    `receipt_credits_offer_shown` (props: scope), `receipt_credits_purchase_started`,
    `receipt_credits_purchase_succeeded`, `receipt_credits_purchase_failed`
    (props: reason class only, no values), `receipt_credits_balance_applied` (first
    status poll where the balance rose). All post-consent (consent-gate trap).

### Client tests
Purchaser fake + ViewModel: offer visibility matrix (pro direct / free pre-dismissal
hidden / free post-dismissal shown / product unavailable / nil-credits server), purchase
success → poll → balance applied, poll timeout path, footer arithmetic incl. credit scan
override, analytics event pins. UI journey: demo-mode receipt sheet still renders with the
inert purchaser (no RevenueCat).

## Deferred (explicit)
Additional pack sizes; StoreKit-direct server-notification path (RC webhook chosen);
credits transfer on RC TRANSFER; server-side RC REST reconciliation (needs
REVENUECAT_SECRET_API_KEY); Firestore TTL on receipt_scan_tokens (already queued).

## Order & gates
1. Server: webhook + quota engine + tests → `npm test` AND `npm run test:rules` green
   locally (counts reported).
2. Client: purchase path + UI + tests → full `verify-ios.sh` green.
3. OPERATOR: run `create_receipt_credits_iap.py` (if not yet), upload review screenshot,
   submit with a version; add the product in RevenueCat WITHOUT entitlement attachment;
   deploy functions (`revenueCatWebhook`, `receiptQuickAdd`, `confirmReceiptScan`,
   `receiptQuotaStatus`, `deleteAccount` carry changes) and verify running revisions
   (landmine #9).
4. Ship server BEFORE any TestFlight build carrying the client UI (old server + new
   client is safe by 17, but the offer stays hidden — communicate to testers).
