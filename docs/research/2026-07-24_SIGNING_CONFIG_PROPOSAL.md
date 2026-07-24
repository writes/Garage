# Signing configuration — PROTECTED-surface change proposal (operator gate)

**Date:** 2026-07-24 · **Author:** claude-opus-5 · **Status:** PROPOSED — not applied
**Surface:** `project.yml` (PROTECTED — "source of truth for targets/signing/bundle IDs")
**Blocks:** every signed TestFlight/App Store build

## Why this cannot be worked around

Three approaches were tried against real builds. All three fail, and the failure modes are
worth recording because two of them look like success.

1. **Manual signing via xcodebuild CLI overrides** —
   `CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER=... archive`
   → **ARCHIVE FAILED.** Command-line build settings apply to *every* target in the build,
   including the SPM package targets. ~25 errors of the form
   `Firebase_FirebaseAuth does not support provisioning profiles ... but provisioning profile
   Garage App Store has been manually specified`. Also hit GoogleUtilities, gRPC, RevenueCat,
   leveldb, abseil, promises, GTMAppAuth.

2. **Automatic signing driven by the ASC API key** —
   `-allowProvisioningUpdates -authenticationKeyPath/-ID/-IssuerID`
   → **ARCHIVE FAILED.** Xcode resolved the *development* lane, not distribution:
   `Your team has no devices from which to generate a provisioning profile` and
   `No profiles for 'com.writes.harrysplayhouse' were found: Xcode couldn't find any iOS App
   Development provisioning profiles`. There is no signing configuration in the project to tell
   it otherwise — `Configuration/Release.xcconfig` and `Debug.xcconfig` contain **no**
   `CODE_SIGN_*`, `PROVISIONING_*` or `DEVELOPMENT_TEAM` keys at all.

3. **Archive unsigned, sign at export time** (what `verify-ios.sh` already produces, then
   `xcodebuild -exportArchive` with `signingStyle: manual`)
   → **EXPORT SUCCEEDED — and this is the dangerous one.** It produces a correctly signed
   15.9 MB IPA: `Authority=iPhone Distribution: Jonathon Thompson (V32WV64X82)`, full chain to
   Apple Root CA, `get-task-allow=false`. But because an unsigned archive carries no
   entitlements, `exportArchive` synthesises only the minimum from the profile. Verified on the
   resulting binary with `codesign -d --entitlements`:

   | entitlement | in `Garage.entitlements` | in exported IPA |
   |---|---|---|
   | `application-identifier` | — | ✅ present |
   | `get-task-allow` | — | ✅ false |
   | `aps-environment` | `production` | ❌ **missing** |
   | `com.apple.developer.applesignin` | `Default` | ❌ **missing** |

   Sign In with Apple is a primary auth path. That IPA installs and then cannot log anyone in,
   with no build-time error anywhere. Do not ship via this route.

## The change

Add app-target-scoped signing to `project.yml` under `targets.Garage.settings.configs.Release`
(alongside the existing `CODE_SIGN_ENTITLEMENTS` / `PRODUCT_BUNDLE_IDENTIFIER` keys). Scoping it
to the target is the whole point — it is what keeps the setting off the SPM package targets that
failure mode 1 tripped over.

```yaml
        Release:
          CODE_SIGN_ENTITLEMENTS: Garage.entitlements
          PRODUCT_BUNDLE_IDENTIFIER: com.writes.harrysplayhouse
          # --- added: signing for TestFlight / App Store distribution ---
          CODE_SIGN_STYLE: Manual
          DEVELOPMENT_TEAM: V32WV64X82
          CODE_SIGN_IDENTITY: iPhone Distribution
          PROVISIONING_PROFILE_SPECIFIER: Garage App Store
          # --- end added ---
          SWIFT_COMPILATION_MODE: wholemodule
```

Notes on each value, since they are easy to get subtly wrong:

- `CODE_SIGN_IDENTITY: iPhone Distribution` — **not** `Apple Distribution`. The certificate
  created for this team is type `IOS_DISTRIBUTION`, whose common name is
  `iPhone Distribution: Jonathon Thompson (V32WV64X82)`. xcodebuild matches on a CN prefix, so
  `Apple Distribution` would not match. (The newer `DISTRIBUTION` cert type produces the
  `Apple Distribution` CN — if the cert is ever reissued as that type, this value must change.)
- `PROVISIONING_PROFILE_SPECIFIER: Garage App Store` — profile `FMHF5C6B3M`, `IOS_APP_STORE`,
  ACTIVE, expires 2027-07-24, installed at
  `~/Library/MobileDevice/Provisioning Profiles/67912437-1f70-4aaf-b342-6f94f2a89796.mobileprovision`.
- `DEVELOPMENT_TEAM: V32WV64X82` — not a secret; the team ID is embedded in every signed app.

## Does this break the CI gate?

No. `scripts/ci/verify-ios.sh` archives with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM=""` as **command-line** overrides, and command-line
settings take precedence over target settings. The gate keeps producing its unsigned archive and
stays green. The regenerate-equality gate will require `xcodegen generate` + committing the
refreshed `Garage.xcodeproj/project.pbxproj` in the same commit.

## Alternative considered and rejected

Putting the same keys in `Configuration/Release.xcconfig` works technically and is **not** a
protected file — the xcconfig applies to `Garage.xcodeproj`'s targets only, so it dodges the SPM
problem too. It was rejected because the doctrine names `project.yml` as the source of truth for
signing specifically; routing signing through the xcconfig to avoid the protection would defeat
the guardrail rather than satisfy it. Raised here so the choice is explicit rather than silent.

## After approval

1. Apply the block above to `project.yml`.
2. `xcodegen generate` and commit the regenerated `Garage.xcodeproj/project.pbxproj`.
3. `scripts/release/testflight_build.sh --team-id V32WV64X82 --profile "Garage App Store"` —
   its preflight will still (correctly) block on the `GoogleService-Info.plist` bundle-ID
   mismatch until a Firebase iOS app exists for `com.writes.harrysplayhouse`.
4. Upload needs the ASC **app record**, which has no API and must be created in the web UI.
