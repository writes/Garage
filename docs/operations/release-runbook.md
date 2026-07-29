# Operations Runbook

## Environment Ownership

- Firebase handles auth, database, storage, messaging, analytics, and crashes.
- RevenueCat owns subscription products and entitlements.
- GitHub Actions (`.github/workflows/ios.yml`) runs CI: a pull-request-triggered gate (there is
  deliberately no `push: main` trigger) that runs `scripts/ci/security-checks.sh` and
  `scripts/ci/verify-ios.sh` (policy checks, build, tests, Release archive). Archive and
  TestFlight delivery are local, operator-run scripts: `scripts/release/testflight_build.sh`
  (`xcodebuild archive` + `-exportArchive`) followed by `scripts/release/asc.py upload`
  (`xcrun altool --upload-app` against an App Store Connect API key).

## Release Checklist

1. Confirm Firestore and Storage rules are deployed.
2. Confirm indexes match `Configuration/FirestoreIndexes.json`.
3. Verify RevenueCat offerings map to the `pro` entitlement.
4. Verify the RevenueCat webhook Authorization header matches `REVENUECAT_WEBHOOK_AUTH` in the deployed functions environment.
5. Confirm `paywall_viewed`, `purchase_completed`, `first_entry_added`, and `sign_in_started`/`sign_in_completed` analytics events are visible (frozen names: `docs/developer/ANALYTICS_CONTRACT.md`).
6. Force a test Crashlytics crash in a non-production build.
7. Validate export, gallery, and stats are Pro-gated before entry.
8. Validate one-vehicle limit on free accounts.
9. Validate App Check is enabled for production services.
10. Validate App Store privacy disclosures and the in-repo privacy manifest against the shipping SDK set.


## Incident Handling

- Auth failures: verify Firebase Auth provider status, Apple key validity, and Google client IDs.
- Subscription failures: check RevenueCat customer info, webhook delivery, webhook auth header, and App Store product readiness.
- Sync failures: inspect local queue records, Firestore write errors, and connectivity state.
- Claude parsing failures: inspect the callable function logs and Anthropic API key rotation.

## Required Production Views

- Firebase console dashboards for Auth, Firestore usage, Storage usage, and Crashlytics
- RevenueCat entitlement and webhook health
- GitHub Actions workflow health (`.github/workflows/ios.yml`)
