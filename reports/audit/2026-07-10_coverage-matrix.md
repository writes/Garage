# Garage iOS — Test Coverage Matrix (audit synthesis, 2026-07-10)

**Headline:** Of ~30 production surfaces, only 2 low-level utilities (AppleSignInNonce, AsyncTimeout) have GOOD coverage. Both "CriticalFlows" UI tests are launch-only stubs. **Every capital/trust-boundary surface — auth, entitlements/webhook, paywall gate, offline sync, exports — has zero meaningful coverage.**

---

## 1. Coverage Matrix

### 1.1 Features (UI layer)

| Surface | Covered by | Coverage | Notes |
|---|---|---|---|
| Auth (LoginView, AuthViewModel) | AuthFlowTests (stub); indirectly AppleSignInNonceTests, AsyncTimeoutTests, AppErrorTests | **PARTIAL** | Only helpers tested. The UI test never queries a sign-in button or asserts the auth screen — no actual flow coverage. |
| Dashboard | DashboardViewModelTests; indirectly WearServiceTests | **PARTIAL** | Initial-state construction only; no load/refresh/error/retry behavior. |
| EntryForms (12 form types + save pipeline) | EntryFormViewModelTests, ValidatorTests, EntryCreationTests (stub) | **PARTIAL** | Only odometer validation. Save pipeline (details encoding, EntryService persist, odometer pushback to Vehicle) untested. 0 of 12 form types exercised. |
| Garage (gallery, parts, detailing, warranty/recalls, Pro gate) | — | **NONE** | |
| Log (search, filter, detail) | EntryServiceTests (filter helper only) | **PARTIAL** | Search text-matching tested off-actor; filter sheet, query construction, detail view untested. |
| Settings (hub, vehicle form, profile, reminders, export, subscription) | ExportViewModelTests | **PARTIAL** | Initial-state only. VehicleForm validation, ReminderConfig, SubscriptionView untested. ProfileViewModel is a live bug (no persistence at all). |
| Shared (FloatingAddButton, ProGateView, VehicleSwitcher) | — | **NONE** | ProGateView is the paywall UX across 4 features. |
| Stats (MPG/cost/wear charts) | — | **NONE** | calculatedMPG plotting, cost grouping unverified. |
| App lifecycle (GarageApp bootstrap modes, AppRouter, AppState) | AuthFlowTests/EntryCreationTests (launch stubs) | **PARTIAL** | Stubs prove only that the uiTest bootstrap path reaches foreground. bootstrap(), vehicle auto-select, SeedData fallback, single-sheet router untested. |

### 1.2 Services

| Surface | Covered by | Coverage | Notes |
|---|---|---|---|
| AuthService | — | **NONE** | **Trust root for all Firestore access** (`uid`). Mode gating, Google flow, sign-out untested. |
| PurchaseService | — | **NONE** | `isPro` is the single entitlement source of truth. |
| VehicleService | — | **NONE** | The only client-side entitlement-gated write (free-tier cap). Explicitly injectable for testability — and untested anyway. |
| SyncService | — | **NONE** | The offline-write durability layer: enqueue, flush, failure-retention all unverified. |
| CSVExportService | — | **NONE** | Known defect: no quoting/escaping, no formula-injection sanitization. |
| PDFExportService | — | **NONE** | `shouldInclude` section-gating (core resale-report promise) unverified; temp file never cleaned up. |
| EntryService | EntryServiceTests | **PARTIAL** | Only static `filter`. Query construction (`in` clause subset logic), fetchLatestOdometer, lastFuelEntry untested. |
| ReminderService | ReminderServiceTests | **PARTIAL** | Only `sortUpcoming` happy path; nil-dueDate → distantFuture branch untested. |
| WearService | WearServiceTests | **PARTIAL** | `latestDashboardItems` dedup tested; nil-valuePct drop and save path untested. |
| SecureStoreService | SecureStoreServiceTests (stub) | **NONE** | `#expect(true)` verifies nothing — no keychain round-trip asserted. Effectively uncovered. |
| AppIntegrityService | — | **NONE** | App Check root of trust; provider-selection matrix (debug/device/release) unverified. |
| ClaudeService | — | **NONE** | Response→OilAnalysisEntry decode contract untested on either side of the wire. |
| FirestoreService, StorageService, DetailingService, GalleryService, PartsService, WarrantyService | — | **NONE** | Merge-write + demo-mode branching, decode paths all unverified. |

### 1.3 Utilities & models

| Surface | Covered by | Coverage | Notes |
|---|---|---|---|
| AppleSignInNonce | AppleSignInNonceTests | **GOOD** | Length, charset, known SHA-256 digest — adequate for scope. |
| AsyncTimeout | AsyncTimeoutTests | **GOOD** | Both race outcomes covered. |
| AppError | AppErrorTests | **PARTIAL** | 2 of 6 domain mappings (URL, ASAuthorization); Firestore/Storage/FIRAuth mappings untested. |
| Validators | ValidatorTests | **PARTIAL** | 2 cases; negative/non-numeric/regressive-odometer branches untested. |
| FirestoreEntry / EntryType / AnyCodable | EntryDecodingTests | **PARTIAL** | JSON round-trip for one type; AnyCodable int-before-double order, nested structures untested. |
| ReportSection | ReportSectionTests | **PARTIAL** | Trivial `allCases` membership; no gating logic. |
| WearSnapshot / WearItemType | WearCalculationTests | **PARTIAL** | Misleading name — labels only, zero calculation math. |
| Constants / AppRuntime / FirestorePaths / StoragePaths | — | **NONE** | Path builders enforce per-user storage isolation by construction — worth locking with tests. |
| Formatters, AppLogger, Color/Date/Double/String/View extensions | — | **NONE** | Cosmetic; lowest priority. |
| All other data models (Vehicle, Reminder, SparePart, Warranty, Recall, GalleryPhoto, DetailingRecord, TireSet, UserProfile, Attachment, SyncQueueItem/DraftEntry, and the 12 entry payloads) | — | **NONE** | Plain Codable structs; risk concentrated in encode/decode via services, not the types themselves. |

### 1.4 Cloud Functions

| Surface | Covered by | Coverage | Notes |
|---|---|---|---|
| handleRevenueCatWebhook | — | **NONE** | **Most entitlement-sensitive code in the backend** — toggles `pro` on user records. Static shared-secret header, not RevenueCat HMAC verification. Misleading filename (`stripeWebhook.ts`). |
| parseOilAnalysis | — | **NONE** | Paid Anthropic call gated only by Firebase Auth — no `enforceAppCheck`, no rate limiting. Cost-abuse surface. |
| lookupRecalls | — | **NONE** | Public-API pass-through; least sensitive. |

---

## 2. Gaps ranked by risk (highest first)

| # | Gap | Risk class | Why |
|---|---|---|---|
| 1 | **handleRevenueCatWebhook** — zero tests | Payments/entitlements | Directly grants/revokes paid access; weak shared-secret auth (no HMAC); idempotency transaction unverified. Crosses the doctrine trust boundary (Law 5) with no coverage. |
| 2 | **AuthService** — zero direct tests; UI "auth flow" test is a stub | Auth | `uid` is the key every Firestore document is scoped by. A regression here is either total lockout or cross-user data exposure. |
| 3 | **VehicleService free-tier cap + PurchaseService.isPro** — zero tests | Payments/entitlements | The only client-side paywall-gated write. A regression silently gives away Pro or wrongly blocks paying users. Service is already injectable — cheapest high-value test in the repo. |
| 4 | **SyncService + SyncQueueItem** — zero tests | Data-loss | The offline durability guarantee ("failed items never silently dropped") is asserted only in comments. Flush failure-retention and status transitions must be unit-tested. |
| 5 | **EntryFormViewModel.save pipeline + EntryService writes** | Data-loss/integrity | Details→AnyCodable encoding, entry persist, and odometer pushback to Vehicle are the core write path of the product; only pre-validation is tested. |
| 6 | **CSVExportService** — zero tests, known escaping defect | Export correctness + security | Unquoted fields corrupt output; no formula-injection (`=`,`+`,`-`,`@`) sanitization — a spreadsheet-injection vector in a user-facing export. |
| 7 | **PDFExportService.shouldInclude** — zero tests | Export correctness | Resale-ready PDF is the headline paid feature; the EntryType→ReportSection mapping is pure and trivially testable. |
| 8 | **parseOilAnalysis** — no App Check, no rate limit, no tests | Security/cost | Any authenticated user can pump base64 blobs at a paid Anthropic endpoint. Contract test against OilAnalysisEntry shape needed on both client and function. |
| 9 | **ProfileViewModel silent non-persistence** | Data-loss (live product bug) | User-entered profile/insurance data is discarded — a test would have caught this; fix + test together. |
| 10 | **SecureStoreService** — stub test | Security | Keychain round-trip (save/read/delete, missing-key nil) unverified. |
| 11 | **AppIntegrityService provider selection** | Security/availability | Wrong provider in DEBUG bricks all backend calls; matrix is pure logic, easily tested. |
| 12 | **AppState.bootstrap / AppRouter** | Correctness | Vehicle auto-select, SeedData fallback, single-sheet state machine untested. |
| 13 | Dead code: **OilAnalysisViewModel** (unwired ClaudeService path) | Hygiene | Delete or wire it; untestable as-is. |
| 14 | lookupRecalls, Garage sub-screens, Stats charts, formatters/extensions | Cosmetic/low | Cover opportunistically. |

---

## 3. Required E2E (XCUITest) journeys

| # | Journey | Status |
|---|---|---|
| 1 | **Auth**: launch → login screen visible → Sign in with Apple / Google → main TabView shown; timeout error banner; sign-out returns to login | ⚠️ **AuthFlowTests exists but is a launch-only stub** — effectively MISSING |
| 2 | **Vehicle CRUD**: add vehicle (form validation), appears in list, switcher swaps active vehicle; second vehicle as free user → vehicleLimitReached → paywall | ❌ MISSING |
| 3 | **Entry CRUD**: FloatingAddButton → entry picker → create entry (at least oil change + fuel) → appears in Log and Dashboard recent feed → detail sheet shows details map; regressive-odometer rejection | ⚠️ **EntryCreationTests exists but is a launch-only stub** — effectively MISSING |
| 4 | **Log search & filter**: search text narrows results; type-filter sheet constrains list; empty state | ❌ MISSING |
| 5 | **Reminders**: non-Pro sees ProGateView; Pro creates reminder → appears on Dashboard upcoming section | ❌ MISSING |
| 6 | **Export**: Pro user sets date range + section toggles → builds PDF and CSV → non-zero byte size shown; non-Pro sees upsell | ❌ MISSING |
| 7 | **Paywall/purchase**: ProGate from Garage/Stats/Reminders/Export routes to subscription sheet → offerings listed → (sandbox/mocked) purchase flips isPro and unlocks gated tabs; restore purchases | ❌ MISSING |
| 8 | **Settings/profile**: edit profile fields and verify persistence across relaunch (currently fails — bug #9 above); sign out | ❌ MISSING |
| 9 | **Offline sync**: create entry offline → sync badge shows Offline → reconnect → flush → Up to date; failed flush shows Needs attention | ❌ MISSING |
| 10 | **Garage Pro screens**: gallery/wheel gallery render, add spare part, add detailing record, warranty/recall list with outstanding-recall highlight | ❌ MISSING |

**Net:** 2 of 10 required journeys have test files in name only; 0 of 10 have real coverage. Recommended first wave (aligns with risk ranking): unit tests for the RevenueCat webhook + VehicleService paywall gate + SyncService, then real XCUITests for journeys 1, 3, and 7.