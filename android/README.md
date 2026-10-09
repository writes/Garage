# Garage for Android (Kotlin)

A native Kotlin / Jetpack Compose port of the Garage iOS app. It has the same product and the same
backend contract (Firestore paths, Storage paths, callable Cloud Functions, RevenueCat entitlement).
It runs **fully locally with no credentials**: with no Firebase config it boots into Demo mode, with
in-memory seeded data, fake auth, fake purchases and deterministic AI proposals.

Build contract and architecture: [docs/ARCHITECTURE_SPEC.md](docs/ARCHITECTURE_SPEC.md).

## Stack

- Kotlin 2.1, Jetpack Compose (Material 3), Navigation Compose, coroutines/Flow, kotlinx-serialization
- AGP 8.7, Gradle 8.9 wrapper, compileSdk/targetSdk 35, minSdk 26, JVM 17
- Firebase: Auth (Google via Credential Manager), Firestore, Storage, Functions, App Check
  (Play Integrity / debug provider), Crashlytics, Analytics, Messaging
- RevenueCat (Pro subscription plus the receipt-credit consumable)
- Manual DI (`di/AppContainer.kt`): `DemoAppContainer` or `FirebaseAppContainer`, no annotation processing

## Run it locally (no accounts needed)

Prerequisites: JDK 17+ and the Android SDK (platform 35). On macOS:

```bash
brew install openjdk@21 && brew install --cask android-commandlinetools
sdkmanager "platforms;android-35" "build-tools;35.0.0" "platform-tools"
# optional emulator:
sdkmanager "emulator" "system-images;android-35;google_apis;arm64-v8a"
avdmanager create avd -n garage35 -k "system-images;android-35;google_apis;arm64-v8a" -d pixel_7
```

Then:

```bash
cd android
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties
./gradlew :app:assembleDebug            # builds app/build/outputs/apk/debug/app-debug.apk
./gradlew :app:installDebug             # with an emulator/device attached
./scripts/android-verify.sh             # gate: assemble + unit tests + lint (abortOnError)
```

Android Studio also works: open the `android/` folder.

## Live mode (your own Firebase project)

1. Add an Android app to your Firebase project. Use package `com.writes.garage` (and
   `com.writes.garage.debug` for debug builds). Save `google-services.json` to `android/app/`
   (it is gitignored). The Gradle build applies the google-services/Crashlytics plugins **only
   when this file exists**.
2. Enable Google sign-in. The web client id comes from `google-services.json` (`default_web_client_id`).
3. Optional RevenueCat: add `revenuecat.apiKey=goog_…` to `local.properties`. Without it, live mode
   reads Pro from the server-written `users/{uid}.subscription` map, and purchases are unavailable.
4. Debug App Check: register the debug token printed in logcat in the Firebase console.
5. Deploy the shared backend from the repo root (`CloudFunctions/`, `firebase.*.rules`). Android and
   iOS use the same functions and rules.

## Feature parity with iOS

| Area | Android |
|---|---|
| Auth | Google sign-in (Apple sign-in is iOS-only); Demo mode button |
| Dashboard | Active vehicle, odometer, quick actions, recent entries, reminders, maintenance due, warranty/recall badges, wear and tire-age advisories |
| Log | Search, type filter, month grouping, detail, edit/delete, attachments |
| Entries | All 12 entry types with per-type fields that iOS can decode, validation, odometer bounds, fuel MPG |
| Garage | Vehicles (counted create, free 1 / Pro 5 limit, soft delete + `deleteVehicle`), owner profile, recalls (NHTSA, with do-not-drive/park-outside banners), warranties, spare parts, detailing, photo and wheel gallery, wear tracking (Pro-gated as on iOS) |
| AI capture | Receipt scan (quota, credits purchase with identity guard, proposal review, confirm-before-write), voice quick-add (Pro), oil-analysis PDF import; all gated on AI consent |
| Stats | Ownership cost, cost by type, fuel economy, track-day summary (Pro) |
| Handover | PDF dossier (Pro), CSV and ICS export, shared via FileProvider |
| Settings | Account, subscription/paywall/restore, AI and analytics consent, notifications, accent theme, review prompt, delete account, privacy/terms |
| Reminders | Create/edit/delete/complete with repeat, local notifications (AlarmManager, re-armed on boot), calendar export |

**Not ported:** the iOS A/B experiment arms and design survey (`experimentConfig` is wired in the
gateway, but no Android UI variants exist).

## Security posture

- Crashlytics and Analytics collection are **off until the user consents** (manifest opt-out,
  driven by `analyticsOptOut`).
- No secrets in source. `google-services.json` and `local.properties` are gitignored.
- Backups and device transfer exclude auth/cache data. Only the launcher activity and the boot receiver (a system-protected broadcast) are exported, the
  FileProvider is scoped to the export and capture cache dirs, and PendingIntents are immutable.
- Sign-out and account deletion wipe the Firestore cache, exports, prefs and alarms.
- Image uploads are downscaled with EXIF/GPS metadata stripped and size-bounded. Attachments upload
  only for Pro users, matching the `enforceAttachmentProGate` trigger.
- Release builds use R8 with keep rules for Firebase, RevenueCat and serialization.

## Tests

537 JVM unit tests (`app/src/test`) cover domain logic, exporters (CSV/ICS/PDF content), Firestore and
callable mappers, demo repositories, every ViewModel (including failure paths and entitlement gates),
reminder/alarm planning and purchase flows. Instrumented UI tests are not included yet.

## Known limitations

- Not yet exercised against a live Firebase project or on a physical device. Demo mode was
  smoke-tested on the Android emulator.
- Server-side: `firebase.storage.rules` allows owner uploads under `users/{uid}/vehicles/...`
  (gallery/parts/warranty documents) without a Pro check. The clients gate these surfaces, but a
  storage-rule or trigger change is an operator decision and is not part of this port.
- Play Billing product ids (`subscriptionId:basePlanId`) must be created in Play Console and mapped
  in RevenueCat before purchases work in live mode.
