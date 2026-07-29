# iOS Quality Gates

## Build Gates

- Warnings are treated as errors in all configurations.
- Strict concurrency stays enabled.
- Release builds validate products and strip dead code.
- Files stay under 300 lines, machine-enforced by `scripts/ci/policy-checks.sh`. Keeping
  directories under ~10 files is a convention, not a CI-checked gate.
- `./scripts/ci/verify-ios.sh` passes locally and in CI once Xcode is installed.
- `./scripts/ci/policy-checks.sh` passes before lint/build.

## Test Gates

- P0 logic tests pass before TestFlight.
- New feature work adds at least one focused unit test.
- Auth, odometer enforcement, paywall gating, export, and sync recovery remain release blockers.

## Security Gates

- Firebase App Check is configured before Firebase bootstrap.
- ATS stays enabled with no arbitrary loads.
- `SecureStoreService` (Keychain wrapper) exists but currently has zero call sites and a
  placeholder service identifier — see the 2026-07-29 roadmap before relying on it.
- Firestore and Storage rules are deployed before distribution.
- Privacy disclosures and manifests are reviewed against the final SDK set before submission.
- `./scripts/ci/security-checks.sh` runs as the "Security checks" step of the `ios` job in
  `.github/workflows/ios.yml` (wired into the automated gate 2026-07-29), ahead of the Xcode
  toolchain setup.

## UI Automation Bootstrap

- The UI test suite (`Tests/UITests`) launches the app with the `LOCAL_DEMO_MODE` argument
  (optionally plus `UI_TEST_PRO`), which resolves to `BootstrapMode.localDemo` in
  `Garage/App/GarageApp.swift`. That path skips Firebase, RevenueCat, and App Check
  configuration and swaps in local-only service instances (`AuthService.localDemo`,
  `VehicleService`/`PurchaseService.uiTest`), rendering the real `ContentView`.
- A separate `UI_TEST_MODE` launch argument and `BootstrapMode.uiTest` (a distinct
  `UITestHarnessView()`) also exist in `GarageApp.swift`, but no file in `Tests/UITests` currently
  passes that argument — it is unused by the actual suite.
- Production boot remains unchanged; both non-production paths are only active when their
  explicit launch argument is present.

## Simulator Recovery

If `xcodebuild test` fails with a simulator preflight or busy error, reset the simulator lifecycle before retrying:

```bash
xcrun simctl shutdown all || true
xcrun simctl boot 'iPhone 17' || true
xcodebuild test -project Garage.xcodeproj -scheme Garage -destination 'platform=iOS Simulator,name=iPhone 17'
```

Use this only as a simulator recovery step. Do not treat it as a substitute for fixing deterministic test failures.
