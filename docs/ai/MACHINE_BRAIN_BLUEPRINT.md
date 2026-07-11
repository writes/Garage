# THE MACHINE-ENABLED BRAIN — Garage instance (self-portrait)

> **This repository is now an instance of the portable multi-LLM "machine brain."** This file
> is its living self-portrait: it both **describes** the brain (organs, laws, rituals) and
> **maps** it to the exact surfaces installed here in the Garage iOS repo. It is kept honest by
> the BLUEPRINT-SYNC maintenance contract (§5.1) — any change to an intelligence surface updates
> this file in the same commit.
>
> Doctrine: `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`. State: `HANDOFF.md`. Decisions:
> `DECISION_LEDGER.jsonl`. Installed: 2026-06-29 on branch `codex/simulator-local-demo`.

---

## 0. TL;DR — the brain in five sentences

1. **Many minds, one resolver.** Every substantive decision is voted by 3 independent LLMs
   (`claude`/`codex`/`agy`) emitting `{decision, reasoning, confidence}`, then resolved by
   deterministic **2/3 majority — no veto** — appended forever to `DECISION_LEDGER.jsonl`.
2. **Memory is files, not context.** State survives session death on disk: `HANDOFF.md`,
   the doctrine files, the append-only ledger, the cross-session memory home, the graveyard.
3. **Loops are sandboxed.** Autonomous work runs in git worktrees behind `scope_guard.py`; the
   sole promoter is the deterministic CI gate (`scripts/ci/*`) — agents write candidates, never
   the gate, secrets, or prod config.
4. **Nothing dead is re-evaluated.** Every inbound idea/library is assayed once, tiered A/B/C/D,
   and recorded in `docs/research-assay/audit/` — searched *before* evaluating.
5. **Verification is adversarial and off the critical path.** Quality comes from finder→refuter
   workflows; the operator keeps the deploy switch.

---

## 1. The brain diagram

```
              ┌────────────────────────── OPERATOR (human) ──────────────────────────┐
              │      poses questions · gates deploys/releases · holds the kill        │
              └─────────────┬───────────────────────────────────────┬────────────────┘
                            │ question                               │ approval
                            ▼                                        │
  ╔══════════════════════════════════════════════════╗              │
  ║  I. CONSENSUS (cortex)                            ║              │
  ║  claude(Opus) · codex(GPT) · agy(Gemini/Ultra)    ║              │
  ║   → {decision,reasoning,confidence} → cross-assess║              │
  ║   → consensus.py resolve_majority (2/3, no veto)  ║──┐           │
  ╚═══════════════════════╪═══════════════════════════╝  │           │
                          │ winning decision              │           │
                          ▼                               │           │
  ┌────────────────────────────────────────────┐         │           │
  │ II. LOOPING (motor)                         │         │           │
  │  plan(claude)→implement(codex)→review(claude)│        │           │
  │  in git WORKTREE behind scope_guard.py       │        │           │
  │           │ candidate                        │        │           │
  │           ▼                                   │        │           │
  │  CI GATE scripts/ci/* (sole promoter) ────────┼────────┼──────────►│ release
  └───────────┬─────────────────────────────────┘         │      (operator-gated)
              │ evidence                                    │
              ▼                                             │
  ┌────────────────────────────────────────────┐           │
  │ V. VERIFICATION (immune system)             │◄──────────┘
  │  async-commit-review · instrument-audit     │
  │  finder→refuter → BRIEF (never auto-revert)  │
  └───────────┬─────────────────────────────────┘
              │ confirmed findings (brief)
              ▼
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │ III. MEMORY (hippocampus)                      IV. DOCUMENTATION (DNA)        │
  │  HANDOFF.md + session_handoff.py               CLAUDE/AGENTS/GEMINI.md        │
  │  memory/*.md + MEMORY.md (cross-session)       docs/research/ (pre-reg+verdict)│
  │  DECISION_LEDGER.jsonl (votes)                 docs/ARCHIVE.md (overflow)      │
  │  research-assay/audit (idea graveyard)         THIS blueprint (self-portrait)  │
  │       ▲ SessionStart hook injects HANDOFF (pending operator wiring)            │
  └─────────────────────────────────────────────────────────────────────────────┘
```

**Read it as a metabolism:** ideas enter through intake, survivors become questions, the cortex
votes, the motor builds in a sandbox, the immune system tries to refute, the CI gate promotes,
the operator releases, and **every step writes durable memory** so the next session starts
smarter than the last.

---

## 2. The five organs (generic core vs domain skin)

### I. Consensus — *the cortex*
**Job:** turn a hard question into an auditable decision no single model (not even the
orchestrator) can dictate. **Mechanism:** 3 independent voters → `{decision, reasoning,
confidence∈[0,1]}` → cross-assessment → `resolve_majority`. **Law:** 3/3 unanimous · 2/3
majority wins (a high-confidence dissenter cannot veto) · 1/1/1 → deterministic
highest-confidence fallback + a `needs_second_round` flag. **Calibration is the integrity
surface** (confidence tracks evidence; inflation is logged). **Here:**
`scripts/brain/consensus.py` (pure resolver, 17/17 self-test), `scripts/brain/gemini_consult.py`
(agy→Vertex→API voter), `scripts/brain/tri_agent_vote.py` (live 3-voter runner), ledger
`DECISION_LEDGER.jsonl`. *Domain skin:* the prompts + what counts as "substantive."

### II. Looping — *the motor*
**Job:** large unattended work that can never damage anything that matters. **Cycle:**
plan(claude) → implement(codex) → review(claude), each turn in a git worktree, with a post-turn
scope check that auto-reverts out-of-scope writes and halts on protected-surface changes.
**Promotion law:** a loop result is only a candidate; the deterministic CI gate is the sole
promoter. **Here:** `scripts/brain/dual_agent_loop.py` + `scripts/brain/scope_guard.py`; the
gate is `scripts/ci/{policy-checks,security-checks,verify-ios}.sh`. *Domain skin:* the protected/
allowed prefixes (§3) and the iOS/Firebase build+test gate.

### III. Memory — *the hippocampus*
**Job:** make session death a non-event; each fact in exactly one place. `HANDOFF.md` = thin
"what just happened / next / who's touching what." Doctrine = compact current state. Ledger =
append-only votes. Graveyard = idea verdicts. `memory/` = cross-session facts. `docs/research/`
= pre-reg + verdict. `docs/ARCHIVE.md` = overflow. **No surface duplicates another; HANDOFF only
points.** A SessionStart hook injects HANDOFF every session. Budgets prevent rot (≤10 doctrine
bullets, one-in-one-out archive). **Here:** all generic — `HANDOFF.md` +
`scripts/brain/session_handoff.py`, memory home
`~/.claude/projects/-Users-jt-Code-AppDev/memory/`. *Domain skin:* only the content.

### IV. Documentation — *the DNA*
**Job:** encode doctrine + verdicts so durably any agent/vendor/session reconstitutes the same
operating mind. Doctrine file (one per vendor, same content) carries standing rules + compact
state. Per-trial docs are pre-registered *with a death condition* before testing, verdict after.
Archive is append-only overflow. **Here:** `CLAUDE.md`/`AGENTS.md`/`GEMINI.md` (mirrors),
`docs/research/`, `docs/ARCHIVE.md`, this blueprint. *Domain skin:* the doctrine text + trial
template.

### V. Verification — *the immune system*
**Job:** catch the defect the syntax-only commit gate can't see — adversarially, off the
blocking path. **finder → refuter** is the unit: one agent hunts, an independent agent defaults
to "not real" and confirms only what is reachable + verdict-changing. **Here:**
`.claude/agents/research-assay.md` (6-stage skeptical intake → A/B/C/D),
`docs/research-assay/audit/` (graveyard, search-before-evaluating),
`.claude/workflows/async-commit-review.js` (post-commit, capital/critical-path) and
`.claude/workflows/instrument-audit.js` (pre-release, 4 lenses). Output is a brief, never an
auto-revert; the operator holds the deploy gate. *Domain skin:* what "capital-relevant"/
"release-blocking" means for an iOS+Firebase app (auth, payments/entitlements, security rules,
secrets, data-loss, App Check, privacy manifest).

---

## 3. The five laws (invariants that survive porting)

1. **No solo decisions on substance.** ≥3 independent voters, deterministic 2/3 majority, no
   veto, logged. The orchestrator votes but cannot rule.
2. **Durable-by-default state.** If it isn't on disk in a single-responsibility surface, it
   doesn't exist next session. HANDOFF is read-first, written-last.
3. **Sandbox before autonomy.** Autonomous writes happen only in a worktree behind the scope
   guard; the only promoter is the deterministic, agent-immutable CI gate.
4. **Search before evaluating.** Every idea is checked against the graveyard first.
5. **Adversarial, human-gated verification.** Confirmation is a finder/refuter brief off the
   critical path; releases and major verdicts need a human switch.

---

## 4. Component reference — generic core vs domain skin (this install)

| Organ | File / surface | Portability | Responsibility |
|---|---|:--:|---|
| I | `scripts/brain/consensus.py` | ✅ copy | Pure 2/3 resolver + `append_ledger_majority`; injective canonicalization; 17/17 self-test |
| I | `scripts/brain/gemini_consult.py` | ✅ copy | Headless Gemini voter: agy (pinned `"Gemini 3.1 Pro (High)"` — landmine #12)→Vertex→API ladder, JSON out |
| I | `scripts/brain/tri_agent_vote.py` | ✅ copy | Live 3-voter runner (Fable 5 / GPT-5.6 Sol / Gemini 3.1 Pro High; concurrent pools) → resolve → ledger |
| I | `DECISION_LEDGER.jsonl` | ✅ schema | Append-only resolved decisions (one JSON/line) |
| II | `scripts/brain/dual_agent_loop.py` | ◐ adapt | Worktree plan(Fable 5)⇄implement(GPT-5.6 Terra)⇄cross-check(Gemini, read-only)⇄review(Fable 5) + scope enforce |
| II | `scripts/brain/scope_guard.py` | ◐ adapt | Protected/allowed/protocol classifier + auto-revert |
| II | `scripts/ci/{policy,security,verify-ios}-checks.sh` | ✗ domain | Immutable promotion gate (build+tests+policy) — pre-existing |
| III | `HANDOFF.md` + `scripts/brain/session_handoff.py` | ✅ copy | Thin cross-agent state + `--status`/`--init`/`update` CLI |
| III | `~/.claude/projects/-Users-jt-Code-AppDev/memory/*.md` + `MEMORY.md` | ✅ schema | Cross-session fact base, frontmatter + wikilinks + index |
| III | `.claude/hooks/session-handoff-inject.sh` (+ settings wiring) | ✅ copy | SessionStart HANDOFF injection (LIVE — wired in `.claude/settings.json` since v1 install) |
| IV | `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` | ◐ adapt | Doctrine + ≤10 compact state bullets (budgeted, mirrored) |
| IV | `docs/research/YYYY-MM-DD_*.md` | ◐ adapt | Pre-reg (with death condition) + verdict per trial |
| IV | `docs/ARCHIVE.md` | ✅ copy | One-in-one-out doctrine overflow, append-only |
| IV | `docs/ai/MACHINE_BRAIN_BLUEPRINT.md` | ✅ copy | This self-portrait |
| V | `.claude/agents/research-assay.md` | ◐ adapt | 6-stage skeptical intake → tier A/B/C/D → audit record |
| V | `docs/research-assay/audit/{REGISTRY.md,index.jsonl,index.schema.json,tier-*}` | ✅ schema | Idea graveyard; search-before-evaluating DB |
| V | `.claude/workflows/async-commit-review.js` | ◐ adapt | Post-commit finder→refuter on capital/critical-path files |
| V | `.claude/workflows/instrument-audit.js` | ◐ adapt | Pre-release 4-lens finder→refuter GO/NO-GO brief |
| V | `scripts/brain/tri_review.py` | ✅ copy | Pre-main tri-provider merge-readiness review (Fable 5 `--effort high` + GPT-5.6 Sol + Gemini 3.1 Pro High) → advisory GO/NO-GO brief; SHA-bound, fail-closed secret screen |

`✅ copy` = portable as-is · `◐ adapt` = portable structure, swap content · `✗ domain` = rebuild
the pattern for your domain.

### Required external CLIs (all present in this install — no degraded mode)
`claude` (orchestrator+voter+reviewer) · `codex` (voter+implementer — **prompt on STDIN
always**; ≥0.144.1 for GPT-5.6) · `agy` (preferred Gemini voter — **never `agy models`**) ·
`git` (worktrees) · `gcloud` (Vertex fallback).

**Model routing v3 (operator directive 2026-07-10 —
`docs/research/2026-07-10_MODEL_ROUTING_V3.md`):** strategy/planning docs = Fable 5 draft +
GPT-5.6 Sol co-review; consensus votes = Fable 5 / GPT-5.6 Sol / Gemini 3.1 Pro (High);
implementation = GPT-5.6 Terra (single writer) + Gemini 3.1 Pro (High) read-only cross-check;
pre-main review = all three providers at top strategic tier via `tri_review.py`. Pins are
env-overridable `BRAIN_*` constants in the scripts. "Gemini Pro Preview" is absent from the agy
roster (observation-only watch armed; adoption requires Law-4 intake).

### Concurrency / rate-limit law
429s are a transient concurrency herd, not the cap. **≤4 fat agents · 1 Codex track · 1 Workflow
at a time.** Anthropic/OpenAI/Google are separate pools and may overlap. Before unattended runs:
`CLAUDE_CODE_MAX_RETRIES=20`, `API_TIMEOUT_MS=900000`, `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=3`.

---

## 5. The living blueprint — *this doc grows with the repo*

### 5.1 The maintenance contract (standing — mirrored in the doctrine files)

> **BLUEPRINT-SYNC (standing).** Any change that adds, removes, or materially alters an
> intelligence-layer surface — a voter/backend, a loop archetype, a memory/state surface, a
> doctrine/budget rule, an intake/verification workflow, an agent, or a guardrail — **must
> update this file in the same commit/PR**: (1) edit the Feature Registry row (§5.3), (2) update
> the affected organ (§2) + component table (§4), (3) append a Changelog entry (§5.4). A commit
> touching `scripts/brain/*`, `.claude/agents/*`, `.claude/workflows/*`, or the doctrine/state
> files without a corresponding blueprint update is **drift** and should be flagged in review.

### 5.2 The reconciliation ritual (catch drift)

Periodically (a `/loop` cadence or on demand) run a completeness-critic pass that diffs the
repo's actual intelligence surfaces against this blueprint: enumerate `scripts/brain/*`,
`.claude/agents/*`, `.claude/workflows/*`, the audit dirs, the state surfaces, the doctrine
files; parse the Feature Registry (§5.3) + component table (§4); diff both ways (*in repo, not
in blueprint* → add a row; *in blueprint, not in repo* → mark removed/moved). Emit a brief,
never an auto-edit beyond appending rows the human confirms (Law 5).

### 5.3 Feature Registry — *the source-of-truth map (extend on every feature)*

| # | Capability | Organ | Source of truth | § | Status | Added |
|---|---|:--:|---|---|---|---|
| 1 | 2/3-majority resolver (no veto) + injective + enum-anchored canonicalization | I | `scripts/brain/consensus.py:resolve_majority` (`options=` roster param) | §2.I,§4 | LIVE (24/24) | 2026-06-29 (enum fix 2026-07-11) |
| 2 | Gemini voter (agy→Vertex→API) | I | `scripts/brain/gemini_consult.py` | §2.I,§4 | LIVE | 2026-06-29 |
| 3 | Live tri-agent vote runner (concurrent pools) | I | `scripts/brain/tri_agent_vote.py` | §2.I,§4 | LIVE | 2026-06-29 |
| 4 | Decision ledger (append-only) | I | `DECISION_LEDGER.jsonl` | §2.I,§8 | LIVE | 2026-06-29 |
| 5 | Cross-agent handoff + CLI | III | `HANDOFF.md`, `scripts/brain/session_handoff.py` | §2.III,§8 | LIVE | 2026-06-29 |
| 6 | SessionStart HANDOFF injection | III | `.claude/hooks/session-handoff-inject.sh` (+ settings) | §2.III,§9 | LIVE (wired since `5679a11`; status truth-up 2026-07-10) | 2026-06-29 |
| 7 | Cross-session file memory + index | III | `~/.claude/projects/-Users-jt-Code-AppDev/memory/`, `MEMORY.md` | §2.III,§8 | LIVE | 2026-06-29 |
| 8 | Doctrine (mirrored) + compact state + budget | IV | `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `docs/ARCHIVE.md` | §2.IV,§9 | LIVE | 2026-06-29 |
| 9 | Pre-reg + verdict trial docs | IV | `docs/research/` | §2.IV,§8 | LIVE | 2026-06-29 |
| 10 | Worktree plan⇄impl⇄review loop | II | `scripts/brain/dual_agent_loop.py` | §2.II | LIVE | 2026-06-29 |
| 11 | Scope guard (protected/allowed/protocol + auto-revert) | II | `scripts/brain/scope_guard.py` | §2.II,§3 | LIVE | 2026-06-29 |
| 12 | Immutable promotion gate (build+tests+policy) | II | `scripts/ci/{policy,security,verify-ios}-checks.sh` | §2.II | LIVE (pre-existing) | 2026-06-29 |
| 13 | Research-assay skeptical intake agent | V | `.claude/agents/research-assay.md` | §2.V,§8 | LIVE | 2026-06-29 |
| 14 | Intake graveyard (audit DB + schema) | V | `docs/research-assay/audit/{REGISTRY.md,index.jsonl,index.schema.json,tier-*}` | §2.V,§8 | LIVE (1 verdict) | 2026-06-29 |
| 15 | Async-commit-review workflow | V | `.claude/workflows/async-commit-review.js` | §2.V | LIVE | 2026-06-29 |
| 16 | Instrument-audit (pre-release, 4 lenses) | V | `.claude/workflows/instrument-audit.js` | §2.V | LIVE | 2026-06-29 |
| 17 | **This blueprint (self-referential)** | — | `docs/ai/MACHINE_BRAIN_BLUEPRINT.md` | all | LIVE | 2026-06-29 |
| 18 | Pre-main tri-provider review (Law 5) | V | `scripts/brain/tri_review.py` | §2.V,§4 | LIVE | 2026-07-10 |
| 19 | Model routing v3 (lane-split collective) | IV | `docs/research/2026-07-10_MODEL_ROUTING_V3.md` + doctrine §2 + `BRAIN_*` pins in `scripts/brain/*` | §4 | LIVE | 2026-07-10 |

### 5.4 Changelog (append-only; newest first)

- **2026-07-11** — **Resolver canonicalization defect found live and fixed (landmine #13
  candidate → registered below).** A Law-1 vote (vehicle-limit mechanism) mis-resolved: gemini's
  bare `"A"` and claude's `"A: <full text>"` hashed to different groups, so a true 2/3 majority
  fell to the `highest_confidence_no_majority` fallback and the lone dissenter won — a
  functional veto. Fix: `consensus.py` gained `enum_option_map`/`resolve_enum` and an
  `options=` roster param on `resolve_majority`/`append_ledger_majority` (letter-anchored
  grouping: bare letters, `A:`/`b)`/`C -` variants, and echoed option bodies group; hedged
  "A and B" and out-of-roster letters never map). `tri_agent_vote.py` passes its parsed roster
  through (incl. `degraded_pair_agrees`). Self-test 17→24 cases, all green; the recorded
  positions replay to majority A; correction row appended to the ledger (protocol
  `resolution_correction`, 2026-07-11T17:47:57Z). Ledger audit: 1 flipped vote (corrected),
  9 understated-consensus rows (decisions unaffected).

- **2026-07-10 (later)** — **Routing v3 hardened through 11 live tri-reviews / 12 Terra passes
  (R1–R56)**; sync note: R17–R56 shipped across several commits during the review loop, squared
  here. Highlights: Sol plan co-review stage (fail-closed, governed bypass) + Gemini read-only
  cross-check (empty-cwd, zero-delta halt) in `dual_agent_loop.py`; resolver-log model
  verification on every agy call (symlink/inode-bound, flock-serialized — landmine #12);
  fail-closed secret screening on ALL provider-bound evidence incl. loop stages, with
  redact-on-write for provider outputs; ROSTER allowlist gating every lane (env overrides are
  recorded operator acts); DECISION_LEDGER enforcement is append-only (revert+halt otherwise);
  tri-votes TV1 (3 live voters or `--allow-degraded`+agreement) and TV2 (fallback = dead voter)
  implemented in `tri_agent_vote.py`; coverage-gated advisory resolution + bounded verdicts in
  `tri_review.py` (selftest 62/62). Two SessionStart/consensus status truth-ups. Decision brief
  + full disposition history: `docs/research/2026-07-10_MODEL_ROUTING_V3.md` §7–§19; 11 briefs
  under `reports/tri-review/`.

- **2026-07-10** — **Model routing v3 (lane-split collective)** per operator directive: strategy
  /planning = Fable 5 + GPT-5.6 Sol; implementation = GPT-5.6 Terra + Gemini 3.1 Pro (High)
  read-only cross-check (new `stage_cross_check` in `dual_agent_loop.py`); pre-main review = all
  three providers at top strategic tier (new `scripts/brain/tri_review.py`, registry #18:
  SHA-bound evidence, fail-closed protected-path + secret screening, strict verdict JSON,
  advisory-only). Voter pins in `tri_agent_vote.py`/`gemini_consult.py`. Spec + Sol review
  disposition: `docs/research/2026-07-10_MODEL_ROUTING_V3.md`. Enablers: codex CLI 0.143.0 →
  0.144.1 (GPT-5.6 was 400-ing on 0.143.0), agy 1.1.1. New landmine #12 (agy silent model
  downgrade). "Gemini Pro Preview" absent from roster — substitution flagged to operator, watch
  armed. Implemented by GPT-5.6 Terra in a supervised worktree (spec §4.6); tri-reviewed
  pre-merge by all three providers.

- **2026-06-29** — **Brain installed (v1) into the Garage iOS repo** (branch
  `codex/simulator-local-demo`). Greenfield install, all 6 phases, full tri-agent capability
  (`claude`+`codex`+`agy` all on PATH). Organs I–V + this blueprint stood up under
  `scripts/brain/`, `.claude/`, `docs/`. Consensus resolver verified 17/17; intake graveyard
  seeded with the first verdict (React/PWA/Supabase rewrite → Tier D, doctrine-fail: native iOS
  is locked). One item deferred to operator approval: wiring the SessionStart hook into
  `.claude/settings.json` (blocked by the self-modification guard). Live tri-agent consensus
  verification recorded in `DECISION_LEDGER.jsonl`. Added **no** app/product code — only
  intelligence-layer surfaces; the CI gate remains the sole promoter.

---

## 6. Phased install plan (companion to §5)

Installed inside-out: **state first** (HANDOFF + session_handoff + memory + empty ledger/archive)
→ **DNA** (doctrine mirrors + docs/research + maintenance contract) → **cortex**
(consensus.py + gemini_consult.py + tri_agent_vote.py) → **motor** (scope_guard + dual_agent_loop,
CI gate as promoter) → **immune system** (research-assay + graveyard + 2 workflows) →
**this blueprint**.

| Phase | Installed | Done when |
|---|---|---|
| 0 | State report + plan | ✅ inventory done, greenfield confirmed |
| 1 | HANDOFF + session_handoff + (hook) + memory + ledger/archive | ✅ status shows prior state; hook **pending wiring** |
| 2 | Doctrine mirrors + compact-state budget + docs/research | ✅ |
| 3 | consensus.py + gemini_consult.py + tri_agent_vote.py + ritual | ✅ 17/17; live vote ledgered |
| 4 | scope_guard + dual_agent_loop + promotion gate | ✅ scope-guard self-test green |
| 5 | research-assay + graveyard + finder/refuter workflows | ✅ 1 verdict recorded |
| 6 | This blueprint + registry + maintenance contract | ✅ |

---

## 7. Operating rituals (the daily loop) — see `CLAUDE.md` §2 for the canonical copy

Session start (read HANDOFF) · inbound idea (research-assay, search graveyard first) ·
substantive decision (`tri_agent_vote.py` → ledger → plan/impl/review) · pre-test (pre-register
with a death condition) · autonomous build (worktree + scope guard + CI gate) · post-commit
(async-commit-review) · pre-release (instrument-audit) · new intelligence feature (BLUEPRINT-SYNC)
· session end (`session_handoff.py update` + memory + archive + commit on a feature branch).

---

## 8. Drop-in templates

See `CLAUDE.md` for the live doctrine and the §8 templates of the canonical blueprint
(HANDOFF marker layout, memory frontmatter, `DECISION_LEDGER.jsonl` row, intake `index.jsonl`
row + scoring rubric, scope-guard prefix lists). In this install those templates are already
instantiated: HANDOFF.md, the memory home, the ledger, `docs/research-assay/audit/index.schema.json`,
and `scripts/brain/scope_guard.py`.

---

## 9. Landmine catalog (scar tissue — read before you trip)

| # | Landmine | Guard |
|---|---|---|
| 1 | `agy models` HANGS forever | Never call it; only `agy -p "…" --print-timeout <T>s < /dev/null` |
| 2 | `codex exec` / `agy` / `claude` hang on stdin | Always redirect/pipe; bound with an outer timeout |
| 3 | Free `@google/gemini-cli` OAuth dead for individuals | Use `agy` / Vertex ADC / `GEMINI_API_KEY` |
| 4 | 429 herd kills fan-outs | ≤4 fat agents · 1 Codex track · 1 Workflow; separate pools may overlap |
| 5 | Confidence inflation to win a 1/1/1 fallback | Logged protocol violation; calibrate to evidence |
| 6 | Ledger row with null timestamp | Always pass an explicit ISO8601 timestamp |
| 7 | Vote canonicalization non-injective on delimiters | Hash a normalized structure, never a raw join (consensus.py does this) |
| 8 | Scope check is file-list based — secrets can leak in content | Never pass secrets to agents; keep protected surfaces out of prompts |
| 9 | "Deployed ✅" trusted without checking the running image | Verify consumption, not presence; probe the deployed image |
| 10 | HANDOFF/doctrine duplicated instead of pointed-to | HANDOFF only points; one fact, one surface; obey the budget |
| 11 | Blueprint drifts behind the repo | The maintenance contract (§5.1) + reconciliation ritual (§5.2) |
| 12 | agy `--model` with an unrecognized value silently downgrades to "Gemini 3.5 Flash (Medium)" — no error | Pin the exact roster label (`"Gemini 3.1 Pro (High)"`); after changing a pin, verify the resolver line in `~/.gemini/antigravity-cli/cli.log`, never model self-report |
| 13 | Voters answer the same option in different shapes (bare "A" vs "A: full text" vs echoed body) — string-hash grouping splits a real majority and the confidence fallback hands the lone dissenter a veto | Pass the enumerated option roster into `resolve_majority(options=)` (tri_agent_vote does since 2026-07-11); watch any `highest_confidence_no_majority` row whose positions contain bare letters — it may be a mis-resolution, not a true 1/1/1 |

---

*The repo is the brain. This file is its self-portrait — keep it honest and it keeps the brain
reproducible. Every session should leave it, and the system it describes, a little sharper than
it found them.*
