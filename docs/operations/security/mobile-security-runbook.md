# Mobile Security Runbook

## Baseline Controls

- Firebase App Check uses App Attest when available and DeviceCheck as fallback.
- Debug and CI builds can use the Firebase App Check debug provider when `FIRAAppCheckDebugToken` is present.
- App Transport Security is enforced.
- Cloud functions reject unauthenticated requests.
- RevenueCat webhooks require an explicit authorization header.
- Firestore and Storage access stay scoped to the signed-in user.
- Sensitive local material stays in Keychain-backed storage.

## Release Review

1. Confirm production App Check enforcement.
2. Confirm deny-by-default Firestore and user-scoped Storage rules.
3. Confirm no debug config, emulator config, or seed data is enabled in release.
4. Confirm App Store privacy disclosures match the shipped SDK set.
5. Confirm RevenueCat entitlements and webhook state agree.
