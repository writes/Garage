# Receipt quota refactor — implementation spec (2026-07-30)

> Unit redesign agreed 2026-07-29 (operator); Pro allowance confirmed MONTHLY 2026-07-30.
> Confirm mechanism = option B by unanimous tri-vote (DECISION_LEDGER 2026-07-30): entry save
> stays on the single client-side local-first path; a scanToken + `confirmReceiptScan`
> callable does confirmed-unit accounting. Rationale recorded in the ledger: Firestore rules
> permit direct client entry writes app-wide, so no design closes the modified-client bypass —
> the 4x scan ceiling is the spend bound either way, and B avoids forking save semantics.

## Model
| | confirmed allowance | scan ceiling (4x) | period |
|---|---|---|---|
| Free | 5 | 20 | lifetime |
| Pro | 20 | 80 | per UTC month |
| +IAP | +10 per $1 (DEFERRED — needs ASC products) | — | consumable |

## Server (`CloudFunctions/src`)

### receiptQuickAdd.ts
1. Constants: `FREE_LIFETIME_CONFIRMED_QUOTA=5`, `FREE_LIFETIME_SCAN_CEILING=20`,
   `PRO_MONTHLY_CONFIRMED_QUOTA=20`, `PRO_MONTHLY_SCAN_CEILING=80`. Delete
   `DAILY_RECEIPT_QUOTA`/`FREE_LIFETIME_RECEIPT_QUOTA`.
2. Buckets (`usage_quotas`, server-only, rules catch-all already denies clients):
   - free scan: REUSE existing `${uid}_receipt_lifetime` doc (it already counts lifetime
     scans — zero migration); free confirmed: `${uid}_receipt_confirmed_lifetime` (new, starts
     0 — prior scanners get their full 5 confirms).
   - pro scan: `${uid}_receipt_scan_${YYYY-MM}`; pro confirmed:
     `${uid}_receipt_confirmed_${YYYY-MM}`. New helper `nextUtcMonthStart(now)` for `resetAt`.
   - Legacy pro daily docs (`${uid}_receipt_${date}`) become inert; do not read them.
3. `consumeReceiptQuota` → scan admission, one transaction: read `users/{uid}` (entitlement),
   scan bucket, confirmed bucket. Deny `resource-exhausted` with `reason:
   "receipt_scan_exhausted"` (details: `scope: "free_lifetime"|"pro_month"`, `resetAt` for
   pro) when scan count ≥ ceiling; deny `reason: "receipt_confirmed_exhausted"` (+`resetAt`
   for pro) when confirmed count ≥ allowance — scanning with nothing confirmable left is pure
   API waste. Else increment scan count.
4. Refund policy (scan unit): today network-throw + ≥500. ADD: 429 (Anthropic doesn't bill
   them) and fetch abort/timeout. Unchanged no-refund: other 4xx, HTTP-OK-malformed,
   `not_a_receipt`, recognizability backstop.
5. Anthropic fetch: pass `signal: AbortSignal.timeout(55_000)` via RequestInit; on abort →
   refund + `HttpsError("deadline-exceeded", "Claude request timed out.")`. Add
   `timeoutSeconds: 120` to the `onCall` options.
6. Success path additions: create `receipt_scan_tokens/{uuid}` doc `{uid, createdAt,
   expiresAt: now+24h, consumed: false}` (plain write after successful parse — a failed write
   fails the request, quota already spent, consistent with current malformed-output policy);
   response gains `token` and `quota: {scanRemaining, confirmedRemaining, resetAt?}`.
7. Old-client compat: old TestFlight clients receive the NEW denial reasons and fall through
   to their generic error banner — acceptable (2 testers), no crash path.

### confirmReceiptScan.ts (NEW export)
`onCall({region, enforceAppCheck, timeoutSeconds: 30})`, auth required. Input `{token:
string}`. One transaction: read token doc — must exist, `uid` match, not expired; read
`users/{uid}` + confirmed bucket. If already `consumed`: return current remainders
(idempotent — client retry is safe, never an error). Else mark consumed + increment confirmed
count. Deliberate: the increment may exceed the allowance under a scan-race (user scanned
several before confirming) — allowed, self-limiting because scan admission (§3) denies once
confirmed ≥ allowance. Confirm NEVER fails for quota reasons — the entry is already saved
locally; failing here would charge honesty with UX. Returns `{confirmedRemaining, resetAt?}`.

### receiptQuotaStatus.ts (NEW export)
Read-only `onCall` (auth + App Check): returns `{entitlement, scanRemaining, scanCeiling,
confirmedRemaining, confirmedAllowance, resetAt?}` from the two buckets. Client calls it when
the capture sheet opens ("show the balance before charging").

### voiceQuickAdd.ts / claudeProxy.ts (mechanical consistency, same commit)
Add the same `AbortSignal.timeout(55_000)` + abort-refund + 429-refund treatment to both
other Anthropic call sites (they are hand-copied parallels of the same pattern). No unit-model
change for voice/oil. While in claudeProxy.ts: `MAX_PDF_BASE64_BYTES` 10 MiB → 9 MiB
(headroom parity with receiptQuickAdd, audit finding).

### index.ts — export `confirmReceiptScan`, `receiptQuotaStatus` (9 → 11 exports).

### Server tests
- NEW `tests/confirmReceiptScan.test.ts`: valid consume, idempotent double-consume, expired
  token, foreign-uid token, missing token, over-allowance race increment tolerated, free vs
  pro bucket routing, entitlement read at confirm time.
- NEW `tests/receiptQuotaStatus.test.ts`: fresh user, partially consumed, exhausted, pro
  monthly resetAt.
- UPDATE `tests/receiptQuickAdd.test.ts`: ceiling denials both scopes, confirmed-exhausted
  scan denial, 429 + timeout refunds (flip the existing "does not refund 429" pins — policy
  change is deliberate), token issuance + quota in response, monthly boundary (2026-01-31 →
  2026-02-01 bucket flip), legacy `${uid}_receipt_lifetime` count honored as scan count.
- UPDATE voice/oil tests for the new refund/timeout behavior; oil test for 9 MiB cap.
- UPDATE `tests/rules/firestore.rules.test.ts`: explicit client default-deny tests for
  `usage_quotas/*` and `receipt_scan_tokens/*` (rules FILE untouched — catch-all already
  denies; the tests pin it).

## Client (`Garage/`)

8. `ReceiptQuickAddService`: decode `token` + `quota` from the response; add protocol methods
   `confirmScan(token:) async throws -> ReceiptQuotaSnapshot` and `quotaStatus() async throws
   -> ReceiptQuotaSnapshot` (new small struct). Fakes updated.
9. `ReceiptPrefillPackage` carries the token. `EntryFormViewModel+ReceiptPrefill` stores it;
   in `finishSaveTracking` (the existing `wasReceiptSeeded` branch) launch a detached
   fire-and-forget confirm call; single attempt; on failure emit
   `receipt_confirm_sync_failed` (no retry loop — an unconfirmed save is a free confirm for
   the user, bounded by the scan ceiling, and the token stays valid 24h for a future session
   sweep if we ever want one).
10. Balance UI: `ReceiptCaptureView` fetches `quotaStatus()` on appear; footer line —
    free: "N receipt saves left" · pro: "N receipt saves left this month". New denial mapping
    in `classifyReceiptError`: `receipt_scan_exhausted(scope)` and
    `receipt_confirmed_exhausted` → free scopes render the existing upsell
    (`PaywallSource.receiptScan`); pro scopes render the reset-date banner. Remove the legacy
    `receipt_free_exhausted`/`receipt_daily_exhausted` cases (server no longer emits them).
11. Field-edit instrumentation: `applyReceiptPrefill` snapshots which fields it seeded and
    their values (`entryDate, odometer, cost, shop, diy, notes`); on save, for each SEEDED
    field emit `receipt_field_outcome(field:, edited: Bool)` (closed `ReceiptPrefillField`
    enum, boolean only, no values — turns every real scan into a golden-set signal). Fields
    the AI failed to read (nil in the proposal): shown once in the form as a single caption
    ("Not read from the receipt: …") — uses the same snapshot, no per-field chrome.
12. Analytics: new events `receipt_field_outcome`, `receipt_confirm_sync_failed` per the
    4-step AnalyticsEvent pattern + `docs/developer/ANALYTICS_CONTRACT.md` §5.2 update (also
    correct its quota description to the confirmed-unit model, shipped).

### Client tests
`ReceiptCaptureViewModel` (status fetch + new denial mapping), `EntryFormViewModel` (confirm
fired exactly once on save, not on abandon; token cleared after), `ReceiptFunnelAnalyticsTests`
(field-outcome emission matrix: edited/unedited/unseeded), fake service conformances.

## Deferred (explicit)
IAP top-up packs (needs ASC consumable products — operator); scheduled token-doc sweep;
content-hash scan dedup + vendor/date/total duplicate detection (§4 roadmap); explicit
`usage_quotas` match block in PROTECTED firestore rules (tests pin the catch-all instead).

## Order & gates
1. Server commit(s): quota engine + two new callables + tests → `npm test` green.
2. Client commit(s): service/UI/instrumentation + tests → full `verify-ios.sh` green.
3. Deploy `receiptQuickAdd`, `confirmReceiptScan`, `receiptQuotaStatus` to prod (operator gate
   already granted for receipt scope 2026-07-30; verify running revisions per landmine #9).
4. `ANALYTICS_CONTRACT.md`/HANDOFF sync in the same PR.
