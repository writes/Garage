# Developer Setup

## Prerequisites

- Xcode 16 or later with iOS 17 SDK
- XcodeGen
- Firebase CLI
- Node.js 20+
- Apple Developer account configured for Sign in with Apple
- Firebase project with Auth, Firestore, Storage, Analytics, Crashlytics, and Messaging enabled
- RevenueCat project with a `pro` entitlement

Full Xcode.app is required. Apple Command Line Tools are not sufficient for this repository.

## Bootstrapping

1. Copy `Configuration/Secrets.template.swift` to `Configuration/Secrets.swift`.
2. Add `Garage/Resources/GoogleService-Info.plist`.
3. Update the bundle identifier in `project.yml`.
4. Run `xcodegen generate`.
5. Open the generated Xcode project.
6. Add the required URL schemes for Google Sign-In in the Firebase console and Xcode.
7. Configure Apple Sign-In in the Apple Developer portal and Firebase Auth.

## Xcode Install Note

- Preferred path: App Store or Apple Developer downloads
- Required outcome: `xcodebuild -version` succeeds and `xcode-select -p` points at `Xcode.app`
- If only `/Library/Developer/CommandLineTools` is active, builds and tests will not work

## Local Configuration

- `Debug.xcconfig` points at development identifiers and enables debug-only seed data.
- `Release.xcconfig` is for production endpoints and hardened logging.
- `Configuration/Secrets.swift` stores compile-time secrets that must never be committed.
- `.firebaserc` defines the shared Firebase aliases: `dev -> harrys-playhouse-dev` and `prod -> harrys-playhouse-prod`.
- `CloudFunctions/.env.local` should hold local emulator secrets when needed.
- `Garage/Resources/PrivacyInfo.xcprivacy` should be reviewed before each release because third-party SDK manifests can change over time.
- `Garage/Resources/GoogleService-Info.plist` is copied into the app bundle by the generated Xcode project when the file exists locally. Keep it out of Git.

## Firebase Projects

- Development project: `harrys-playhouse-dev`
- Production project: `harrys-playhouse-prod`

Common alias commands:

- `firebase use dev`
- `firebase use prod`

Firestore rules and indexes are deployed from this repo to both projects. Storage buckets and Cloud Functions still require a linked billing account before they can be provisioned or deployed.

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

### Google Sign-In Build Behavior

When a local `Garage/Resources/GoogleService-Info.plist` is present, the generated Xcode project now does three things during the app build:

- copies the plist into the app bundle
- derives the Firebase Auth callback URL scheme from `GOOGLE_APP_ID`
- adds that callback scheme to the built `Info.plist`

That means the checked-in project can stay free of local Firebase plist values while the local Firebase Auth web flow still has the bundle metadata it needs at runtime.

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
