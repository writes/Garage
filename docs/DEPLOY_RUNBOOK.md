# Garage — Production Deploy Runbook

> Operator-only steps. Everything here needs YOUR credentials (Firebase, Apple, RevenueCat,
> Anthropic) and cannot be run by an agent. The app + Cloud Functions are code-complete and gated
> green; this is the wiring to production. Do **dev** first, verify, then **prod**.

Projects (`.firebaserc`): `dev = harrys-playhouse-dev`, `prod = harrys-playhouse-prod`.

---

## 0. Prerequisites
- `firebase login` (currently **not authenticated** — `firebase login:list` shows none).
- Apple Developer account + App Store Connect access for the bundle id **`com.writes.harrysplayhouse`** (debug builds use `.debug`).
- The real **Anthropic API key**, **RevenueCat prod SDK key**, and a chosen **RevenueCat webhook auth token**.

## 1. Cloud Functions — secrets (REQUIRED, or functions fail at runtime)
The v2 functions now declare Secret Manager secrets (`src/params.ts`). Set them before deploy:
```bash
cd CloudFunctions
firebase functions:secrets:set ANTHROPIC_API_KEY      --project prod   # paste the Anthropic key
firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH --project prod   # a strong shared token
```
Bound to: `parseOilAnalysis`, `voiceQuickAdd` (ANTHROPIC_API_KEY) and `handleRevenueCatWebhook`
(REVENUECAT_WEBHOOK_AUTH). Without these, voice/oil-analysis throw "API key is not configured"
and the webhook returns 503.

## 2. Cloud Functions — build + deploy
```bash
cd CloudFunctions
npm ci && npm run build && npm test          # tsc clean + 102 tests
firebase deploy --only functions --project dev     # dev first
# smoke-test dev, then:
firebase deploy --only functions --project prod
```
Functions: `parseOilAnalysis`, `voiceQuickAdd`, `handleRevenueCatWebhook`, `lookupRecalls`,
`deleteAccount`, `deleteVehicle`, `recomputeVehicleOdometer` (Firestore trigger),
`enforceAttachmentProGate` (Storage trigger) (region `us-central1`; callables enforce App Check).

### ⚠️ The FIRST functions deploy to a project always fails — twice. Budget for it.
Observed on dev 2026-07-24, immediately after enabling Blaze. Both failures are expected and
transient; neither means the code is wrong.

**Failure 1 — IAM service agents not provisioned.** `Error: We failed to modify the IAM policy
for the project.` v2 functions with Eventarc/Storage/Firestore triggers need four service-agent
bindings that don't exist on a fresh project. The CLI prints the exact commands; run them (add
`--condition=None` or gcloud prompts interactively and hangs a non-interactive shell):
```bash
P=<project-id>; N=<project-number>
gcloud projects add-iam-policy-binding $P --condition=None \
  --member=serviceAccount:service-$N@gs-project-accounts.iam.gserviceaccount.com --role=roles/pubsub.publisher
gcloud projects add-iam-policy-binding $P --condition=None \
  --member=serviceAccount:service-$N@gcp-sa-pubsub.iam.gserviceaccount.com --role=roles/iam.serviceAccountTokenCreator
gcloud projects add-iam-policy-binding $P --condition=None \
  --member=serviceAccount:$N-compute@developer.gserviceaccount.com --role=roles/run.invoker
gcloud projects add-iam-policy-binding $P --condition=None \
  --member=serviceAccount:$N-compute@developer.gserviceaccount.com --role=roles/eventarc.eventReceiver
```
**Failure 2 — propagation + a source-bucket race.** The retry still partially fails: trigger
functions get `400 … Permission denied while using the Eventarc Service Agent … may take a few
minutes before all necessary permissions are propagated`, and several functions race to create
`gcf-v2-sources-<N>-us-central1`, so all but one get `409 Could not create bucket`. **Wait ~2
minutes and deploy again** — the bucket now exists and the bindings have propagated. Deploying
one function first (`--only functions:deleteVehicle`) to create the bucket, then the rest, also
works. Do NOT start debugging the functions; nothing is wrong with them.

**Failure 2 can outlast one retry — the fix is patience, not IAM.** On prod the two
Eventarc-triggered functions (`enforceAttachmentProGate` on `storage.object.finalized`,
`recomputeVehicleOdometer` on `firestore.document.written`) still failed on the second attempt —
one with `403 Permission "storage.buckets.get" denied … verify that [the Eventarc service
account] has permission`, the other with the same 400 as above. **No manual IAM grant was
needed.** Deploying just those two later succeeded with no intervention: the service agents
finish provisioning on their own timescale. Retry the failed subset with
`--only functions:<a>,functions:<b>` before granting anything by hand.

### The webhook needs a public invoker — verify it, don't assume it
`onRequest` defaults to a public invoker, but when the **first** deploy fails at its IAM step
(Failure 1 above) the binding is never applied and Cloud Run rejects every third-party POST at
the edge with `401 Authorization header lacked OIDC mandated 'Bearer' prefix` — the request
never reaches your code. `handleRevenueCatWebhook` now declares `invoker: "public"` explicitly so
each deploy reconciles it. **Verify against the running service, and read the BODY, not just the
status** — the function also answers 401 for a bad secret, so status alone cannot tell you which
layer refused:

| Body | Refused by |
|---|---|
| HTML + a `www-authenticate: Bearer` header | Cloud Run (function never ran) |
| plain `Unauthorized.` | the function's own authorization check |

**Secrets must not carry a trailing newline.** `firebase functions:secrets:set --data-file`
stores the file verbatim, so a file written by `python -c "print(...)"` stores 44 bytes for a
43-char token and the byte-exact comparison can never match. Write the file with no trailing
newline (`printf`, or `.strip()` before writing).

**A `.env.<project>` key and a Secret Manager secret of the same name cannot coexist:** the
deploy fails with `Secret environment variable overlaps non secret environment variable: <NAME>`.
Keep each secret in exactly one place.

## 3. Firestore + Storage rules

**RULES-1 rollout order is mandatory: backfill → rules → app binary.** The counted-create rules
read `users/{uid}.vehicleCount`; deploying them before the backfill would let legacy users
undercount (missing counter reads as 0), and shipping the counted-create app binary before the
rules is fine (the batch also satisfies the old rules), but the reverse order breaks vehicle
creation for old binaries — so rules go live only after the backfill, and ideally with the new
binary already in review.

```bash
# 1. Backfill per-user vehicle counters (dry-run first, then --apply):
cd CloudFunctions
GOOGLE_APPLICATION_CREDENTIALS=<svc.json> npx tsx scripts/backfillVehicleCounts.ts          # inventory + anomaly report
GOOGLE_APPLICATION_CREDENTIALS=<svc.json> npx tsx scripts/backfillVehicleCounts.ts --apply
# Review the anomaly report (orphan vehicles / over-cap users) before proceeding.

# 2. Deploy the rules:
firebase deploy --only firestore:rules,firestore:indexes,storage --project prod
```
Rollback: redeploy the previous rules file from git (`git show <sha>:firebase.firestore.rules`);
the counter fields are inert under the old rules.

## 4. App Check
- Register the iOS app for **App Check** (App Attest) in the Firebase console.
- The callables set `enforceAppCheck: true`, so real devices need a valid App Check token.
  Configure the App Attest provider + (optionally) a debug token for TestFlight.

## 5. iOS `Configuration/Secrets.swift` (PROTECTED — not in git)
Create from `Secrets.template.swift` with real values:
```swift
enum Secrets {
    static let revenueCatAPIKey = "appl_...real prod key..."
    static let anthroProxyRegion = "us-central1"
}
```
`verify-ios.sh` bootstraps a placeholder for CI; the real file is gitignored.

## 6. RevenueCat
- Products: `garage_pro_monthly`, `garage_pro_annual` (see `AnalyticsProductID`).
- Webhook: point RevenueCat at the deployed `handleRevenueCatWebhook` URL; set the
  `Authorization` header to the exact `REVENUECAT_WEBHOOK_AUTH` value from step 1 (the function
  compares it with a timing-safe check).

## 7. App Store Connect / TestFlight
- Version/build from `project.yml` (`CFBundleShortVersionString` / bundle version).
- **Privacy manifest** (`Garage/Resources/PrivacyInfo.xcprivacy`) — ✅ **complete as of
  2026-07-24.** `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1` IS declared (an earlier
  note here claiming `NSPrivacyAccessedAPITypes` was empty was stale — landmine #9). Verified no
  other required-reason API is used: no file-timestamp (`C617.1`), disk-space (`E174.1`),
  active-keyboard, or boot-time (`35F9.1`) calls anywhere in `Garage/`. Data types declared:
  UserID, Email, OtherUserContent, ProductInteraction. **Purchases** (RevenueCat) and
  **Crash/Diagnostics** (Crashlytics) are covered by those SDKs' own bundled privacy manifests,
  which Apple aggregates — re-check if either SDK is ever vendored rather than linked via SPM.
- App Privacy "nutrition label": declare data collected (account, purchases, diagnostics via
  Crashlytics/Analytics).
- Export compliance (uses standard encryption only → usually exempt; declare it).
- 🔴 **The App Store name is a PLACEHOLDER — change it before the first public release.**
  The record was created as **"Harry's Playhouse"** (2026-07-24) purely so an app record could
  exist while the naming/trademark workstream was still open
  (`docs/research/2026-07-24_underhood_trademark_preclearance.md`). It matches the bundle ID /
  Firebase project on purpose and is deliberately un-shippable-looking. The name is freely
  editable in ASC until the first public release; **after** a release it can only change with a
  new version. `python3 scripts/release/asc.py audit` re-raises this as a blocker on every run
  until the record carries a real, trademark-cleared name.
- **EU trader status (DSA) — OPERATOR-ONLY, HARD BLOCKER for EU distribution.** App Store
  Connect → **Business** → Trader Status. Only an **Account Holder or Admin** can set it; no
  agent, script, or build step can. Apple removes apps from the EU storefront until it is
  provided, and new versions/updates cannot be submitted without it. Declaring as a trader
  publishes the trader contact details (name, address, phone, email) on the EU App Store
  listing and requires Apple to verify them — allow lead time before a submission deadline.
  Declaring non-trader means no EU distribution.
- Policy + Terms URLs (required for a subscription app).
- Screenshots, description, subscription group + localized pricing.
- Confirm the **restore-purchases** path is reachable (Settings → Manage/Upgrade).

## 8. Pre-flight gates (run before each release)
```bash
./scripts/ci/verify-ios.sh                       # policy + build + tests + Release archive
./scripts/ci/release-checks.sh                   # BLOCKS on .invalid URLs + missing export-compliance key
node .claude/workflows/instrument-audit.js       # 4-lens GO/NO-GO brief (advisory)
cd CloudFunctions && npm run test:rules          # Firestore + Storage security-rules tests (emulator)
```
`release-checks.sh` currently FAILS (by design) until you (a) replace the `.invalid` Privacy/Terms
URLs in `Constants.swift` and (b) add `ITSAppUsesNonExemptEncryption` to `project.yml`.

## 9. Verify the RUNNING image (landmine #9)
After deploy, hit each function once from a real device build and confirm success — never trust a
"deployed ✅" log line. Watch Crashlytics + Functions logs for the first hour.
