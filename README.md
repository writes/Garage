# Garage

Garage is a native iOS app (with a Kotlin/Android port in [`android/`](android/README.md)) for serious car owners: a clean service log, receipt and voice capture,
resale-ready exports, and ownership tracking (maintenance, track days, oil analysis, parts,
warranties, recalls). It is backed by Firebase and a set of TypeScript Cloud Functions that call
Claude for document understanding.

> **Public snapshot (2026-10-07).** This is a public copy of the private development repo,
> published with its **full commit history** (476 commits, 34 branches) so the end-to-end build,
> test, release and operations setup can be assessed. See
> [Public snapshot notes](#public-snapshot-notes) for exactly what was changed.

---

## At a glance

| Area | What is here |
|---|---|
| iOS app | SwiftUI, Swift 6, iOS 17+: 285 Swift files (~27k lines) under `Garage/`, organized App → Core → Design → Features |
| Android app | Kotlin + Jetpack Compose port in `android/` (146 Kotlin files, ~14k lines, 537 unit tests): same Firebase/RevenueCat/Cloud Functions contract, runs locally in Demo mode with no credentials |
| Feature slices | Auth, Dashboard, Log, EntryForms, Garage, Stats, Receipt, Voice, Handover, Settings, Shared |
| Backend | Firebase Auth (Sign in with Apple / Google), Firestore (persistent offline cache), Storage, App Check (App Attest), Crashlytics, Messaging |
| Cloud Functions | 18 TypeScript source files (~5.8k lines), 13 deployed functions (listed below), Node 22 |
| AI features | Receipt and invoice extraction, voice quick-add, oil-analysis parsing (Claude, called server-side only) |
| Monetization | RevenueCat subscriptions plus consumable receipt-scan top-ups, synced through a webhook |
| Tests | 175 Swift test files (Swift Testing + UI flow scaffolding), Vitest unit tests, Firestore/Storage security-rules tests on the emulator, golden-set evals for the AI extraction paths |
| CI / release | GitHub Actions PR gate, policy/security/build scripts, App Store Connect API release tooling, legal/support site |
| Engineering workflow | A multi-agent AI development workflow with handoff state, a decision ledger, cross-model review and secret screening |

## Architecture

```
iOS app (SwiftUI)
  ├─ Firebase Auth (Apple / Google sign-in)   no passwords stored
  ├─ App Check (App Attest)                    callables require attestation
  ├─ Firestore (persistent cache)   ◄──────── security rules, tested on the emulator
  ├─ Storage (attachments, receipts) ◄─────── storage rules + Pro-gate trigger
  ├─ RevenueCat SDK ──► RevenueCat ──webhook──► handleRevenueCatWebhook ──► entitlement doc
  └─ Callable Cloud Functions
       receiptQuickAdd / confirmReceiptScan ──► Claude extraction ──► proposal ──► user confirms ──► Firestore
       receiptQuotaStatus / reconcileReceiptCreditPurchase   scan quotas and top-up credits
       voiceQuickAdd        ──► Claude (speech to structured entry)
       parseOilAnalysis     ──► Claude (lab report PDF to structured values)
       lookupRecalls        ──► NHTSA recall data
       experimentConfig     A/B arm assignment
       deleteAccount / deleteVehicle   data-deletion paths
  Background triggers: recomputeVehicleOdometer (Firestore), enforceAttachmentProGate (Storage)
```

**End to end, receipt capture:**
1. The user photographs a receipt. The app checks the quota (`receiptQuotaStatus`) and uploads it
   to Storage.
2. `receiptQuickAdd` issues a scan token and calls Claude with a grounded extraction prompt.
3. The app shows the proposed entry: type, cost, odometer and line items.
4. Nothing is written until the user confirms (`confirmReceiptScan`). The entry then lands in
   Firestore, and the odometer trigger recomputes the vehicle's state.

Extraction quality is tracked with golden sets. In `reports/receipt-golden-prod*.json`, 212 of 216
and 318 of 324 field checks pass on the two corpus versions.

## Repository map

- `android/`: Kotlin/Compose Android port (Gradle project, its own README and architecture spec)
- `Garage/`: app source, design system (DesignPack v2 token engine), feature slices, resources
- `CloudFunctions/`: Firebase Cloud Functions (TypeScript), unit tests, rules tests, eval scripts
- `Configuration/`: xcconfigs and **secret templates** (real values are never committed)
- `Tests/`: Swift Testing unit tests and UI flow scaffolding
- `scripts/ci/`: policy, security and iOS verification gates, used locally and in CI
- `scripts/release/`: App Store Connect API tooling (`asc.py`) and the legal/support site generator
- `scripts/analytics/`: SQL for activation, conversion and notification funnels and experiment arms
- `scripts/brain/`: tooling for the AI development workflow (see below)
- `docs/`: developer, operations, release, user and research documentation
- `reports/`: eval results, audits, design gate receipts, cross-model review records
- `firebase.*.rules`, `firebase.json`, `.firebaserc`: backend configuration (Firebase project IDs are public by design)

## Running it locally

**Prerequisites:**
- a full Xcode 16+ install (Command Line Tools alone are not enough)
- XcodeGen and SwiftLint
- Node 22 and the Firebase CLI
- your own Firebase project (the projects in `.firebaserc` are mine and not accessible to you)

1. **App configuration**
   - `cp Configuration/Secrets.template.swift Configuration/Secrets.swift`, then fill in your values.
   - `cp Configuration/Local.template.xcconfig Configuration/Local.xcconfig` for signing overrides.
   - Add your own `Garage/Resources/GoogleService-Info.plist`.
2. **Generate and open the project:** `xcodegen generate && open Garage.xcodeproj`
3. **Cloud Functions**
   - Build and test: `cd CloudFunctions && npm ci && npm run build && npm test`
   - Security-rules tests on the emulator: `npm run test:rules`
   - Copy `.env.example` to `.env.<your-project-id>`. Deployed environments read their secrets
     from Secret Manager: `ANTHROPIC_API_KEY`, `REVENUECAT_SECRET_API_KEY`, `REVENUECAT_WEBHOOK_AUTH`.
   - Local emulator: `npm run serve`. To deploy, see [docs/DEPLOY_RUNBOOK.md](docs/DEPLOY_RUNBOOK.md).
4. **Android app (no accounts needed):** `cd android && ./gradlew :app:assembleDebug` boots in Demo
   mode; add `android/app/google-services.json` for live Firebase. See [android/README.md](android/README.md).
5. **AI evals (optional, needs an Anthropic key):** `npm run eval:askgarage`. The receipt goldens
   live under `CloudFunctions/scripts/golden/`. Every receipt there is generated and uses fictional
   data.

## Quality gates

- `./scripts/ci/policy-checks.sh`: repo policy (no secrets, no forbidden patterns, structure)
- `./scripts/ci/security-checks.sh`: security posture checks
- `./scripts/ci/verify-ios.sh`: build and test the app
- `android/scripts/android-verify.sh`: build, unit-test and lint the Android app
- **GitHub Actions** (`.github/workflows/ios.yml`) runs on pull requests and uses no repository
  secrets. It has three jobs:
  - a path filter;
  - a Functions job (build and tests);
  - an iOS job (security checks, a hermetic dummy Firebase config, pinned XcodeGen and SwiftLint,
    build and test).

See [developer setup](docs/developer/local-setup.md),
[quality gates](docs/developer/quality/ios-quality-gates.md),
[release runbook](docs/operations/release-runbook.md),
[security runbook](docs/operations/security/mobile-security-runbook.md) and
[user guide](docs/user/getting-started.md).

## Operations

- **Deploy and release:** [docs/DEPLOY_RUNBOOK.md](docs/DEPLOY_RUNBOOK.md) covers Firebase deploys,
  Secret Manager, App Check and rollback. `scripts/release/asc.py` automates the App Store Connect API.
- **Cost discipline:** the project was spun down on 2026-08-27, with its run-rate verified at
  roughly $0/month. Production runs on the free tier: about 300 Cloud Run requests per 30 days,
  under 15 MB of storage, and no always-on instances. The record is in `HANDOFF.md`.
- **Status:** active development is paused. The code, docs and history are complete as of that
  checkpoint.

## AI-assisted engineering workflow

One developer (JT) built this project by directing AI coding agents through a deliberate
workflow. The human owns architecture, product decisions, review gates and operations. The
workflow itself is part of the repo:

- `HANDOFF.md`: the always-current cross-session state (read first, write last)
- `DECISION_LEDGER.jsonl`: recorded decisions and votes
- `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`: per-agent doctrine, kept in sync
- `docs/ai/MACHINE_BRAIN_BLUEPRINT.md`: the architecture of the workflow
- `scripts/brain/`:
  - cross-model review (`tri_review.py`)
  - voting (`tri_agent_vote.py`, `consensus.py`)
  - a dual-agent loop and scope guarding
  - a process sentinel that catches leaked long-running jobs
  - `secret_screen.py`, which redacts secrets from anything sent to a model provider
- `reports/tri-review/`, `reports/audit/`, `reports/gates/`: the review and gate receipts

## Public snapshot notes

- **History is preserved.** Every commit and branch from the private repo is included.
  - Commit SHAs differ from the private repo because of the redaction below.
  - Short SHAs and PR numbers quoted inside docs refer to the private history; PR discussions
    are not part of this copy.
- **What was redacted, and nothing else:** in `HANDOFF.md` and its history, a GCP billing account ID
  was replaced with `[REDACTED-BILLING-ACCOUNT]`. References to an unrelated personal project (its VM
  name and local path) were replaced with neutral wording.
- **Secrets were never committed** (see [SECURITY.md](SECURITY.md)). Before publishing, the history
  was scanned with gitleaks plus a custom scan of every blob. The only hits are test fixtures and
  placeholders, such as the dummy Firebase key used by CI's hermetic tests.
- **Product requirements:** `blueprint.md` is treated as the source of truth for product features.
  It describes a React/PWA stack; this repo deliberately implements it on native iOS instead.
