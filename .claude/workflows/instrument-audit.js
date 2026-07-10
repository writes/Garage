/*
 * ORGAN V — Verification / Workflows ("the immune system")
 * ────────────────────────────────────────────────────────
 * instrument-audit.js — a PRE-RELEASE adversarial audit, the mobile analogue
 * of a pre-unblinding instrument audit. Run this BEFORE a TestFlight / App
 * Store submission or a Cloud Functions deploy. It does not push, sign, or
 * submit anything; it produces a GO / NO-GO BRIEF for a human to act on.
 *
 * FOUR LENSES, each run as finder → refuter:
 *   LENS 1  alignment              — does the build/release config actually do
 *                                    what the release runbook claims?
 *   LENS 2  data-integrity & money — entitlement/paywall correctness, no
 *                                    off-by-one in trial/subscription logic,
 *                                    export numbers match source data.
 *   LENS 3  privacy & security     — PrivacyInfo.xcprivacy completeness, no
 *                                    secrets in bundle, least-privilege rules,
 *                                    PII handling in Cloud Functions / Claude
 *                                    PDF parsing.
 *   LENS 4  data-loss              — migration/persistence safety for vehicle
 *                                    logs & service history, offline/sync edge
 *                                    cases, irreversible deletes.
 *
 * DISCIPLINE — finder → refuter: each lens runs a finder (surfaces candidate
 * issues with evidence), then INDEPENDENT refuters that DEFAULT to "not real"
 * and confirm only issues that are BOTH reachable AND release-blocking.
 *
 * LOOP-UNTIL-DRY: accepts args {rounds:N} (default 1). Finders re-run up to N
 * rounds and stop early once a round adds no NEW confirmed issue. Dropped /
 * again counts are logged so nothing is silently capped.
 *
 * OUTPUT IS A BRIEF, NEVER AN AUTO-EDIT. No auto-fix, no auto-revert, no
 * auto-submit. THE HUMAN HOLDS THE DEPLOY GATE.
 */

export const meta = {
  name: "instrument-audit",
  description:
    "Pre-release adversarial finder→refuter audit (4 lenses: alignment, money-math, privacy/security, data-loss) for the Garage iOS + Firebase app. Loop-until-dry. Emits a GO/NO-GO brief; never auto-edits or auto-submits. Human holds the deploy gate.",
  phases: [
    "Scope & runbook alignment",
    "Adversarial audit pass",
    "GO / NO-GO synthesis",
  ],
};

// ── helpers ────────────────────────────────────────────────────────────────

function resolveRounds(input) {
  if (input && typeof input === "object" && input.rounds != null) {
    const n = parseInt(input.rounds, 10);
    if (!isNaN(n) && n > 0) return n;
  }
  return 1;
}

const SEVERITY_ORDER = ["critical", "high", "med", "low"];
function severityRank(sev) {
  const i = SEVERITY_ORDER.indexOf(String(sev || "").toLowerCase());
  return i === -1 ? SEVERITY_ORDER.length : i;
}

// Stable identity for an issue, so loop-until-dry can tell NEW from AGAIN.
function issueKey(i) {
  return [
    String(i.lens || "").toLowerCase().trim(),
    String(i.title || "").toLowerCase().trim(),
    String(i.location || "").toLowerCase().trim(),
  ].join("|");
}

const LENSES = [
  {
    key: "alignment",
    title: "Alignment — config vs release runbook",
    finderFocus:
      "Does the actual build/release configuration do what the release runbook/docs claim? Check: bundle identifier and display name, the release scheme/xcconfig (Configuration/Release.xcconfig vs Debug.xcconfig), entitlements (Garage.entitlements vs GarageDebug.entitlements — aps-environment, App Groups, associated domains), which Firebase project the shipped GoogleService-Info.plist points at (PROJECT_ID / BUNDLE_ID must be PROD, not a debug/emulator project, and not the local-demo path), App Check provider selection (DeviceCheck/AppAttest in release vs debug provider), and code-signing / provisioning (project.yml, Garage.xcodeproj settings). Flag any place the runbook promises one thing and the config delivers another.",
    refuterFocus:
      "Confirm only mismatches that would actually ship a wrong/broken release (wrong Firebase project, debug App Check provider in prod, dev entitlements, mis-signed build). Cosmetic or already-overridden-at-build-time items are NOT blocking.",
  },
  {
    key: "money_math",
    title: "Data-integrity & money-math — entitlements, paywall, exports",
    finderFocus:
      "Entitlement and money correctness. Check the RevenueCat product->entitlement mapping in Garage/Core/Services/Subscription/PurchaseService.swift and SubscriptionView: does every paid product unlock exactly the right entitlement, and is locked content actually gated? Look for off-by-one or boundary bugs in trial / subscription window logic (trial length, expiry comparisons, grace period, renewal boundaries, timezone/date math). Cross-check CloudFunctions/src/functions/stripeWebhook.ts entitlement plumbing against the client's assumptions. Verify export/report numbers (Garage/Core/Services/Export CSVExportService/PDFExportService) match the source vehicle data exactly — no dropped rows, double-counts, unit/currency mistakes, or rounding drift.",
    refuterFocus:
      "Confirm only issues that would grant/deny entitlements incorrectly, mischarge or mis-gate a user, or emit a wrong number to the user. Theoretical edge cases with no real trigger are NOT blocking.",
  },
  {
    key: "privacy_security",
    title: "Privacy & security — manifest, secrets, rules, PII",
    finderFocus:
      "Privacy and security posture for submission. Check Garage/Resources/PrivacyInfo.xcprivacy: are all collected data types and required-reason APIs declared and consistent with what the app actually does (auth, analytics, vehicle data)? Scan for secrets that would ship in the bundle or repo (Configuration/Secrets.swift, *.xcconfig, plists, hardcoded RevenueCat/Stripe/Anthropic/Firebase keys). Re-audit firebase.firestore.rules and firebase.storage.rules for least-privilege (ownership checks on users/, vehicles/ and subcollections; no wildcard read/write leaks). Review PII handling in Cloud Functions, especially claudeProxy.ts and the Claude PDF-parsing path: what user/vehicle data is sent off-device, is it minimised, logged, or retained, and is the Anthropic call server-side with the key never exposed to the client?",
    refuterFocus:
      "Confirm only issues that would fail App Store privacy review, leak a secret, expose another user's data via rules, or send unminimised PII off-device. Declared-but-slightly-verbose manifest entries are NOT blocking.",
  },
  {
    key: "data_loss",
    title: "Data-loss — migration, persistence, sync, deletes",
    finderFocus:
      "Durability of user vehicle logs and service history across this release. Check migration/persistence safety: schema or model changes (Garage/Core/Models, FirestoreService) without a backfill or with a lossy transform; SyncService offline/online conflict resolution that can drop or clobber local unsynced edits; cache eviction that discards data not yet persisted; and irreversible deletes (cascade deletes on a vehicle wiping service history, hard deletes with no soft-delete/undo/confirmation). Confirm the firestore rules even ALLOW the deletes the app performs, and that export is available as a safety valve before destructive operations.",
    refuterFocus:
      "Confirm only issues that can actually lose or corrupt real user data (vehicle logs / service history) on a realistic device/sync path. Defensively-handled or already-guarded cases are NOT blocking.",
  },
];

const FINDER_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["issues"],
  properties: {
    issues: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["lens", "title", "location", "severity", "why", "evidence"],
        properties: {
          lens: { type: "string" },
          title: { type: "string" },
          location: { type: "string" },
          severity: {
            type: "string",
            enum: ["low", "med", "high", "critical"],
          },
          why: { type: "string" },
          evidence: { type: "string" },
        },
      },
    },
  },
};

const REFUTER_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["verdict"],
  properties: {
    verdict: {
      type: "object",
      additionalProperties: false,
      required: [
        "is_real",
        "reachable",
        "release_blocking",
        "confidence",
        "rationale",
      ],
      properties: {
        is_real: { type: "boolean" },
        reachable: { type: "boolean" },
        release_blocking: { type: "boolean" },
        confidence: { type: "number", minimum: 0, maximum: 1 },
        rationale: { type: "string" },
      },
    },
  },
};

// ── workflow body ───────────────────────────────────────────────────────────

const rounds = resolveRounds(args);
log(
  `instrument-audit: pre-release adversarial audit, up to ${rounds} round(s). Advisory GO/NO-GO; never auto-edits or auto-submits.`
);

// SCOPE — load shared release-context once so every lens reasons from the same
// facts (which project is "prod", where the runbook lives, etc.).
phase("Scope & runbook alignment");

const scopeSchema = {
  type: "object",
  additionalProperties: false,
  required: ["facts", "runbook_sources"],
  properties: {
    facts: { type: "string" },
    runbook_sources: { type: "array", items: { type: "string" } },
  },
};

const scope = await agent(
  `You are establishing shared release context before a pre-release audit of the Garage iOS app (SwiftUI/Swift 6, iOS 17+) + Firebase Cloud Functions.

Read enough to report the ground truth a release runbook would assert:
  - The release runbook / deploy docs (look in docs/, README.md, HANDOFF.md, blueprint.md, .github/).
  - The intended PROD Firebase project (.firebaserc, firebase.json, Garage/Resources/GoogleService-Info.plist PROJECT_ID/BUNDLE_ID).
  - Release vs debug config (Configuration/Release.xcconfig, Debug.xcconfig, project.yml) and entitlements (Garage.entitlements vs GarageDebug.entitlements).
  - Where App Check provider selection lives (Garage/Core/Services/Security/AppIntegrityService.swift, app bootstrap).

Summarise the facts the lenses should hold the build against, and list the runbook source files you found. Do not modify anything. Return only the structured object.`,
  { label: "scope", phase: "Scope & runbook alignment", schema: scopeSchema }
);

const sharedContext = `RELEASE CONTEXT (ground truth from scope):
${scope.facts}
Runbook sources: ${(scope.runbook_sources || []).join(", ") || "(none located — flag this as an alignment risk)"}`;

log(
  `Scope complete. Runbook sources: ${(scope.runbook_sources || []).length}.`
);

// One lens = finder -> parallel refuters.
async function runLens(lens, round) {
  const found = await agent(
    `You are a FINDER for a PRE-RELEASE audit of the Garage iOS + Firebase app.
LENS: ${lens.title}.
Audit round: ${round}.

${sharedContext}

What to hunt for:
${lens.finderFocus}

Rules:
  - Use Read/git/grep to inspect the real files; cite a concrete location (file:line or config key) in "location".
  - "evidence" must quote/paraphrase the offending code or config so a refuter can verify independently.
  - severity: critical = must not ship; high = release-blocking defect; med = should fix; low = note.
  - Precision over volume; an empty issues array is a valid answer.
  - Do NOT edit, fix, sign, or submit anything. Return the structured object only.`,
    {
      label: `find:${lens.key}:r${round}`,
      phase: "Adversarial audit pass",
      schema: FINDER_SCHEMA,
    }
  );

  const issues = (found.issues || []).map((i) => ({
    ...i,
    lens: i.lens || lens.title,
    lensKey: lens.key,
  }));

  if (issues.length === 0) return { lensKey: lens.key, confirmed: [], raised: 0 };

  const verdicts = (
    await parallel(
      issues.map((iss) => async () => {
        const out = await agent(
          `You are a REFUTER for a pre-release audit. Default stance: the issue is NOT real.
CONFIRM only when the issue is BOTH:
  (a) reachable on the real release/deploy path, AND
  (b) release-blocking — it would ship a wrong/broken release, a money/entitlement error, a privacy/security failure, or real user data loss.
Speculation, style, and already-guarded or build-time-overridden cases do NOT qualify.

Repo: Garage iOS (SwiftUI/Swift 6) + Firebase Cloud Functions (TypeScript).
${sharedContext}

ISSUE TO REFUTE OR CONFIRM:
  lens: ${iss.lens}
  title: ${iss.title}
  location: ${iss.location}
  claimed severity: ${iss.severity}
  why (finder's claim): ${iss.why}
  evidence: ${iss.evidence}

Independently verify against the actual files. Decide is_real, reachable, and release_blocking. Return ONLY the structured verdict. Do not edit anything.`,
          {
            label: `refute:${lens.key}:r${round}`,
            phase: "Adversarial audit pass",
            schema: REFUTER_SCHEMA,
          }
        );
        return { issue: iss, verdict: out.verdict };
      })
    )
  ).filter(Boolean);

  const confirmed = verdicts
    .filter(
      (v) =>
        v.verdict &&
        v.verdict.is_real &&
        v.verdict.reachable &&
        v.verdict.release_blocking
    )
    .map((v) => ({ ...v.issue, verdict: v.verdict }));

  log(
    `[round ${round}] Lens "${lens.title}": ${issues.length} raised -> ${confirmed.length} confirmed blocker(s).`
  );
  return { lensKey: lens.key, confirmed, raised: issues.length };
}

// LOOP-UNTIL-DRY across rounds.
const confirmedByKey = new Map(); // issueKey -> confirmed issue (deduped)
let totalRaised = 0;

for (let round = 1; round <= rounds; round++) {
  phase("Adversarial audit pass");
  log(`Audit round ${round} of up to ${rounds}.`);

  const lensResults = (
    await parallel(LENSES.map((lens) => () => runLens(lens, round)))
  ).filter(Boolean);

  let roundNew = 0;
  let roundAgain = 0;
  for (const lr of lensResults) {
    totalRaised += lr.raised || 0;
    for (const c of lr.confirmed || []) {
      const key = issueKey(c);
      if (confirmedByKey.has(key)) {
        roundAgain++;
      } else {
        confirmedByKey.set(key, c);
        roundNew++;
      }
    }
  }

  log(
    `Round ${round}: ${roundNew} new confirmed, ${roundAgain} again (already known). Cumulative confirmed: ${confirmedByKey.size}.`
  );

  if (roundNew === 0) {
    const dropped = rounds - round;
    log(
      `Loop-until-dry: round ${round} added no new confirmed blocker. Stopping early; ${dropped} further round(s) not run (nothing silently capped — the audit went dry).`
    );
    break;
  }
  if (round === rounds && rounds > 1) {
    log(
      `Loop-until-dry: reached the ${rounds}-round cap while still finding new blockers — more may remain. NOT a clean "dry" result; consider re-running with higher {rounds}.`
    );
  }
}

// SYNTHESIZE GO / NO-GO BRIEF ──────────────────────────────────────────────────
phase("GO / NO-GO synthesis");

const confirmed = Array.from(confirmedByKey.values());
confirmed.sort((a, b) => severityRank(a.severity) - severityRank(b.severity));

const blockers = confirmed.filter((c) => {
  const s = String(c.severity || "").toLowerCase();
  return s === "critical" || s === "high";
});
const recommendation = blockers.length > 0 ? "NO-GO" : "GO (advisory)";

const lines = [];
lines.push("# Instrument Audit — Pre-Release GO / NO-GO Brief");
lines.push("");
lines.push(`**Recommendation:** ${recommendation}`);
lines.push(
  `**Confirmed issues:** ${confirmed.length} (${blockers.length} release-blocking: critical/high) from ${totalRaised} raised across the lenses.`
);
lines.push("");
lines.push(
  "> Advisory only. This organ is the immune system, not the gate: it emits a brief and **never** auto-edits, auto-reverts, auto-signs, or auto-submits. **The human holds the deploy gate.**"
);
lines.push("");

for (const lens of LENSES) {
  const items = confirmed.filter((c) => c.lensKey === lens.key);
  lines.push(`## ${lens.title} — ${items.length} confirmed`);
  lines.push("");
  if (items.length === 0) {
    lines.push("_No confirmed blockers in this lens._");
    lines.push("");
    continue;
  }
  for (const it of items) {
    lines.push(
      `### [${String(it.severity || "").toUpperCase()}] ${it.title}`
    );
    lines.push(`- **Where:** \`${it.location}\``);
    lines.push(`- **Why:** ${it.why}`);
    lines.push(`- **Evidence:** ${it.evidence}`);
    if (it.verdict && it.verdict.rationale) {
      lines.push(
        `- **Refuter confirmed** (confidence ${it.verdict.confidence}): ${it.verdict.rationale}`
      );
    }
    lines.push("");
  }
}

lines.push("---");
lines.push(
  recommendation === "NO-GO"
    ? "**NO-GO:** at least one reachable, release-blocking issue is confirmed. Do not submit/deploy until a human resolves the blockers above."
    : "**GO (advisory):** no release-blocking issue survived refutation. This is a reasoned clear, not silence — review the per-lens detail, then the human makes the call."
);
lines.push("");
lines.push("_The human holds the deploy gate._");

const brief = lines.join("\n");

log(
  `Instrument audit done: ${recommendation}. ${confirmed.length} confirmed (${blockers.length} blocking) from ${totalRaised} raised. Human holds the deploy gate.`
);

return brief;
