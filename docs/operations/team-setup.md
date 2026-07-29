# Team Setup

## GitHub

1. Protect `main`.
2. Require pull requests before merge.
3. Require the `CI / functions` and `CI / ios` workflow checks from `.github/workflows/ios.yml`.
4. Add the repository admins and developers as collaborators before enabling required reviews.
5. Use `gh` (installed and used routinely from this workstation) or the GitHub web UI for branch protection.

## Firebase

1. Keep `harrys-playhouse-prod` on Blaze.
2. `harrys-playhouse-dev` is on Blaze (moved 2026-07-24; see `docs/DEPLOY_RUNBOOK.md`).
3. After development is on Blaze, create its default Storage bucket and deploy Storage rules.
4. Mirror the production function environment keys into `CloudFunctions/.env.harrys-playhouse-dev`.
5. Keep Firestore and Storage rules deployed from this repo only.

## Apple

1. Finalize the Apple Developer team used for signing.
2. Register Sign in with Apple in both Apple Developer and Firebase Auth.
3. Register the Apple Team ID with the Firebase iOS app so App Attest can be enforced.

## RevenueCat

1. Create the project and the `pro` entitlement.
2. Configure the iOS public SDK key in local `Configuration/Secrets.swift`.
3. Point the webhook to the deployed production function URL.
4. Set the webhook Authorization header to the production `REVENUECAT_WEBHOOK_AUTH` value.

## Local Development

1. Keep `Garage/Resources/GoogleService-Info.plist` local and out of Git.
2. Keep `Configuration/Secrets.swift` local and out of Git.
3. Keep `Configuration/Local.xcconfig` local and out of Git.
4. Keep `CloudFunctions/.env.local` and `CloudFunctions/.env.<projectId>` local and out of Git.
5. Run `./scripts/ci/verify-ios.sh` before opening a pull request.
