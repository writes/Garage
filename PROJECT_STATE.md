# Garage — Project State

> **Single-file detailed snapshot of the whole project**, generated 2026-06-29.
> Two layers live in this repo: the **Garage iOS application** (the product) and the
> **machine brain** (the multi-LLM intelligence layer that develops it).
>
> This is a *snapshot* (point-in-time, detailed). It does **not** replace the brain's live
> surfaces: `HANDOFF.md` is the thin always-current cross-agent state; `CLAUDE.md` is the
> compact doctrine; `docs/ai/MACHINE_BRAIN_BLUEPRINT.md` is the architecture self-portrait. When
> those disagree with this file, **they win** — regenerate this snapshot.

---

## 1. Executive summary

**Garage** is a native iOS app for serious car owners: a clean service log, resale-ready
exports, and advanced ownership tracking (maintenance, track days, oil analysis, parts,
warranties, recalls). It is a SwiftUI app (Swift 6, iOS 17+) backed by Firebase + a small set of
Cloud Functions, with RevenueCat subscriptions and Claude-powered PDF parsing.

- **Product source:** ~141 Swift files (~5,600 LOC) under `Garage/`, organized App → Core →
  Design → Features.
- **Backend:** Firebase (Auth, Firestore, Storage, Functions, App Check, Crashlytics,
  Messaging) + 4 TypeScript Cloud Functions under `CloudFunctions/`.
- **Build:** XcodeGen-generated project from `project.yml`; CI gate in `scripts/ci/` + GitHub
  Actions.
- **Intelligence layer:** a full multi-LLM "machine brain" (Organs I–V + living blueprint) was
  installed 2026-06-29 (commit `5679a11`, branch `brain/install-v1`) — see §9.
- **Architecture is locked to native iOS.** `blueprint.md` describes a React/PWA/Supabase stack;
  that is treated as *product-feature truth only* and implemented on native iOS. A proposal to
  re-platform was assayed and recorded **Tier D / doctrine-fail** in the intake graveyard.

---

## 2. Product — what the app does

Primary user: an enthusiast tracking 1–3 vehicles (daily drivers to dedicated track cars), who
cares about maintenance history, resale documentation, and performance data. Initial reference
vehicles in the blueprint: a 2008 Dodge Viper ACR (track) and a 2015 Audi SQ5 (daily).

**Feature areas (each a slice under `Garage/Features/`):**

| Area | Purpose | Key views/VMs |
|---|---|---|
| **Auth** | Sign in with Apple / Google (no passwords) | `LoginView`, `AuthViewModel` |
| **Dashboard** | At-a-glance: odometer hero, reminders, recall alerts, recent feed, wear bars | `DashboardView` + cards |
| **Log** | The maintenance log: list, filter, detail, rows | `LogView`, `EntryDetailView`, `EntryFilterSheet` |
| **EntryForms** | Add/edit every entry type (service, oil, performance) via a form factory | `EntryFormFactoryView`, type-specific forms |
| **Garage** | Parts, detailing log, photo/wheel galleries, warranties & recalls | `GarageView`, `SparePartsView`, `PhotoGalleryView`, `WarrantyRecallView` |
| **Stats** | Charts: cost breakdown, MPG trend, wear history | `StatsView` + chart views |
| **Settings** | Profile, vehicles, reminders config, export, subscription | `SettingsView`, `VehicleFormView`, `ExportView`, `SubscriptionView` |
| **Shared** | Cross-feature UI: vehicle switcher, floating add, Pro gate | `VehicleSwitcher`, `FloatingAddButton`, `ProGateView` |

**Entry taxonomy** (`Garage/Core/Models/Entries/`): Service (maintenance, repair, brake, tire,
alignment, fuel), Oil (change, analysis, consumption), Performance (track day, DME report,
upgrade). Plus detailing records, spare parts, tire sets, wear snapshots, reminders, warranties,
recalls, gallery photos.

**Monetization:** RevenueCat subscriptions gate "Pro" features (`PurchaseService`, `ProGateView`,
`SubscriptionView`); a `stripeWebhook` Cloud Function plumbs entitlements.

**AI feature:** Blackstone-style oil-analysis PDFs are parsed via the Claude API through the
`claudeProxy` Cloud Function (`ClaudeService` on device → `OilAnalysisViewModel` autofill).

---

## 3. Architecture

### 3.1 iOS app layers (`Garage/`)
- **`App/`** — composition root: `GarageApp` (entry), `AppState`, `AppRouter`, `AppTab`,
  `ContentView`. App-wide state and navigation.
- **`Core/Models/`** — Codable domain models (`Entry` + per-type entries, `Vehicle`, `User`,
  `TireSet`, `WearSnapshot`, `Reminder`, `Warranty`, `Recall`, `SparePart`, `SyncQueueItem`,
  `Attachment`, `ReportSection`, `AnyCodable`).
- **`Core/Services/`** — the dependency layer, grouped by concern:
  - **Auth:** `AuthService`, `AppleSignInNonce`
  - **Database:** `FirestoreService`
  - **Domain:** `EntryService`, `VehicleService`, `ReminderService`, `WearService`,
    `WarrantyService`, `PartsService`, `GalleryService`, `DetailingService`, `StorageService`
  - **Sync:** `SyncService` (offline queue → Firestore)
  - **Export:** `PDFExportService` (TPPDF), `CSVExportService`
  - **AI:** `ClaudeService` (→ `claudeProxy` function)
  - **Security:** `AppIntegrityService` (App Check), `SecureStoreService` (Keychain)
  - **Subscription:** `PurchaseService` (RevenueCat)
- **`Design/`** — design system: `Theme`, reusable components (cards, buttons, banners,
  skeleton/shimmer loaders, search, badges, empty states) + modifiers.
- **`Features/`** — MVVM feature slices (View + ViewModel), listed in §2.

### 3.2 Backend — Firebase + Cloud Functions
- **Firestore** — primary datastore (users, vehicles, entries, etc.); security rules in
  `firebase.firestore.rules` (default-deny; per-document owner checks on `userId`/`uid`); indexes
  in `Configuration/FirestoreIndexes.json`.
- **Storage** — receipts, vehicle/glamour photos, generated PDFs; rules in
  `firebase.storage.rules`.
- **Cloud Functions** (`CloudFunctions/src/`, TypeScript, Node 22):
  - `claudeProxy.ts` — server-side Claude API call for oil-analysis PDF parsing (keeps the API
    key off-device).
  - `nhtsaRecalls.ts` — recall lookups (NHTSA).
  - `stripeWebhook.ts` — subscription/entitlement webhook plumbing.
  - `index.ts` — function exports.
- **App Check** — `AppIntegrityService` + `FirebaseAppCheck`; provider selection differs in
  simulator/local vs prod (recent commits stabilized this).

### 3.3 Cross-cutting
- **Offline-first sync** via `SyncService` + `SyncQueueItem` (queue writes, reconcile to
  Firestore).
- **Privacy** — `Garage/Resources/PrivacyInfo.xcprivacy` privacy manifest.
- **Error handling** — `AppError`, `ErrorBanner`, `Logger`; `AsyncTimeout` utility for bounded
  async work.

---

## 4. Tech stack & dependencies

| Layer | Choice |
|---|---|
| Language / UI | Swift 6 (strict concurrency `complete`), SwiftUI, iOS 17+ |
| Project gen | XcodeGen (`project.yml` → `Garage.xcodeproj`) |
| Backend | Firebase (Auth, Firestore, Storage, Functions, App Check, Analytics, Crashlytics, Messaging) |
| Functions runtime | TypeScript on Node 22 (`firebase-functions`, `firebase-admin`) |
| Subscriptions | RevenueCat (`purchases-ios-spm` 5.x) |
| Sign-in | GoogleSignIn-iOS 7.x + Sign in with Apple |
| PDF | TPPDF 2.5.x (export); Claude API (parsing, via function) |
| Lint | SwiftLint (SwiftLintPlugins 0.57.x), `.swiftlint.yml`, strict mode |

Swift Package deps are pinned in `project.yml` (Firebase 11.x, GoogleSignIn 7.x, RevenueCat 5.x,
TPPDF 2.5.x, SwiftLintPlugins 0.57.x). Bundle ID: `com.writes.harrysplayhouse` (release) /
`.debug` (debug). Firebase project: `harrys-playhouse` (dev/prod env files).

---

## 5. Repository layout

```
AppDev/
├── Garage/                     # SwiftUI app (App · Core · Design · Features · Resources)
├── CloudFunctions/             # TypeScript Firebase Functions (src/, Node 22)
├── Configuration/              # xcconfigs, FirestoreIndexes.json, Secrets (gitignored)
├── Tests/                      # UnitTests (Swift Testing) + UITests (XCUITest)
├── scripts/
│   ├── ci/                     # policy-checks · security-checks · verify-ios  (the GATE)
│   └── brain/                  # machine-brain Organs I–II–III (Python)  ← new
├── docs/
│   ├── developer/ operations/ user/   # human docs (setup, runbooks, quality gates)
│   ├── ai/MACHINE_BRAIN_BLUEPRINT.md   # brain self-portrait  ← new
│   ├── research/                       # pre-reg + verdict trial docs  ← new
│   └── research-assay/audit/           # idea graveyard (REGISTRY, index.jsonl, tier-*)  ← new
├── .claude/                    # agents/ workflows/ hooks/ settings.json  ← new
├── .github/workflows/ios.yml   # CI: functions build + iOS verify
├── project.yml                 # XcodeGen spec (PROTECTED by consensus)
├── firebase.json · .firebaserc · firebase.*.rules     # Firebase config + security rules
├── blueprint.md                # original product blueprint (PWA stack = product-truth only)
├── CLAUDE.md / AGENTS.md / GEMINI.md   # mirrored doctrine  ← new
├── HANDOFF.md · DECISION_LEDGER.jsonl  # brain state + decision ledger  ← new
└── PROJECT_STATE.md            # this file
```

---

## 6. Build, configuration & secrets

**Local start:** install Xcode + XcodeGen → copy `Configuration/Secrets.template.swift` →
`Secrets.swift` and populate → add `Garage/Resources/GoogleService-Info.plist` →
`xcodegen generate` → open `Garage.xcodeproj`. (Full Xcode.app required, not just CLT.)

**Config:** `Configuration/{Debug,Release}.xcconfig` (Debug includes optional `Local.xcconfig`),
strict warnings-as-errors, Swift 6 strict concurrency. A `postBuildScript` in `project.yml`
bundles `GoogleService-Info.plist` and derives URL schemes / `GIDClientID` from it.

**Secrets / protected (gitignored, never in agent prompts):** `Configuration/Secrets.swift`,
`Garage/Resources/GoogleService-Info.plist`, `CloudFunctions/.env.*`, `Configuration/Local.xcconfig`.

**Entitlements:** `Garage.entitlements` (release) / `GarageDebug.entitlements` (debug) — Apple
Sign-In + APNs (`aps-environment`).

---

## 7. Quality gates — the promoter

The **deterministic CI gate is the sole promoter** (no LLM declares work ready). Three scripts in
`scripts/ci/` (zsh, `set -euo pipefail`):

- **`policy-checks.sh`** — repo policy/structure checks.
- **`security-checks.sh`** — security checks (secret hygiene etc.).
- **`verify-ios.sh`** — the main gate: requires `xcodegen` + `swiftlint`; runs
  `policy-checks.sh` → `xcodegen generate` → `swiftlint lint --strict` →
  `xcodebuild … build` (CODE_SIGNING_ALLOWED=NO) → `xcodebuild … test` on an available
  simulator → archive parity.

**GitHub Actions** (`.github/workflows/ios.yml`) on PR + push to `main`:
- `functions` job (Ubuntu): `npm ci` + `npm run build` in `CloudFunctions/`.
- `ios` job (macOS 15): `brew install xcodegen swiftlint` → `./scripts/ci/verify-ios.sh`.

> ⚠️ Status note: this snapshot did **not** execute the iOS build/tests; the above is the
> *defined* gate. Run `./scripts/ci/verify-ios.sh` locally (full Xcode required) to confirm green.

**Tests** (`Tests/`): Unit (Swift Testing) cover models (entry decoding, validators, wear calc,
report sections, app errors), services (entry, reminder, wear, secure store, async timeout, Apple
nonce), and view models (dashboard, entry form, export). UI (XCUITest) cover auth flow + entry
creation.

---

## 8. Security & data model posture

- **Firestore rules:** default-deny (`match /{document=**} { allow read,write: if false }`),
  then per-collection owner checks (`request.auth.uid == userId` / `resource.data.userId ==
  request.auth.uid`); user docs are non-deletable (`delete: if false`).
- **App Check** enforced via `AppIntegrityService` (provider differs simulator vs prod).
- **Secrets off-device:** the Claude API key lives in the `claudeProxy` function, not the app.
- **Keychain** via `SecureStoreService`; privacy manifest present.

---

## 9. The machine brain (intelligence layer) — installed 2026-06-29

A portable multi-LLM "machine brain" was installed to develop this repo under governance. It
added **no app/product code** — only intelligence-layer surfaces. Full self-portrait:
`docs/ai/MACHINE_BRAIN_BLUEPRINT.md`. Committed as `5679a11` on branch `brain/install-v1`.

**The Five Laws:** (1) no solo decisions on substance — ≥3 independent LLM voters, 2/3 majority,
no veto, logged; (2) durable-by-default state on disk; (3) sandbox before autonomy (worktree +
scope guard; CI gate is sole promoter); (4) search the idea graveyard before evaluating;
(5) adversarial, human-gated verification.

**Organs:**

| Organ | Surfaces | Status |
|---|---|---|
| **I · Consensus** (cortex) | `scripts/brain/consensus.py` (pure 2/3 resolver, **17/17** self-test), `gemini_consult.py` (agy→Vertex→API voter), `tri_agent_vote.py` (live 3-voter runner), `DECISION_LEDGER.jsonl` | ✅ LIVE |
| **II · Looping** (motor) | `scripts/brain/scope_guard.py` (protected/allowed/protocol classifier + auto-revert, **34/34** self-test), `dual_agent_loop.py` (worktree-isolated plan→implement→review); promoter = `scripts/ci/*` | ✅ LIVE |
| **III · Memory** (hippocampus) | `HANDOFF.md` + `scripts/brain/session_handoff.py`, SessionStart hook (`.claude/hooks/session-handoff-inject.sh` wired in `.claude/settings.json`), cross-session memory home `~/.claude/projects/-Users-jt-Code-AppDev/memory/` | ✅ LIVE |
| **IV · Documentation** (DNA) | `CLAUDE.md`/`AGENTS.md`/`GEMINI.md` (mirrored doctrine + compact state), `docs/research/`, `docs/ARCHIVE.md`, `docs/ai/MACHINE_BRAIN_BLUEPRINT.md` | ✅ LIVE |
| **V · Verification** (immune system) | `.claude/agents/research-assay.md` (6-stage intake → tier A/B/C/D), `docs/research-assay/audit/` (graveyard, 1 verdict), `.claude/workflows/{async-commit-review,instrument-audit}.js` (finder→refuter) | ✅ LIVE |

**Voters available (full set, no degraded mode):** `claude` (Anthropic), `codex` (OpenAI),
`agy` (Google Antigravity) + `gcloud` (Vertex fallback) + `git` (worktrees).

**Scope-guard surfaces (Organ II):**
- *Protected (change → halt for human review):* `Configuration/Secrets.swift`,
  `Garage/Resources/GoogleService-Info.plist`, `CloudFunctions/.env*`, `firebase.firestore.rules`,
  `firebase.storage.rules`, `firebase.json`, `.firebaserc`, `scripts/ci/`, `Garage.xcodeproj/`,
  **`project.yml`** (added by consensus — see §10).
- *Allowed candidate surface:* `Garage/Features/`, `Garage/Design/`, `Garage/Core/`, `Tests/`,
  `CloudFunctions/src/`, `reports/`, `results/`, `logs/`, `docs/research/`.

---

## 10. Verification evidence — the multi-agent setup, proven live

On 2026-06-29 a real repo guardrail decision was put to a live tri-agent vote
(`scripts/brain/tri_agent_vote.py`): *how should `project.yml` be treated by the autonomous-loop
scope guard?*

- **claude** (Anthropic) → PROTECTED, conf 0.82 — caught the bypass loophole ("edit yml →
  regenerate the protected `.xcodeproj`").
- **codex** (OpenAI) → PROTECTED, conf 0.86 — cited the doctrine's protected-surface rule.
- **gemini** via **agy** (Google Antigravity backend confirmed) → PROTECTED, conf 0.95 —
  release-integrity risk.

→ Resolved **UNANIMOUS 3/3, no veto**, appended to `DECISION_LEDGER.jsonl`
(`group_key d09e41f1544ac2e6`), then **acted upon**: `project.yml` added to
`PROTECTED_PREFIXES` (verified `classify_change('project.yml') -> protected`) and to the
doctrine. The full cycle — question → 3 independent minds → deterministic resolution → durable
ledger → implementation — is demonstrated end-to-end.

**Self-tests:** `consensus.py selftest` 17/17 · `scope_guard.py selftest` 34/34. Intake graveyard
seeded with its first verdict: a "rewrite as React/PWA/Supabase" proposal → **Tier D**
(doctrine-fail; native iOS is locked).

---

## 11. Git state

- **Current branch:** `brain/install-v1` (brain install, commit `5679a11`).
- **Other branches:** `codex/simulator-local-demo` (simulator local demo work — the brain branch
  was cut from here), `main` (default; CI runs on push).
- **Working tree:** clean except untracked `.vscode/` (pre-existing, unrelated) and this file.
- **Recent product history:** simulator local demo mode, Apple auth handling, App Check provider
  selection, local Xcode signing, team dev bootstrap + production infra, Firebase auth wiring.

---

## 12. Open items / next actions

- **Merge path for the brain:** `brain/install-v1` is committed but not merged. Decide whether to
  merge to `main` or fold into `codex/simulator-local-demo`.
- **Confirm the gate is green locally:** run `./scripts/ci/verify-ios.sh` (needs full Xcode +
  simulator) — not executed in this snapshot.
- **Exercise the immune system:** optionally run `.claude/workflows/async-commit-review.js`
  against `5679a11` and `instrument-audit.js` before any TestFlight/Functions deploy.
- **Live product gaps** (not audited here): nothing flagged in this pass; treat the existing
  `docs/operations/*` runbooks as the source of truth for release/security ops.

See `HANDOFF.md` ▶ NEXT ACTION for the always-current single next step.

---

## 13. Landmines (operational scar tissue)

`agy models` HANGS — never call it (use `agy -p … --print-timeout <T>s < /dev/null`) ·
`codex exec` HANGS without stdin (always pipe the prompt) · the free `@google/gemini-cli` OAuth
tier is dead for individuals (use agy/Vertex/API) · 429s are a concurrency herd, not the cap
(≤4 fat agents · 1 Codex track · 1 Workflow; provider pools may overlap) · never a null ledger
timestamp · the scope check is path-based so keep secrets out of prompts · verify the *running*
image, not a "deployed ✅" note · HANDOFF only points — one fact, one surface. Full catalog:
`docs/ai/MACHINE_BRAIN_BLUEPRINT.md` §9.

---

*Snapshot generated 2026-06-29. Regenerate when the architecture or brain surfaces change; keep
`HANDOFF.md` (live state), `CLAUDE.md` (doctrine), and the blueprint (architecture) as the
authoritative surfaces.*
