/*
 * ORGAN V — Verification / Workflows ("the immune system")
 * ────────────────────────────────────────────────────────
 * async-commit-review.js — a finder → refuter POST-COMMIT review that runs
 * OFF the blocking path. It never gates a commit; it produces an advisory
 * BRIEF after the fact so a human can decide. This is the cheap, always-on
 * antibody pass for the Garage iOS app (SwiftUI / Swift 6) plus its Firebase
 * Cloud Functions (TypeScript/Node).
 *
 * DISCIPLINE — finder → refuter:
 *   1. SCOPE   — list the changed files for the range under review and bucket
 *                them into "critical-path" (auth, payments/entitlements,
 *                Firestore/Storage rules, secrets, data-loss, App Check) vs
 *                "ordinary". Critical-path is where capital, user data, and
 *                security live.
 *   2. FIND    — parallel finders, one per critical dimension, each surfacing
 *                candidate findings with file:line evidence.
 *   3. REFUTE  — every finding goes to an INDEPENDENT refuter that DEFAULTS to
 *                "not real". A finding is only confirmed when it is BOTH
 *                reachable AND verdict-changing (it could actually ship a
 *                capital / data / security defect). This is what kills the
 *                review-theatre noise that erodes trust in the brief.
 *   4. SYNTH   — assemble a markdown brief, confirmed findings grouped by
 *                severity, with a raised-vs-confirmed count so silent
 *                truncation cannot masquerade as "all clear".
 *
 * OUTPUT IS A BRIEF, NEVER AN AUTO-EDIT. These workflows do not revert, fix,
 * or rewrite anything. The human holds the deploy gate.
 */

export const meta = {
  name: "async-commit-review",
  description:
    "Off-the-blocking-path post-commit finder→refuter review of a git range for the Garage iOS + Firebase app. Emits an advisory brief (confirmed capital/data/security findings); never auto-edits. Human holds the deploy gate.",
  phases: [
    "Scope the diff",
    "Find → Refute (parallel finders, streaming refutation)",
    "Synthesize advisory brief",
  ],
};

// ── helpers ────────────────────────────────────────────────────────────────

// Resolve the git range to review from caller args; default to the last commit.
function resolveRange(input) {
  if (typeof input === "string" && input.trim()) return input.trim();
  if (input && typeof input === "object") {
    if (typeof input.range === "string" && input.range.trim()) {
      return input.range.trim();
    }
    if (typeof input.ref === "string" && input.ref.trim()) {
      return input.ref.trim();
    }
  }
  return "HEAD~1..HEAD";
}

const SEVERITY_ORDER = ["critical", "high", "med", "low"];
function severityRank(sev) {
  const i = SEVERITY_ORDER.indexOf(String(sev || "").toLowerCase());
  return i === -1 ? SEVERITY_ORDER.length : i;
}

// The critical dimensions. Each is its own finder so a noisy dimension cannot
// drown out a quiet-but-lethal one.
const DIMENSIONS = [
  {
    key: "correctness",
    title: "Correctness & logic bugs",
    focus:
      "Swift concurrency misuse (actor isolation, @MainActor violations, data races, unstructured Task leaks), force-unwraps on remote/optional data, off-by-one and boundary errors, mis-ordered async state updates, incorrect error handling that swallows failures, and TypeScript Cloud Functions logic that mis-handles request payloads or async rejections.",
  },
  {
    key: "security_secrets",
    title: "Security & secrets exposure",
    focus:
      "Secrets committed to the repo or baked into the app bundle (Configuration/Secrets.swift, *.xcconfig, GoogleService-Info.plist beyond what is expected, API keys, RevenueCat/Stripe/Anthropic keys), keys logged or sent to the client, missing input validation on Cloud Functions (CloudFunctions/src/functions: claudeProxy.ts, stripeWebhook.ts, nhtsaRecalls.ts), unverified webhook signatures, SSRF/injection in proxied requests, and SecureStore/Keychain misuse in Garage/Core/Services/Security.",
  },
  {
    key: "data_loss",
    title: "Data-loss & persistence",
    focus:
      "Anything that can lose or corrupt user vehicle logs and service history: destructive Firestore writes that overwrite instead of merge, deletes without confirmation/soft-delete, migration/schema changes without backfill, SyncService conflict resolution that drops local edits, CSV/PDF export (Garage/Core/Services/Export) that silently omits rows, and offline cache eviction that discards unsynced data.",
  },
  {
    key: "auth_entitlement",
    title: "Auth & entitlement bypass",
    focus:
      "Authentication and paywall bypass paths: AuthViewModel / FirebaseAuth state handled so an unauthenticated or signed-out user retains access, entitlement checks done only client-side (PurchaseService / RevenueCat) without server enforcement, premium features reachable without an active entitlement, trial/subscription state trusted from the client, and App Check / AppIntegrityService not enforced on privileged Cloud Functions.",
  },
  {
    key: "rules_regression",
    title: "Firestore/Storage rules regressions",
    focus:
      "Security-rules weakening in firebase.firestore.rules / firebase.storage.rules: broadened read/write scopes, ownership checks (request.auth.uid == userId / resource.data.userId) removed or loosened, subcollection rules that no longer verify the parent vehicle owner, wildcard matches that expose other users' data, and rules that allow deletes where data-loss matters.",
  },
];

const FINDER_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["findings"],
  properties: {
    findings: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "title",
          "file",
          "line",
          "severity",
          "dimension",
          "why_it_matters",
          "evidence",
        ],
        properties: {
          title: { type: "string" },
          file: { type: "string" },
          line: { type: ["integer", "string"] },
          severity: { type: "string", enum: ["low", "med", "high", "critical"] },
          dimension: { type: "string" },
          why_it_matters: { type: "string" },
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
      required: ["is_real", "reachable", "confidence", "rationale"],
      properties: {
        is_real: { type: "boolean" },
        reachable: { type: "boolean" },
        confidence: { type: "number", minimum: 0, maximum: 1 },
        rationale: { type: "string" },
      },
    },
  },
};

// ── workflow body ───────────────────────────────────────────────────────────

const range = resolveRange(args);
log(`async-commit-review: reviewing range ${range} (advisory, off the blocking path)`);

// 1) SCOPE ────────────────────────────────────────────────────────────────────
phase("Scope the diff");

const scopeSchema = {
  type: "object",
  additionalProperties: false,
  required: ["critical_path", "ordinary", "summary"],
  properties: {
    critical_path: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["file", "buckets"],
        properties: {
          file: { type: "string" },
          buckets: {
            type: "array",
            items: {
              type: "string",
              enum: [
                "auth",
                "payments",
                "rules",
                "secrets",
                "data-loss",
                "appcheck",
              ],
            },
          },
        },
      },
    },
    ordinary: { type: "array", items: { type: "string" } },
    summary: { type: "string" },
  },
};

const scope = await agent(
  `You are scoping a git diff for the Garage iOS app (SwiftUI/Swift 6, iOS 17+) and its Firebase Cloud Functions (CloudFunctions/, TypeScript/Node).

Run git to enumerate the files changed in the range "${range}". Use commands like:
  git diff --name-status ${range}
  git diff --stat ${range}
(If the range is invalid or empty, fall back to "git show --name-status HEAD" and note it.)

Bucket every changed file. A file is CRITICAL-PATH if it touches any of:
  - auth        -> Garage/Features/Auth, AuthViewModel, FirebaseAuth usage, sign-in/session
  - payments    -> RevenueCat / PurchaseService, entitlements, Garage.entitlements, CloudFunctions stripeWebhook.ts, subscription/trial logic
  - rules       -> firebase.firestore.rules, firebase.storage.rules, Configuration/FirestoreIndexes.json
  - secrets     -> Configuration/Secrets.swift, *.xcconfig, GoogleService-Info.plist, .env*, anything holding keys/tokens
  - data-loss   -> Firestore/Storage persistence, SyncService, vehicle logs / service history models, Export (CSV/PDF), migrations, deletes
  - appcheck    -> App Check, AppIntegrityService, Cloud Functions privilege enforcement
Everything else is ORDINARY.

Return ONLY the structured object. Do not modify any files.`,
  { label: "scope", phase: "Scope the diff", schema: scopeSchema }
);

const criticalFiles = (scope.critical_path || []).map((c) => c.file);
log(
  `Scope: ${criticalFiles.length} critical-path file(s), ${(scope.ordinary || []).length} ordinary. ${scope.summary || ""}`
);

const criticalManifest =
  criticalFiles.length > 0
    ? (scope.critical_path || [])
        .map((c) => `- ${c.file}  [${(c.buckets || []).join(", ")}]`)
        .join("\n")
    : "(scope flagged no obviously critical-path files; still scan the whole diff defensively)";

// 2) FIND -> REFUTE (pipeline, no barrier) ──────────────────────────────────────
// Finders run concurrently across dimensions (pipeline stage 1). As each finder
// returns, its findings stream straight into refutation (stage 2) without
// waiting on the other finders — refutation starts as each finder returns.
phase("Find → Refute (parallel finders, streaming refutation)");

let totalRaised = 0;

async function finderStage(dim) {
  const result = await agent(
    `You are a FINDER auditing a committed git diff for the Garage iOS + Firebase app.
Dimension: ${dim.title}.
Range under review: ${range}.

Scope flagged these critical-path files (prioritise them, but read enough of the diff to reason):
${criticalManifest}

Use git/Read to inspect the actual change, e.g.:
  git diff ${range} -- <file>
  git show ${range}:<file>   (post-change contents)

Hunt specifically for: ${dim.focus}

Rules:
  - Report only issues you can point to with a concrete file and line/anchor in the CHANGED code (or code the change newly exposes).
  - Prefer precision over volume. It is fine to return an empty findings array.
  - severity: critical = ships a capital/data/security defect; high = likely exploitable/lossy; med = real but bounded; low = hygiene.
  - "evidence" must quote or tightly paraphrase the offending lines so a refuter can verify without you.
  - Do NOT edit, fix, or revert anything. Output the structured object only.`,
    {
      label: `find:${dim.key}`,
      phase: "Find → Refute (parallel finders, streaming refutation)",
      schema: FINDER_SCHEMA,
    }
  );
  const findings = (result.findings || []).map((f) => ({
    ...f,
    dimension: f.dimension || dim.title,
    dimKey: dim.key,
  }));
  totalRaised += findings.length;
  log(`Finder [${dim.title}] raised ${findings.length} candidate finding(s).`);
  return { dim, findings };
}

async function refuteStage({ dim, findings }) {
  if (findings.length === 0) return { dim, confirmed: [], raised: 0 };

  // Independent refuter per finding, in parallel — refutation of this
  // dimension's findings proceeds without waiting on other dimensions.
  const verdicts = (
    await parallel(
      findings.map((f) => async () => {
        const out = await agent(
          `You are a REFUTER. Your default stance is that the finding below is NOT real.
You only CONFIRM a finding when it is BOTH:
  (a) reachable in this codebase's real execution / deploy path, AND
  (b) verdict-changing — i.e. it could actually ship a capital, data-loss, or security defect to users.
Style notes, speculative "could be cleaner", and defects gated behind unreachable code do NOT qualify.

Repo: Garage iOS app (SwiftUI/Swift 6) + Firebase Cloud Functions (TypeScript). Range: ${range}.

FINDING TO REFUTE OR CONFIRM:
  dimension: ${f.dimension}
  title: ${f.title}
  file: ${f.file}
  line/anchor: ${f.line}
  claimed severity: ${f.severity}
  why it matters (finder's claim): ${f.why_it_matters}
  evidence: ${f.evidence}

Independently verify against the actual code (use git diff/show and Read on ${f.file} and anything it calls). Decide reachability and whether it is genuinely verdict-changing. Return ONLY the structured verdict. Do not edit anything.`,
          {
            label: `refute:${dim.key}`,
            phase: "Find → Refute (parallel finders, streaming refutation)",
            schema: REFUTER_SCHEMA,
          }
        );
        return { finding: f, verdict: out.verdict };
      })
    )
  ).filter(Boolean);

  const confirmed = verdicts
    .filter((v) => v.verdict && v.verdict.is_real && v.verdict.reachable)
    .map((v) => ({ ...v.finding, verdict: v.verdict }));

  log(
    `Refuter [${dim.title}]: confirmed ${confirmed.length}/${findings.length}.`
  );
  return { dim, confirmed, raised: findings.length };
}

const buckets = await pipeline(DIMENSIONS, finderStage, refuteStage);

// 3) SYNTHESIZE BRIEF ────────────────────────────────────────────────────────
phase("Synthesize advisory brief");

const confirmedAll = [];
for (const b of buckets || []) {
  if (b && b.confirmed) confirmedAll.push(...b.confirmed);
}
confirmedAll.sort((a, b) => severityRank(a.severity) - severityRank(b.severity));

const confirmedCount = confirmedAll.length;

function fixDirection(f) {
  // One-line direction, never an applied edit.
  switch (f.dimKey) {
    case "rules_regression":
      return "Restore the ownership/scope check in the security rules and re-test with the emulator before any deploy.";
    case "auth_entitlement":
      return "Enforce the auth/entitlement check server-side (Cloud Function + rules + App Check), not on the client alone.";
    case "data_loss":
      return "Make the write merge/soft-delete and confirm an unsynced-data path exists before this can land.";
    case "security_secrets":
      return "Remove the secret from the bundle/repo, rotate it, and validate/verify inputs & webhook signatures server-side.";
    default:
      return "Confirm the logic against the intended behaviour and add a regression test for the changed path.";
  }
}

const lines = [];
lines.push("# Async Commit Review — Advisory Brief");
lines.push("");
lines.push(`**Range:** \`${range}\``);
lines.push(
  `**Findings:** ${totalRaised} raised → ${confirmedCount} confirmed (reachable + verdict-changing).`
);
lines.push(
  `**Critical-path files in diff:** ${criticalFiles.length}${criticalFiles.length ? " (" + criticalFiles.join(", ") + ")" : ""}`
);
lines.push("");
lines.push(
  "> Advisory only. This organ is the immune system, not the gate: it emits a brief and **never** auto-edits, auto-reverts, or auto-fixes. **A human holds the deploy gate.**"
);
lines.push("");

if (confirmedCount === 0) {
  lines.push("## No confirmed findings");
  lines.push("");
  lines.push(
    `No findings survived refutation. Note ${totalRaised} candidate(s) were raised and refuted, so this is a reasoned "clear", not silence.`
  );
} else {
  let lastSev = null;
  for (const f of confirmedAll) {
    const sev = String(f.severity || "").toLowerCase();
    if (sev !== lastSev) {
      lines.push(`## ${sev.toUpperCase()}`);
      lines.push("");
      lastSev = sev;
    }
    lines.push(`### ${f.title}`);
    lines.push(`- **Where:** \`${f.file}:${f.line}\`  _(dimension: ${f.dimension})_`);
    lines.push(`- **Why it matters:** ${f.why_it_matters}`);
    lines.push(`- **Evidence:** ${f.evidence}`);
    if (f.verdict && f.verdict.rationale) {
      lines.push(
        `- **Refuter confirmed** (confidence ${f.verdict.confidence}): ${f.verdict.rationale}`
      );
    }
    lines.push(`- **Fix direction:** ${fixDirection(f)}`);
    lines.push("");
  }
}

const brief = lines.join("\n");

const bySev = SEVERITY_ORDER.map((s) => {
  const n = confirmedAll.filter(
    (f) => String(f.severity || "").toLowerCase() === s
  ).length;
  return `${s}:${n}`;
}).join(" ");
log(
  `Brief ready for ${range}. ${totalRaised} raised → ${confirmedCount} confirmed (${bySev}). Advisory only; human holds the deploy gate.`
);

return brief;
