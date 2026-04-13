# Garage

Garage is a native iOS app for serious car owners who want a clean service log, resale-ready exports, and advanced ownership tracking without learning a complicated app.

## Blueprint Alignment

The product requirements in `blueprint.md` are treated as feature truth. Where the blueprint's delivery stack differs from this repository, the product detail is preserved and implemented on the locked native iOS architecture in this repo.

## Repo Layout

- `Garage/`: SwiftUI app source, design system, feature slices, and resources
- `CloudFunctions/`: Firebase Cloud Functions for Claude parsing, recall lookup, and entitlement plumbing
- `Configuration/`: xcconfigs, index definitions, and secret templates
- `Tests/`: Swift Testing unit coverage and critical UI flow scaffolding
- `docs/`: split documentation for developers, operators, and end users

## Toolchain

- Swift 6
- iOS 17+
- Xcode 16+
- XcodeGen for local project generation from `project.yml`
- Firebase CLI for rules, indexes, and functions deployment

Command Line Tools alone are not enough for this repository. A full Xcode.app installation is required for project generation, simulator builds, tests, archives, and Xcode Cloud parity.

## Local Start

1. Install Xcode and XcodeGen.
2. Copy `Configuration/Secrets.template.swift` to `Configuration/Secrets.swift` and populate real values.
3. Add `Garage/Resources/GoogleService-Info.plist`.
4. Run `xcodegen generate`.
5. Open `Garage.xcodeproj`.

## Verification

- `./scripts/ci/policy-checks.sh`
- `./scripts/ci/security-checks.sh`
- `./scripts/ci/verify-ios.sh`

See [developer setup](docs/developer/local-setup.md), [quality gates](docs/developer/quality/ios-quality-gates.md), [operations runbook](docs/operations/release-runbook.md), [security runbook](docs/operations/security/mobile-security-runbook.md), and [user guide](docs/user/getting-started.md).
