# Garage for Android — architecture spec (build contract)

Kotlin port of the Garage iOS app (`../Garage/`). Same product, same backend contract
(Firebase project layout, Firestore paths, callable names, RevenueCat entitlement), Android idioms.
The iOS sources are the reference for behaviour; port what matters, don't transliterate.

## Hard requirements
1. **Runs locally with zero credentials.** With no `app/google-services.json` and no RevenueCat key,
   the app boots into **Demo mode**: in-memory repositories seeded with sample data
   (port of `Garage/App/SeedData*.swift`), fake auth ("Continue in demo"), fake purchases, fake AI
   (deterministic canned proposals). `./gradlew :app:assembleDebug` and `./gradlew test` must pass
   on a clean checkout with only JDK 17+/21 and the Android SDK.
2. **Live mode** when `app/google-services.json` exists: the Gradle build applies the
   `com.google.gms.google-services` plugin **only if that file exists** (check in
   `app/build.gradle.kts`). `BuildConfig.FIREBASE_CONFIGURED` / `BuildConfig.REVENUECAT_API_KEY`
   (read from `local.properties` key `revenuecat.apiKey`, default "") select the backend at runtime.
3. Never commit secrets. `.gitignore` covers `google-services.json`, `local.properties`, `build/`,
   `.gradle/`, `*.keystore`.

## Toolchain / build
- Root project in `android/` (self-contained Gradle build, its own wrapper, `settings.gradle.kts`).
- Gradle wrapper 8.x, AGP 8.x, Kotlin 2.x with Compose compiler plugin, version catalog
  `gradle/libs.versions.toml`. compileSdk/targetSdk 35, minSdk 26. JVM target 17.
- Single module `:app`, package / applicationId `com.writes.garage` (debug suffix `.debug`).
- Libraries: Jetpack Compose (BOM) + Material 3, Navigation Compose, Lifecycle ViewModel Compose,
  kotlinx-coroutines, kotlinx-serialization-json, Firebase BOM (auth, firestore, storage, functions,
  appcheck-playintegrity + appcheck-debug, crashlytics, messaging), Credential Manager +
  `googleid` for Google Sign-In, RevenueCat `purchases`. Tests: JUnit4, kotlinx-coroutines-test.
  No Hilt/KSP/kapt — manual DI via `AppContainer` (keeps the build fast and simple).
- Android PDF export uses `android.graphics.pdf.PdfDocument`; CSV via plain Kotlin.

## Package layout (`app/src/main/java/com/writes/garage/`)
```
GarageApplication.kt        builds AppContainer (Demo or Firebase)
MainActivity.kt             setContent { GarageApp() }
di/AppContainer.kt          interface + DemoAppContainer + FirebaseAppContainer
core/model/                 Vehicle, Entry(+EntryType, details map), Reminder, UserProfile,
                            Subscription/Entitlement, ReceiptProposal, VoiceProposal, Recall, etc.
core/data/                  repository INTERFACES: AuthRepository, VehicleRepository,
                            EntryRepository, ReminderRepository, StorageRepository,
                            FunctionsGateway (callables), PurchaseRepository, AnalyticsSink
core/data/demo/             in-memory impls + SeedData
core/data/firebase/         Firestore/Auth/Storage/Functions/AppCheck/Crashlytics/Messaging impls
core/data/revenuecat/       RevenueCat PurchaseRepository
core/domain/                pure Kotlin logic (unit-tested): OwnershipCostCalculator,
                            FuelEconomy, MaintenanceSchedule/next-due, VehicleLimitPolicy
                            (free 1 / pro 5), Validators, Formatters
core/export/                CsvExporter, PdfExporter (dossier), IcsBuilder
ui/theme/                   Material3 theme (dark-first, automotive accent)
ui/navigation/              GarageNavHost, bottom bar: Dashboard, Log, Garage, Stats, Settings
feature/auth/               Sign-in screen (Google via Credential Manager in live; demo button)
feature/dashboard/          active vehicle summary, recent entries, upcoming reminders
feature/log/                searchable/filterable entry list, entry detail
feature/entry/              add/edit entry form (type picker, per-type detail fields)
feature/garage/             vehicles list, add/edit vehicle (limit enforced), vehicle switcher, recalls
feature/stats/              cost of ownership, cost by type, fuel economy, simple Compose charts
feature/receipt/            capture/pick image -> upload -> receiptQuickAdd -> proposal review -> confirmReceiptScan
feature/voice/              speech (SpeechRecognizer) -> voiceQuickAdd -> proposal review
feature/handover/           export PDF dossier / CSV, share via FileProvider
feature/settings/           account, subscription/paywall, AI consent, delete account, privacy/terms links
feature/shared/             ProGate, VehicleSwitcher, empty states, AIConsent dialog
```

## Backend contract (must match iOS / CloudFunctions)
- Firestore: `users/{uid}` (profile; `subscription` map is server-written, read-only to client;
  `vehicleCount` server-authoritative), `vehicles/{vehicleId}` (field `userId` = owner; soft delete
  via `deletedAt`, never hard-delete client-side), subcollections under `vehicles/{id}/`:
  `entries`, `reminders`, `attachments`, `gallery`, `parts_inventory`, `warranties`, `wear_snapshots`.
- Entry doc fields: id, vehicleId, userId, entryType (snake_case enum: oil_change, oil_consumption,
  oil_analysis, fuel, tire, brake, alignment, maintenance, repair, track_day, upgrade, dme_report),
  entryDate, odometerReading, cost, isDiy, shopName, notes, attachmentPaths, isResolved, details (map),
  createdAt, updatedAt.
- Vehicle fields: as `Garage/Core/Models/Profile/Vehicle.swift` (fuelType: regular_87, premium_91,
  premium_93, e85, diesel).
- Callables (Firebase Functions, default region): `receiptQuickAdd`, `confirmReceiptScan {token}`,
  `receiptQuotaStatus`, `reconcileReceiptCreditPurchase`, `voiceQuickAdd`, `parseOilAnalysis`,
  `lookupRecalls`, `experimentConfig`, `deleteAccount`, `deleteVehicle`. Read the matching
  `CloudFunctions/src/functions/*.ts` for request/response shapes.
- Vehicle creation in live mode must be the counted batch (vehicle create + `users/{uid}`
  vehicleCount+1 + lastVehicleOp) — see `Garage/Core/Services/Domain/VehicleService+CountedCreate.swift`
  and `firebase.firestore.rules`.
- RevenueCat entitlement id and product ids: see `Garage/Core/Utilities/Constants.swift`.
- AI features require explicit AI consent (port `AIConsentGate`); nothing writes until the user confirms
  a proposal.

## Quality
- ViewModels expose `StateFlow<UiState>`; screens are stateless composables + ViewModel.
- Unit tests under `app/src/test/` for core/domain, export, demo repositories, and ViewModels.
- `scripts/android-verify.sh` (in `android/`): `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`.
