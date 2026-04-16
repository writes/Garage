# Operations Runbook

## Environment Ownership

- Firebase handles auth, database, storage, messaging, analytics, and crashes.
- RevenueCat owns subscription products and entitlements.
- Xcode Cloud handles CI, archive, and TestFlight delivery.

## Release Checklist

1. Confirm Firestore and Storage rules are deployed.
2. Confirm indexes match `Configuration/FirestoreIndexes.json`.
3. Verify RevenueCat offerings map to the `pro` entitlement.
4. Verify the RevenueCat webhook Authorization header matches `REVENUECAT_WEBHOOK_AUTH` in the deployed functions environment.
4. Confirm `paywall_view`, `purchase`, `first_entry`, `login`, and `sign_up` analytics events are visible.
5. Force a test Crashlytics crash in a non-production build.
6. Validate export, reminders, gallery, and stats are Pro-gated before entry.
7. Validate one-vehicle limit on free accounts.
8. Validate App Check is enabled for production services.
9. Validate App Store privacy disclosures and the in-repo privacy manifest against the shipping SDK set.


## Incident Handling

- Auth failures: verify Firebase Auth provider status, Apple key validity, and Google client IDs.
- Subscription failures: check RevenueCat customer info, webhook delivery, webhook auth header, and App Store product readiness.
- Sync failures: inspect local queue records, Firestore write errors, and connectivity state.
- Claude parsing failures: inspect the callable function logs and Anthropic API key rotation.

## Required Production Views

- Firebase console dashboards for Auth, Firestore usage, Storage usage, and Crashlytics
- RevenueCat entitlement and webhook health
- Xcode Cloud workflow health
