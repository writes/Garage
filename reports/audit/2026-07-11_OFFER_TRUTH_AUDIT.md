# iOS-0 Offer/Paywall Truth Audit — 2026-07-11

Work order for blueprint §5 Wave-1 item **iOS-0** (Sol blocker #4 disposition). Read-only
audit of branch `feature/profit-first-p0`; doctrine reference:
`docs/research/2026-07-11_PROFIT_FIRST_BLUEPRINT.md` §4 (Free = 1 vehicle, unlimited manual
entries, reminders, free complete raw CSV, 10 lifetime oil-analysis imports; Pro =
$4.99/mo·$34.99/yr, **up to 5 vehicles**, AI at disclosed 5/day fair-use, enhanced PDF).

| # | Claim (verbatim) | File:line | Backing surface | Status | Required action |
|---|---|---|---|---|---|
| 1 | "Unlimited vehicles" | `SubscriptionView.swift:35` | `VehicleService.validateVehicleLimit` (`VehicleService.swift:201-205`) always passes for `isPro`; no Pro cap constant exists; `firebase.firestore.rules:26` has zero count check for any tier | **GATED_CONTRADICTION** | Reword to "up to 5 vehicles"; add `Constants.maxProVehicles = 5` + client enforcement pending RULES-1 |
| 2 | "Free accounts are limited to 1 vehicle. Upgrade to Pro for unlimited." | `AppError.swift:30` | Same as #1 | **GATED_CONTRADICTION** | Reword: "…Upgrade to Pro for up to 5 vehicles." |
| 3 | "reminders" (Pro benefit) | `SubscriptionView.swift:35` | `ReminderConfigView.swift:12-19` gates the whole form behind Pro; `ReminderConfigViewModel.swift:27` hardcodes `isProFeature: true` (dead data — real gate is UI-only) | **GATED_CONTRADICTION** | Doctrine makes reminders FREE — un-gate for free users |
| 4 | "Reminders are part of Pro" | `ReminderConfigView.swift:14-15` | Same as #3 | **GATED_CONTRADICTION** | Remove the gate (highest-priority copy+gate fix) |
| 5 | "exports" (Pro benefit) | `SubscriptionView.swift:35` | `ExportView.swift:10-17` gates PDF + CSV wholesale | **GATED_CONTRADICTION** (CSV half) | Un-gate CSV (iOS-1); PDF stays Pro |
| 6 | "Exports are part of Pro" | `ExportView.swift:12` | Same as #5 | **GATED_CONTRADICTION** | Split messaging: CSV free, PDF Pro |
| 7 | "Generate buyer-ready PDF reports and full-fidelity CSV exports from one place." | `ExportView.swift:13` | PDF prints `"Vehicle History: Not connected"` (`PDFExportService.swift:26`), photos = heading only, receipts = text stub; CSV capped at 500 (`ExportViewModel.swift:54`) | **PLACEHOLDER** / **PARTIAL** | Suppress "buyer-ready" until iOS-7; fix CSV completeness in iOS-1 or reword |
| 8 | "attachments" (Pro benefit) | `SubscriptionView.swift:35` | `AttachmentPicker.swift:38-46` never reads bytes (synthetic filenames only); `StorageService.upload` has zero call sites | **PLACEHOLDER** | Suppress until iOS-5 ships |
| 9 | "AI oil analysis" (Pro benefit) | `SubscriptionView.swift:36` | `ClaudeService.swift:7-23` has zero call sites; `OilAnalysisFormView.swift` is pure manual entry — no import affordance | **UNWIRED** | Suppress until iOS-6L ships |
| 10 | "gallery" | `SubscriptionView.swift:35` | `GarageView.swift:23` → `PhotoGalleryView` (real) | **SHIPPED_REACHABLE** | None |
| 11 | "parts" | `SubscriptionView.swift:36` | `GarageView.swift:27` → `SparePartsView` | **SHIPPED_REACHABLE** | None |
| 12 | "detailing" | `SubscriptionView.swift:36` | `GarageView.swift:29` → `DetailingLogView` | **SHIPPED_REACHABLE** | None |
| 13 | "warranty, recalls" | `SubscriptionView.swift:36` | `GarageView.swift:31` → `WarrantyRecallView` | **SHIPPED_REACHABLE** | None |
| 14 | "full stats" | `SubscriptionView.swift:37` | `StatsView.swift:23-25` → three charts, backed by `StatsViewModel.load` | **SHIPPED_REACHABLE** | None |
| 15 | "Garage tools are part of Pro…" | `GarageView.swift:12-15` | Same as #10–13 | **SHIPPED_REACHABLE** | None |
| 16 | "Stats are a Pro feature…" | `StatsView.swift:14-15` | Same as #14 | **SHIPPED_REACHABLE** | None |
| 17 | RevenueCat package title/price strings | `SubscriptionView.swift:56-74` | Live from App Store Connect metadata — not in repo | **OUT OF SCOPE (operator)** | Verify ASC copy for "unlimited" language pre-submit; add "up to 5 vehicles" / "5/day AI fair-use" disclosure near the package list |

## Highest-risk contradictions (rank order)

1. **No Pro vehicle cap exists anywhere, client or server** (#1) — copy-truth violation AND
   the entitlement gap RULES-1 closes; the copy fix alone stops false advertising, not abuse.
2. **Reminders fully Pro-gated while doctrine defines them as Free** (#3, #4) — simplest fix.
3. **CSV export Pro-gated wholesale** (#5, #6) — free users currently get zero export.
4. **"AI oil analysis" marketed with zero reachable code path** (#9) — a paying Pro user
   cannot invoke the advertised feature at all.
5. **"Buyer-ready PDF" and "attachments" are placeholder-only** (#7, #8) — marketed as core
   Pro value today.

All map to scoped backlog items: iOS-0 copy/gate fixes now; RULES-1, iOS-1, iOS-5, iOS-6L,
iOS-7 for the underlying builds. Operator item: #17 (App Store Connect metadata).
