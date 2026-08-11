<!-- MIRROR of CLAUDE.md for OpenAI Codex. Same content; edit all three (CLAUDE.md/AGENTS.md/GEMINI.md) together. -->

# CLAUDE.md — Garage doctrine + machine-brain operating manual

> This file is the **DNA** (Organ IV) of the machine brain installed in this repo.
> It carries the standing rules every agent (any vendor, any session) obeys, plus a
> compact, scannable current-state block. `AGENTS.md` (Codex) and `GEMINI.md` (agy)
> are byte-for-byte mirrors of this file — edit all three together.
> Read `HANDOFF.md` FIRST every session; the full architecture lives in
> `docs/ai/MACHINE_BRAIN_BLUEPRINT.md`.

---

## 0. What this repo is

**Garage** — a native SwiftUI iOS app (Swift 6, iOS 17+, XcodeGen from `project.yml`) for
serious car owners: clean service logs, resale-ready PDF/CSV exports, ownership tracking.
Backend: **Firebase** (Auth, Firestore, Storage, Functions, App Check, Crashlytics,
Messaging) + **RevenueCat** subscriptions + **Claude API** PDF parsing in `CloudFunctions/`
(TypeScript/Node). The native iOS architecture is **locked** (the PWA stack in `blueprint.md`
is product-truth only; it is implemented on native iOS — never re-platform).

Build/verify: `xcodegen generate`; gates `./scripts/ci/{policy-checks,security-checks,verify-ios}.sh`.

---

## 1. The Five Laws (invariants — never violate; a port that breaks one is not this brain)

1. **No solo decisions on substance.** Any substantive decision (architecture, schema, risk,
   security, dependency adoption, release) is voted by ≥3 independent LLMs
   (`claude` + `codex` + `gemini`/agy) → each emits `{decision, reasoning, confidence}` →
   cross-assess → resolve by **2/3 majority, NO veto** → append `DECISION_LEDGER.jsonl`.
   The orchestrator votes but cannot rule.
2. **Durable-by-default state.** If it isn't on disk in a single-responsibility surface, it
   doesn't exist next session. `HANDOFF.md` is read-first, written-last. One fact, one surface.
3. **Sandbox before autonomy.** Autonomous writes happen only inside a git **worktree** behind
   the **scope guard**; the only promoter is the deterministic, agent-immutable CI gate.
4. **Search before evaluating.** Every inbound idea/library/SDK is checked against the graveyard
   (`docs/research-assay/audit/`) first; dead ground is never re-fished.
5. **Adversarial, human-gated verification.** Confirmation is a finder→refuter brief off the
   critical path; **deploys and major verdicts need the operator's switch.**

---

## 2. Standing protocols (the daily rituals)

### CONSENSUS RITUAL (Law 1) — for any substantive decision
1. Pose ONE enumerated question (`A: … | B: … | C: …`).
2. Collect three independent cases. Easiest path:
   ```
   python3 scripts/brain/tri_agent_vote.py \
     --question "…" --options "A: …|B: …" \
     --timestamp "$(date -u +%FT%TZ)"
   ```
   (Polls `claude` + `codex` + `gemini`/agy concurrently — separate rate pools — resolves
   2/3 majority via `scripts/brain/consensus.py`, appends the ledger.)
3. **Calibrate confidence to EVIDENCE** (real verification > docs > intuition). Inflating
   confidence to swing a 1/1/1 fallback is a logged protocol violation (landmine #5).
4. The orchestrator then drives **plan → implement → review** (Organ II).

### MODEL ROUTING (v3 — operator directive 2026-07-10)
Full matrix + Sol-review disposition: `docs/research/2026-07-10_MODEL_ROUTING_V3.md`.
- **Strategy/planning docs:** Fable 5 drafts; **GPT-5.6 Sol** co-reviews before execution
  (`codex exec -m gpt-5.6-sol -`, spec on STDIN). Substantive decisions inside a plan still go
  to the tri-vote (Law 1); planner disagreement **escalates to a vote — never Fable fiat**.
- **Implementation:** **GPT-5.6 Terra** (`codex exec -m gpt-5.6-terra -`) is the single writer;
  **Gemini 3.1 Pro (High)** cross-checks read-only (`dual_agent_loop.py` `stage_cross_check`).
- **Pre-main feature review:** ALL three providers at top strategic tier via
  `python3 scripts/brain/tri_review.py --timestamp "$(date -u +%FT%TZ)"` — Fable 5
  (`--effort high`) + GPT-5.6 Sol + Gemini 3.1 Pro (High). Valid only with 3 schema-conforming
  verdicts from the pinned models; NO-GO/DEGRADED ⇒ remediate & rerun, or operator override in
  the ledger tied to head SHA. Advisory — **the human holds the merge gate** (Law 5).
- **Votes (Law 1):** pinned Fable 5 / GPT-5.6 Sol / Gemini 3.1 Pro (High) in `tri_agent_vote.py`.
- Pins are env-overridable `BRAIN_*` constants. "Gemini Pro Preview" is NOT in the agy roster —
  observation-only watch; adopting any new model label requires Law-4 intake first.

### AUTONOMOUS BUILD RITUAL (Law 3)
- Run inside a worktree via `scripts/brain/dual_agent_loop.py`; the post-turn
  `scripts/brain/scope_guard.py` auto-reverts out-of-scope writes and HALTS on any change to a
  **protected** surface. Never auto-merge — the human holds the deploy gate.
- Concurrency law (landmine #4 — 429s are a concurrency herd, not the cap): **≤4 fat agents**,
  **1 Codex track at a time**, **1 Workflow at a time**. Anthropic / OpenAI / Google are
  separate pools and *may* overlap. Before unattended runs set `CLAUDE_CODE_MAX_RETRIES=20`,
  `API_TIMEOUT_MS=900000`, `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=3`.

### PROMOTION LAW (Law 3) — the CI gate is the sole promoter
A loop result is only a **candidate**. Path: `branch → implement → scope-guard → CI gate
(./scripts/ci/*) → human review → merge → deploy (operator-gated)`. No LLM declares itself
ready; only `scripts/ci/{policy-checks,security-checks,verify-ios}.sh` (build + tests + policy)
promote.

### INTAKE RITUAL (Law 4) — every inbound idea/library/SDK/paper
Run the `research-assay` agent → it **searches the graveyard first** → if new, scores/tiers
(A/B/C/D) and records to `docs/research-assay/audit/`. Only **Tier A** earns a pre-registered
validation spec in `docs/research/YYYY-MM-DD_*.md` (with a death condition).

### VERIFICATION RITUAL (Law 5)
- Post-commit on capital/critical-path files (auth, payments/entitlements, security rules,
  secrets, data-loss, App Check): run `.claude/workflows/async-commit-review.js` → a brief.
- Before a TestFlight/App Store/Cloud-Functions release: run
  `.claude/workflows/instrument-audit.js` (4 lenses) → a GO/NO-GO brief. Output is advisory.

### SESSION RITUALS (Law 2)
- **Start:** read `HANDOFF.md` (the SessionStart hook prints it). If the LOG shows a very recent
  commit by another agent, assume contention and verify shared files before editing.
- **End (mandatory if anything changed):**
  `python3 scripts/brain/session_handoff.py update --by <agent> --summary "…" --next "…"`,
  move any superseded doctrine bullet to `docs/ARCHIVE.md` (one-in-one-out), save a memory file
  for anything non-obvious (`~/.claude/projects/-Users-jt-Code-AppDev/memory/`), commit on a
  feature branch.

---

## 3. Scope guard surfaces (Organ II — keep in sync with `scripts/brain/scope_guard.py`)

- **PROTECTED (never auto-edit; a change → halt + human review):** `Configuration/Secrets.swift`,
  `Garage/Resources/GoogleService-Info.plist`, `CloudFunctions/.env*`, `firebase.firestore.rules`,
  `firebase.storage.rules`, `firebase.json`, `.firebaserc`, `scripts/ci/`, `project.yml` (the
  XcodeGen INPUT — source of truth for targets/signing/bundle IDs; stays PROTECTED. Supersedes the
  2026-06-29 protect-both decision via unanimous tri-agent consensus 2026-07-21, ledger group
  `ea4de5ac0c6fb564`).
- **ALLOWED candidate surface:** `Garage/Features/`, `Garage/Design/`, `Garage/Core/`, `Tests/`,
  `CloudFunctions/src/`, `reports/`, `results/`, `logs/`, `docs/research/`, `Garage.xcodeproj/`
  (GENERATED from `project.yml` by `xcodegen generate` — agents may regenerate it when adding
  sources; promotion safety is the `verify-ios.sh` regenerate-equality gate, not a write ban).
- **Secrets never enter agent prompts or candidate outputs.** The scope check is file-list based,
  so keep protected content out of prompts (landmine #8).

---

## 4. BLUEPRINT-SYNC maintenance contract (standing — Organ IV/§5.1)

> Any change that adds, removes, or materially alters an intelligence-layer surface — a
> voter/backend, a loop archetype, a memory/state surface, a doctrine/budget rule, an
> intake/verification workflow, an agent, or a guardrail — **must update
> `docs/ai/MACHINE_BRAIN_BLUEPRINT.md` in the same commit/PR**: edit the Feature Registry row,
> update the affected organ section + component table, and append a Changelog entry. A commit
> touching `scripts/brain/*`, `.claude/agents/*`, `.claude/workflows/*`, or the doctrine/state
> files without a corresponding blueprint update is **drift** and should be flagged in review.

---

## 5. Required CLIs & landmines (read before you trip — full catalog in the blueprint §10)

**Grok status (2026-08-11, machine doctrine):** `grok` (grok-4.5) is an OPTIONAL advisory CLI on
this machine — NOT a Law-1 voter. The 3-voter roster (`claude`+`codex`+`agy`) is FROZEN pending
`~/.claude/doctrine/evals/` intake; `tri_agent_vote.py` majority math assumes exactly 3 — never
add a 4th voter by fiat. Grok's owned advisory classes: `~/.claude/doctrine/MODEL_LANES.md`.


Voters/tools (all present in this install): `claude` (orchestrator+voter+reviewer),
`codex` (voter+implementer — **always feed prompt on STDIN; bare `codex exec` HANGS**),
`agy` (preferred Gemini voter — **never `agy models` (HANGS); always `agy -p "…"
--print-timeout <T>s < /dev/null`**), `git` (worktrees), `gcloud` (Vertex fallback).
Key landmines: #1 `agy models` hangs · #2 CLIs hang on stdin (always redirect + outer timeout) ·
#4 429 herd (concurrency caps above) · #6 never a null ledger timestamp · #8 secrets can leak
via file content even though the scope check is path-based · #9 verify the *running* image, not
a "deployed ✅" note · #12 agy `--model` **silently downgrades** to "Gemini 3.5 Flash (Medium)"
on any unrecognized value — pin the exact roster label and verify via the resolver line in
`~/.gemini/antigravity-cli/cli.log`, never model self-report · #14 **LLM/build processes LEAK**
(operator directive 2026-07-12): hung codex/agy/`claude -p`/xcodebuild processes survive their
tasks and burn quota silently (observed: 27h agy wrappers, a 44h silent codex mine, stale
xcodebuild runners) — **run `python3 scripts/brain/process_sentinel.py` at session start and
before/after any unattended or long-running LLM work**; every spawn site carries its own
timeout; cross-session suspects are reported to the operator, never killed blindly.

---

## 6. Current State (v1 — 2026-06-29)

> Compact, scannable: verdict + punchline + pointer per bullet. Budget: ≤10 bullets / ≤~600
> chars each. Every appended bullet MOVES a superseded one to `docs/ARCHIVE.md` (one-in-one-out).

- **🟢 Machine brain INSTALLED (v1, 2026-06-29)** — Organs I–V + living blueprint stood up on
  branch `codex/simulator-local-demo`; full tri-agent capability (`claude`+`codex`+`agy` all on
  PATH, no degraded mode). Source map: `docs/ai/MACHINE_BRAIN_BLUEPRINT.md` §5.3.
- **🟢 Model routing v3 LIVE (2026-07-10, operator directive)** — lanes: strategy = Fable 5 +
  GPT-5.6 Sol · implementation = GPT-5.6 Terra + Gemini 3.1 Pro (High) read-only cross-check ·
  pre-main review = all 3 providers via `scripts/brain/tri_review.py` · votes pinned. Enablers:
  codex 0.144.1 (5.6 was 400-ing on 0.143.0), agy 1.1.1. "Gemini Pro Preview" absent from
  roster (watch armed). Spec: `docs/research/2026-07-10_MODEL_ROUTING_V3.md`.
- **🟢 SessionStart hook LIVE (status truth-up 2026-07-10)** — `.claude/settings.json` has
  carried the wiring since the v1 install commit (`5679a11`); verified working (it injects
  HANDOFF at session start). The "pending operator approval" note was stale from day one —
  landmine #9 in the wild.
- **🟢 Intake graveyard live** — `docs/research-assay/audit/` seeded; first verdict recorded:
  "React/PWA/Supabase rewrite" → **Tier D** (doctrine fail: native iOS is locked).
- **🟢 App baseline** — Garage iOS app builds via XcodeGen; CI gate = `scripts/ci/*`; this brain
  install changed **no** app/product code, only added intelligence-layer surfaces.
- **🟢 Profit-first blueprint GOVERNING (2026-07-11, operator directive)** — evidence-verified
  adoption: 12-claim truth table vs live code, 2 new tri-votes (Passport credit REMOVED
  unanimous; vehicle-limit = rules getAfter counter), Q5 naming WITHDRAWN (Roadfolio hard
  collision; Motorkeep impaired — motorkeep.ru), Q4 scrape ToS-prohibited → lawful redesign.
  Consensus resolver enum-grouping defect found+fixed (landmine #13). Plan + P0 waves:
  `docs/research/2026-07-11_PROFIT_FIRST_BLUEPRINT.md`.
