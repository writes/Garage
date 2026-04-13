# iOS Quality Gates

## Build Gates

- Warnings are treated as errors in all configurations.
- Strict concurrency stays enabled.
- Release builds validate products and strip dead code.
- Files stay under 300 lines and directories stay under 10 files.
- `./scripts/ci/verify-ios.sh` passes locally and in CI once Xcode is installed.
- `./scripts/ci/policy-checks.sh` passes before lint/build.

## Test Gates

- P0 logic tests pass before TestFlight.
- New feature work adds at least one focused unit test.
- Auth, odometer enforcement, paywall gating, export, and sync recovery remain release blockers.

## Security Gates

- Firebase App Check is configured before Firebase bootstrap.
- ATS stays enabled with no arbitrary loads.
- Sensitive local values use `SecureStoreService`.
- Firestore and Storage rules are deployed before distribution.
- Privacy disclosures and manifests are reviewed against the final SDK set before submission.
- `./scripts/ci/security-checks.sh` passes before release candidates.

## UI Automation Bootstrap

- UI tests run the app with the `UI_TEST_MODE` launch argument.
- In `UI_TEST_MODE`, the app skips Firebase, RevenueCat, and App Check bootstrapping and renders a local-only harness view.
- This keeps UI automation deterministic and prevents failures caused by missing cloud configuration or entitlement prompts in CI.
- Production boot remains unchanged. The bypass is only active when the explicit launch argument is present.

## Simulator Recovery

If `xcodebuild test` fails with a simulator preflight or busy error, reset the simulator lifecycle before retrying:

```bash
xcrun simctl shutdown all || true
xcrun simctl boot 'iPhone 17' || true
xcodebuild test -project Garage.xcodeproj -scheme Garage -destination 'platform=iOS Simulator,name=iPhone 17'
```

Use this only as a simulator recovery step. Do not treat it as a substitute for fixing deterministic test failures.
