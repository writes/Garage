# Epoch-1 kill runbook (design_megatest) — stage NOW, execute BEFORE the app goes on sale

Why: the binary in review carries design_megatest epoch 1 live-armed (50/50) with the
partial PR #23 "bold" variant_a. Public launch without this kill enrolls real users into a
half-designed challenger (master plan §2, Sol finding B1). The prereg is review-phase-only;
production was never authorized (B2).

## The kill (operator-executed; prod config write)

Write the server override document the app already polls (`experimentConfig` read path):

```bash
# Firestore: app_config/experiments — kill design_megatest epoch 1
gcloud firestore documents update "app_config/experiments" \
  --project=harrys-playhouse-prod \
  --update-mask="design_megatest" \
  --fields='design_megatest={"epoch":1,"isKilled":true}'
```

(If the gcloud shape fights you, the equivalent one-doc set via the Firebase console:
Firestore → `app_config/experiments` → field `design_megatest` = `{epoch: 1, isKilled: true}`.
The CloudFunctions sanitizer accepts `isKilled` for a known experiment.)

## Verify

1. Read the doc back (console or `gcloud firestore documents describe`).
2. On a TestFlight install: relaunch twice → the bold variant renders control after the
   first override fetch; `experiment_exposure` stops for new installs after their first
   resolved fetch.

## Known imperfection (accepted, bounded)

The shipped binary applies the BUNDLED assignment before its first frame and only then
fetches the override — a fresh install may render/log variant_a once before the kill lands
(Sol B8). Bounded by epoch closure: epoch 1 is recorded as "never publicly enrolled;
superseded", and any leaked exposure rows are quarantined by epoch in analysis. The first
post-approval build ships the bundled kill + the fail-closed enrollment gate, removing the
leak class entirely.

## Timing

- Stage: now. Execute: any time before "Ready for Sale" flips — put it in the release
  checklist ahead of the release click (release is MANUAL per standing rule).
- After execution, note date/time + who in this file's margin and in HANDOFF.
