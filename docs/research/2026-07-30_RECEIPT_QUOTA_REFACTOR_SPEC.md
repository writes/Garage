# Receipt quota refactor — implementation spec (2026-07-30, rev 2 after Sol NO-GO)

> Unit redesign agreed 2026-07-29 (operator); Pro allowance confirmed MONTHLY 2026-07-30.
> Confirm mechanism = option B by unanimous tri-vote (DECISION_LEDGER 2026-07-30). Rev 2
> incorporates all 12 findings of GPT-5.6 Sol's co-review (NO-GO on rev 1): the two CRITICAL
> quota-integrity defects are fixed with a **reservation model** (scan admission reserves a
> confirmed-unit slot; confirm converts it; expiry releases it lazily), tokens are **bound at
> scan time** to the bucket that admitted them, and the wire contract is **additive** for old
> clients. Sol transcript: session scratchpad `sol-review2.txt`.

## Model
| | confirmed allowance | scan ceiling (4x) | period |
|---|---|---|---|
| Free | 5 | 20 | lifetime |
| Pro | 20 | 80 | per UTC month |
| +IAP | +10 per $1 (DEFERRED — needs ASC products) | — | consumable |

The scan ceiling bounds API spend; the confirmed allowance is the monetization lever. Both are
hard-enforced (Sol #1): `confirmed.count + confirmed.reserved` can never exceed the allowance,
so banked tokens cannot inflate 5/20 into 20/80.

## Server (`CloudFunctions/src`)

### Firestore docs (all server-only; rules catch-all denies clients — tests pin this)
- Scan buckets in `usage_quotas`: free reuses existing `${uid}_receipt_lifetime`
  (`{count}` — it already counts lifetime scans, zero migration); pro
  `${uid}_receipt_scan_${YYYY-MM}`. Legacy pro daily docs become inert; never read.
- Confirmed buckets in `usage_quotas`: `${uid}_receipt_confirmed_lifetime` /
  `${uid}_receipt_confirmed_${YYYY-MM}` with fields `{uid, kind, count, reserved, updatedAt}`
  (`reserved` = outstanding unconsumed, unexpired tokens admitted against this bucket).
- `receipt_scan_tokens/{uuid}`: `{uid, entitlementUsed: "free"|"pro",
  confirmedBucketId, resetAtMillis: number|null, createdAtMillis, expiresAtMillis
  (created+24h), consumed: false, consumedAtMillis?: number}`. Timestamps are epoch millis
  (numbers), matching `parseMillis` conventions. Token bound to its admitting bucket at scan
  time (Sol #2) — confirm NEVER routes by current entitlement/month.

### receiptQuickAdd.ts
1. Constants: `FREE_LIFETIME_CONFIRMED_QUOTA=5`, `FREE_LIFETIME_SCAN_CEILING=20`,
   `PRO_MONTHLY_CONFIRMED_QUOTA=20`, `PRO_MONTHLY_SCAN_CEILING=80`. Delete the old pair.
   New helper `nextUtcMonthStart(now)` beside `nextUtcMidnight`.
2. Scan admission (`consumeReceiptQuota` rewrite), ONE transaction, ALL reads before ANY
   write (Firestore rule): read `users/{uid}` → entitlement; read scan bucket; read confirmed
   bucket; **lazy expiry release** (Sol #1's leak counter-measure): `tx.get` a query on
   `receipt_scan_tokens` where `uid==, consumed==false, expiresAtMillis < now` limit 10 —
   sum releasable per bucket, then in the write phase mark each `consumed: true` (with
   `consumedAtMillis: now`, a `released: true` marker) and decrement `reserved` accordingly.
   Then admission checks against post-release numbers:
   - `scanCount >= ceiling` → `resource-exhausted`, details `{reason:
     "receipt_scan_exhausted", scope: "free_lifetime"|"pro_month", resetAt?}` (resetAt only
     for pro, ISO string of next month start).
   - `confirmed.count + confirmed.reserved >= allowance` → `resource-exhausted`, details
     `{reason: "receipt_confirmed_exhausted", scope: "free_lifetime"|"pro_month", resetAt?}`
     (scope present on BOTH reasons — Sol #5).
   - Else: increment scan count, increment confirmed.reserved, and `tx.create` the token doc
     (`create`, not `set` — collision-safe; id = `crypto.randomUUID()`).
   Reservation is admission: a scan is only admitted if a confirmed slot is reservable, so
   over-allowance confirmation is impossible by construction.
3. Refund on failure paths must ALSO release the reservation and void the token: refund =
   one transaction doing scan-count −1, reserved −1, token `consumed: true, released: true`.
   Refund triggers: network throw, HTTP ≥500, **429 (new — Anthropic doesn't bill them)**,
   **fetch abort/timeout (new)**. Unchanged no-refund (scan spent, reservation + token kept
   so the user can still confirm nothing — they keep the slot until expiry releases it? NO:
   on non-refund failures there is no proposal and no token is returned to the client, so
   void the token + release the reservation there too; the SCAN unit alone stays spent):
   other 4xx, HTTP-OK-malformed, `not_a_receipt`, recognizability backstop. Net: token+
   reservation exist iff the client received a proposal.
4. Anthropic fetch: `signal: AbortSignal.timeout(55_000)`; abort → refund path +
   `HttpsError("deadline-exceeded", "Claude request timed out.")`. `onCall` options gain
   `timeoutSeconds: 120`.
5. Response shape is ADDITIVE (Sol #4): proposal fields stay exactly where they are today
   (top-level), plus new top-level `token: string` and `quota: ReceiptQuotaSnapshot`. Old
   clients ignore both keys, decode unchanged, save entries, never confirm — their
   reservations expire and release after 24h; ACCEPTED two-tester exposure (Sol #9), noted
   in HANDOFF.

### ReceiptQuotaSnapshot (one DTO for all three callables — Sol #4)
`{entitlement: "free"|"pro", scanRemaining, scanCeiling, confirmedRemaining,
confirmedAllowance, resetAt: string|null}` where `confirmedRemaining = allowance − count −
reserved` (what a user can actually still start+finish), clamped ≥0.

### confirmReceiptScan.ts (NEW export)
`onCall({region, enforceAppCheck, timeoutSeconds: 30})`, auth required. Input `{token}`.
Validate BEFORE any read: string, exactly 36 chars, UUID-v4 regex → else `invalid-argument`.
One transaction: read token doc; missing OR `uid` mismatch → `not-found` with the SAME
message for both (no foreign-token oracle — Sol #10). Precedence (Sol #10): if `consumed`
→ return current snapshot of ITS bucket, success (idempotent — a legitimately consumed
token retried after expiry is still success). Else if expired (`expiresAtMillis < now`) →
`failed-precondition {reason: "receipt_token_expired"}` (its reservation is released by the
next scan's lazy sweep, or by this call: release it now — reserved −1, mark
`consumed: true, released: true` — self-healing). Else: read the token's STORED
`confirmedBucketId`, count +1, reserved −1, token `consumed: true, consumedAtMillis`.
Cannot exceed the allowance by construction (reservation). Returns the snapshot.

### receiptQuotaStatus.ts (NEW export)
Read-only `onCall` (auth + App Check, `timeoutSeconds: 30`): current-entitlement snapshot
from the two buckets (plus the same lazy expiry-release sweep, non-transactionally skippable
— run it in a transaction identical to scan admission minus the increments, so the numbers
shown are accurate after abandons).

### deleteAccount.ts (Sol #3)
Add `receipt_scan_tokens` where `uid ==` batch purge to the cascade + test. (Also note for a
future commit: a Firestore TTL policy on `expiresAtMillis` would sunset consumed tokens;
deferred, documented.)

### voiceQuickAdd.ts / claudeProxy.ts (same commit, deployed together — Sol #8)
Same `AbortSignal.timeout(55_000)` + abort-refund + 429-refund + `timeoutSeconds: 120` on
all three AI callables. `MAX_PDF_BASE64_BYTES` 10 MiB → 9 MiB in claudeProxy.ts. No unit-
model change for voice/oil.

### index.ts — export `confirmReceiptScan`, `receiptQuotaStatus` (9 → 11).

### CI (Sol #7)
Add `npm test` to the `functions` job in `.github/workflows/ios.yml` (it currently runs
only ci+build — function tests never ran in CI). `npm run test:rules` (emulator) stays a
local-gate requirement documented in the runbook; wiring the emulator into CI is a
follow-up. (CI is billing-dead today; this lands dormant but correct.)

### Server tests
- `confirmReceiptScan.test.ts` (NEW): valid consume (count+1, reserved−1, snapshot),
  idempotent re-confirm (incl. after expiry), expired-unconsumed (error + reservation
  released), malformed token (invalid-argument, no db read), missing vs foreign token
  (identical not-found), bucket binding: free→pro upgrade mid-flight debits the FREE bucket
  the token stored; month-boundary confirm debits the admitting month.
- `receiptQuickAdd.test.ts` (UPDATE): ceiling denial both scopes; **reservation admission**
  — with allowance 5, five unconfirmed scans admit and the sixth denies
  `receipt_confirmed_exhausted` even though `count==0` (the Sol #1 exploit, pinned);
  lazy release — an expired token's slot readmits a new scan and marks the old token
  released; refund paths (network/5xx/429/timeout) release reservation + void token;
  non-refund failures void token + release reservation but keep the scan unit; token doc
  shape (bucket binding fields); additive response shape (old top-level fields byte-stable);
  monthly boundary bucket flip; legacy `${uid}_receipt_lifetime` honored as scan count.
- `receiptQuotaStatus.test.ts` (NEW): fresh/partial/exhausted/reserved-visible/pro resetAt.
- Voice/oil tests: new refund/timeout pins; oil 9 MiB cap.
- `tests/rules/firestore.rules.test.ts`: explicit client default-deny for `usage_quotas/*`
  AND `receipt_scan_tokens/*`; plus one emulator concurrency test (Sol #6): two parallel
  `confirmReceiptScan`-shaped transactions on the same token — exactly one increments
  (the serial InMemoryFirestore cannot prove this; the emulator can).
- deleteAccount test: token purge.

## Client (`Garage/`)

8. `ReceiptQuickAddService`: decode additive `token` + `quota`; `proposeEntry` returns
   `(proposal: ReceiptEntryProposal, token: String?, quota: ReceiptQuotaSnapshot?)` (both
   optional-decoded — server absence tolerated). Protocol gains
   `confirmScan(token:) async throws -> ReceiptQuotaSnapshot` and
   `quotaStatus() async throws -> ReceiptQuotaSnapshot`. One Swift DTO mirroring the server
   snapshot. Fakes updated.
9. `ReceiptPrefillPackage` carries token + quota. `EntryFormViewModel+ReceiptPrefill`
   stores the token; in `finishSaveTracking`'s `wasReceiptSeeded` branch, fire-and-forget
   one confirm attempt; on thrown error emit `receipt_confirm_sync_failed`; token cleared
   either way (idempotency makes an accidental double-call safe anyway). Never fired on
   abandon.
10. Balance UI (Sol #12): footer uses the snapshot's `confirmedRemaining` (already the
    effective start+finish number since it subtracts reservations) EXCEPT when
    `scanRemaining == 0`, which renders the scan-exhausted state instead of promising saves
    that cannot be scanned. Copy — free: "N receipt saves left" · pro: "N receipt saves left
    this month". Status fetched on sheet appear; fetch failure → no footer, capture still
    allowed (server is authoritative); re-fetch on re-appear only. Denial mapping in
    `classifyReceiptError`: `receipt_scan_exhausted` + `receipt_confirmed_exhausted`, both
    carrying `scope` (+optional resetAt): `free_lifetime` → existing upsell
    (`PaywallSource.receiptScan`); `pro_month` → reset-date banner. Legacy reason cases
    removed.
11. Field-outcome instrumentation (Sol #11): TWO distinct captures. (a) Raw-model presence:
    which proposal fields were non-nil — drives the single "Not read from the receipt: …"
    caption. (b) Effective-seed snapshot: form values captured AFTER `applyReceiptPrefill`
    AND after `reconcileReceiptOdometerFloor` (the programmatic odometer bump and any
    isDiy/notes derivation are part of the seed, not a user edit). On save, for each field
    seeded in (b), emit `receipt_field_outcome(field:, edited: currentValue !=
    snapshotValue)` over closed enum `ReceiptPrefillField {date, odometer, cost, shop, diy,
    notes}`. Booleans only, no values. Test matrix: odometer-floor reconciliation ≠ edited;
    edit-then-revert = not edited; unseeded fields never emit; zero/empty values.
12. Analytics: `receipt_field_outcome`, `receipt_confirm_sync_failed` via the 4-step
    AnalyticsEvent pattern; `ANALYTICS_CONTRACT.md` §5.2 updated to the shipped model.

### Client tests
`ReceiptCaptureViewModel` (status fetch/failure/scan-zero override, new denial mapping),
`EntryFormViewModel` (confirm exactly once on save, never on abandon, token cleared),
`ReceiptFunnelAnalyticsTests` (field-outcome matrix incl. reconciliation and revert cases),
fakes.

## Deferred (explicit)
IAP top-ups (ASC products — operator); Firestore TTL policy on tokens; content-hash scan
dedup + vendor/date/total duplicate detection; emulator in CI; explicit `usage_quotas`
match block in PROTECTED rules (tests pin the catch-all).

## Order & gates
1. Server: quota engine + 2 callables + deleteAccount purge + tests → `npm test` AND
   `npm run test:rules` green locally (both counts reported, not just exit codes).
2. Client: service/UI/instrumentation + tests → full `verify-ios.sh` green (fail-closed
   gate landed 49458df).
3. Deploy ALL FIVE changed functions (receiptQuickAdd, confirmReceiptScan,
   receiptQuotaStatus, voiceQuickAdd, parseOilAnalysis) to prod; verify each running
   revision (landmine #9). Operator approval 2026-07-30 covers this scope.
4. `ANALYTICS_CONTRACT.md` + HANDOFF sync in the same PR.
