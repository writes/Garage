# Developer Setup

## Prerequisites

- Xcode 16 or later with iOS 17 SDK
- XcodeGen
- Firebase CLI
- Node.js 22+
- Apple Developer account configured for Sign in with Apple
- Firebase project with Auth, Firestore, Storage, Analytics, Crashlytics, and Messaging enabled
- RevenueCat project with a `pro` entitlement

Full Xcode.app is required. Apple Command Line Tools are not sufficient for this repository.

## Bootstrapping

1. Copy `Configuration/Secrets.template.swift` to `Configuration/Secrets.swift`.
2. Copy `Configuration/Local.template.xcconfig` to `Configuration/Local.xcconfig`.
3. Add your Apple Developer Team ID to `Configuration/Local.xcconfig`.
4. Add `Garage/Resources/GoogleService-Info.plist`.
5. Update the bundle identifier in `project.yml`.
6. Run `xcodegen generate`.
7. Open the generated Xcode project.
8. Add the required URL schemes for Google Sign-In in the Firebase console and Xcode.
9. Configure Apple Sign-In in the Apple Developer portal and Firebase Auth.

## Xcode Install Note

- Preferred path: App Store or Apple Developer downloads
- Required outcome: `xcodebuild -version` succeeds and `xcode-select -p` points at `Xcode.app`
- If only `/Library/Developer/CommandLineTools` is active, builds and tests will not work

## Local Configuration

- `Debug.xcconfig` points at development identifiers and enables debug-only seed data.
- `Release.xcconfig` is for production endpoints and hardened logging.
- `Configuration/Secrets.swift` stores compile-time secrets that must never be committed.
- `Configuration/Local.xcconfig` stores local signing overrides such as `DEVELOPMENT_TEAM` and should never be committed.
- `.firebaserc` defines the shared Firebase aliases: `dev -> harrys-playhouse-dev` and `prod -> harrys-playhouse-prod`.
- `CloudFunctions/.env.local` should hold local emulator secrets when needed.
- `CloudFunctions/.env.<projectId>` should hold deploy-time function environment variables when needed.
- `CloudFunctions/.env.example` documents the expected function environment keys.
- `Garage/Resources/PrivacyInfo.xcprivacy` should be reviewed before each release because third-party SDK manifests can change over time.
- `Garage/Resources/GoogleService-Info.plist` is copied into the app bundle by the generated Xcode project when the file exists locally. Keep it out of Git.
- Debug builds intentionally use `GarageDebug.entitlements`, which keeps Sign in with Apple but omits push entitlements so local simulator and device installs are easier to provision. Release builds continue to use `Garage.entitlements`.

## Firebase Projects

- Development project: `harrys-playhouse-dev`
- Production project: `harrys-playhouse-prod`

Common alias commands:

- `firebase use dev`
- `firebase use prod`

Current state as of 2026-07-29:

- Firestore rules and indexes are deployed to both projects.
- Both projects are on Blaze billing (`harrys-playhouse-dev` moved off Spark on 2026-07-24; see
  `docs/DEPLOY_RUNBOOK.md`).
- Production has a default Storage bucket: `harrys-playhouse-prod.firebasestorage.app`.
- Production Storage rules are deployed.
- Cloud Functions are deployed to both projects — verified live via `firebase functions:list`:
  `deleteAccount`, `deleteVehicle`, `enforceAttachmentProGate`, `handleRevenueCatWebhook`,
  `lookupRecalls`, `parseOilAnalysis`, `recomputeVehicleOdometer`, `voiceQuickAdd`.
  `receiptQuickAdd` is code-complete but not yet deployed to either project (see
  `docs/GARAGE_MASTER_PLAN.md`).

## Authentication Providers

The login screen is wired for Firebase Authentication with Apple and Google.

Provider setup still has two manual parts:

1. Firebase Console
2. Apple Developer

### Firebase Console

For both `harrys-playhouse-dev` and `harrys-playhouse-prod`:

- Open Authentication.
- Enable the Google provider.
- Enable the Apple provider.

The Apple provider needs the following values:

- Apple Team ID
- Apple Key ID
- Apple private key (`.p8`)
- Apple Services ID

Firebase OAuth handler URLs:

- Development: `https://harrys-playhouse-dev.firebaseapp.com/__/auth/handler`
- Production: `https://harrys-playhouse-prod.firebaseapp.com/__/auth/handler`

### Apple Developer

For Apple Sign-In:

- Keep Sign in with Apple enabled for the iOS App IDs:
  - `com.writes.harrysplayhouse.debug`
  - `com.writes.harrysplayhouse`
- Create Apple Services IDs for the Firebase OAuth callback flow.
- Allow the matching Firebase handler URL for each environment.
- Create an Apple Sign-In private key and record the Team ID and Key ID for Firebase.

### Apple Sign-In On Simulator

If Apple login stalls on the simulator:

- Create `Configuration/Local.xcconfig` from the template and set `DEVELOPMENT_TEAM` to the Apple team that owns the app IDs.
- Sign into an Apple ID inside the Simulator Settings app.
- Confirm `com.writes.harrysplayhouse.debug` is enabled for Sign in with Apple in both Apple Developer and Firebase Auth.
- Rebuild after any entitlement or signing change so the simulator picks up the updated capability set.

### Google Sign-In Build Behavior

Google login uses the native Google Sign-In SDK and then exchanges the returned Google tokens for a Firebase credential.

The local `Garage/Resources/GoogleService-Info.plist` must include:

- `CLIENT_ID`
- `REVERSED_CLIENT_ID`
- `GOOGLE_APP_ID`

If `CLIENT_ID` or `REVERSED_CLIENT_ID` is missing, enable the Google provider for the Firebase project, confirm the iOS app uses `com.writes.harrysplayhouse.debug`, then redownload `GoogleService-Info.plist` from the Firebase iOS app settings.

When a valid local plist is present, the generated Xcode project does these things during the app build:

- copies the plist into the app bundle
- derives the Firebase Auth callback URL scheme from `GOOGLE_APP_ID`
- adds the Firebase callback scheme and Google reversed client ID scheme to the built `Info.plist`
- adds `GIDClientID` to the built `Info.plist`

That means the checked-in project can stay free of local Firebase plist values while the native Google Sign-In flow still has the bundle metadata it needs at runtime.

## Cloud Functions

Production Cloud Functions are deployed from `CloudFunctions/`.

Expected environment keys:

- `ANTHROPIC_API_KEY`
- `REVENUECAT_WEBHOOK_AUTH`

How the repo uses them:

- `CloudFunctions/.env.local` for emulator-only values
- `CloudFunctions/.env.harrys-playhouse-prod` for production deploy values
- `CloudFunctions/.env.harrys-playhouse-dev` for development deploy values once development is on Blaze

Current production status:

- `handleRevenueCatWebhook` is configured with a private authorization header value at deploy time.
- `lookupRecalls` and `parseOilAnalysis` are deployed in `us-central1`.
- `parseOilAnalysis` still needs `ANTHROPIC_API_KEY` populated before it will return live results.

Local commands:

- `cd CloudFunctions && npm ci`
- `cd CloudFunctions && npm run build`
- `firebase emulators:start --only functions`

Deploy commands:

- `firebase deploy --only functions --project harrys-playhouse-prod`
- `firebase deploy --only functions --project harrys-playhouse-dev`

The development deploy command will continue to fail until development is upgraded to Blaze.

## RevenueCat

The backend webhook endpoint is:

- `https://us-central1-harrys-playhouse-prod.cloudfunctions.net/handleRevenueCatWebhook`

RevenueCat dashboard work still required:

1. Create the project and the `pro` entitlement.
2. Point the webhook at the function URL above.
3. Set the webhook Authorization header to the same value stored in `REVENUECAT_WEBHOOK_AUTH` for production.
4. Configure the iOS public SDK key in `Configuration/Secrets.swift`.

The webhook handler now rejects requests without the expected authorization header and ignores duplicate events by event ID.

## App Check

Debug builds now use the App Check debug provider automatically:

- on the iOS simulator
- or when `FIRAAppCheckDebugToken` is present in the environment

To register a local debug token:

1. Add `-FIRDebugEnabled` to the scheme launch arguments.
2. Launch the app once.
3. Copy the logged App Check debug token.
4. Register it in Firebase Console > App Check > your iOS app > Manage debug tokens.

Production App Check still has one manual dependency: the Firebase iOS app must have the Apple Team ID registered for App Attest. That value is not stored in this repo, so final App Check enforcement should stay off until Apple developer ownership is finalized.

## Daily Workflow

1. Implement work in phase order.
2. Keep files under 300 lines and folders under 10 files.
3. Add a unit test with each feature change.
4. Keep all Firebase imports inside `Services/`.
5. Run SwiftLint and the test targets before shipping.
6. Keep App Check, ATS, privacy disclosures, and deployed Firebase rules aligned with production.

## Deployment Commands

- Firestore rules and indexes: `firebase deploy --only firestore`
- Storage rules: `firebase deploy --only storage`
- Functions: `firebase deploy --only functions`

The checked-in CI workflow that runs these repo quality gates lives at `.github/workflows/ios.yml`.

## UI Test Mode

The UI test target launches the app with `UI_TEST_MODE`.

What this does:
- skips Firebase bootstrap
- skips RevenueCat bootstrap
- skips App Check bootstrap
- uses local-only service instances for auth, vehicles, and purchases
- renders a simple harness view so launch and flow smoke tests are stable in CI

This mode exists only for UI automation. Do not use it for manual product verification.

## Simulator Reset

When the simulator reports `Application failed preflight checks` or `Busy`, recover with:

```bash
xcrun simctl shutdown all || true
xcrun simctl boot 'iPhone 17' || true
```

Then rerun the test command.

## Missing Firebase Config Behavior

If `GoogleService-Info.plist` is not bundled into the app target, Garage now opens to a setup-required screen instead of aborting during `FirebaseApp.configure()`.

This is intentional for local development. It keeps the app launchable while making the missing setup step explicit.
