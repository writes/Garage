# docs/ index

One line per doc: path, what it is, and a freshness caveat where one applies. See the root
`README.md` for the project overview and `HANDOFF.md` for the always-current single next step.

## Top level

- `docs/GARAGE_MASTER_PLAN.md` — living strategy + phased roadmap (generated 2026-06-29).
  Strategy/sequence, not live state; check `HANDOFF.md` for what has actually shipped.
- `docs/DEPLOY_RUNBOOK.md` — operator-only production deploy runbook (secrets, Cloud Functions
  deploy order, Firestore/Storage rules rollout, App Store Connect steps).
- `docs/ARCHIVE.md` — append-only overflow for doctrine bullets superseded out of
  `CLAUDE.md`/`AGENTS.md`/`GEMINI.md`'s "Current State" block. Historical record, never edited
  in place.

## developer/

- `docs/developer/local-setup.md` — environment bootstrap, Firebase project config, dated
  "current state" snapshots (kept refreshed; treat any undated claim as live, dated blocks as
  point-in-time).
- `docs/developer/ANALYTICS_CONTRACT.md` — the frozen analytics event contract; source of truth
  is `Garage/Core/Services/Analytics/AnalyticsService.swift`. Event names are test-enforced.
- `docs/developer/quality/ios-quality-gates.md` — build/test/security gates and what is actually
  machine-enforced vs. convention.
- `docs/developer/quality/ci-command-matrix.md` — the local commands that mirror CI, for running
  the gate scripts by hand.

## operations/

- `docs/operations/release-runbook.md` — environment ownership, release checklist, incident
  handling, and required production dashboards.
- `docs/operations/team-setup.md` — one-time GitHub/Firebase/Apple/RevenueCat setup checklist for
  a new team member or workstation.
- `docs/operations/security/mobile-security-runbook.md` — baseline security controls (App Check,
  ATS, webhook auth, Keychain) and the pre-release security review checklist.

## legal/

- `docs/legal/PRIVACY_POLICY_DRAFT.md` — draft privacy policy grounded in the app's real data
  flows. DRAFT for operator + legal review; bracketed fields are filled at render time.
- `docs/legal/TERMS_OF_USE_DRAFT.md` — draft terms of use. Same DRAFT/legal-review caveat.
- `docs/legal/site.config.json` — the render config (support email, legal entity/address,
  effective date) that `scripts/release/legal_site.py` uses to render the drafts above to the
  hosted legal pages.

## user/

- `docs/user/getting-started.md` — end-user guide: first steps, free vs. Pro feature list,
  offline behavior, glossary.

## release/

- `docs/release/BUILD_4_TESTER_NOTES.md` — point-in-time tester instructions for a specific
  TestFlight build; historical once a newer build ships.
- `docs/release/01-dashboard.png` … `05-settings.png` — App Store screenshot captures used in the
  release/submission process.

## ai/

- `docs/ai/MACHINE_BRAIN_BLUEPRINT.md` — the living self-portrait of the multi-LLM "machine
  brain" installed in this repo (organs, laws, rituals, component map). Kept in sync with
  `scripts/brain/*` and `.claude/` by the BLUEPRINT-SYNC contract in `CLAUDE.md`.

## research-assay/ — the idea graveyard (Law 4 intake)

- `docs/research-assay/audit/REGISTRY.md` — human-readable index of every assayed idea, newest
  first. Check here before evaluating anything new.
- `docs/research-assay/audit/index.jsonl` / `index.schema.json` — the machine-readable twin of
  the registry and its schema.
- `docs/research-assay/audit/tier-a/*.md` — adopted ideas (model routing pins, the profit-first
  strategy review).
- `docs/research-assay/audit/tier-b/*.md` — conditionally promising ideas retained in summary
  (generative vehicle identity monetization, XcodeBuildMCP tooling, the Garage Continuity
  redesign concept).
- `docs/research-assay/audit/tier-c/*.md` — reference-only ideas (10x agentic iOS app builder).
- `docs/research-assay/audit/tier-d/*.md` — killed ideas kept as terse headstones (React/PWA/
  Supabase rewrite, consumer OBD dongle integration, home-maintenance-vault vertical, VODER voice
  suite) — dead ground; do not re-evaluate without new evidence.

All research-assay files are point-in-time verdicts as of their `date:` field; a later re-run of
the same idea should update the existing entry, not fork a new one.

## research/ — pre-registered trials and point-in-time records

`docs/research/README.md` explains the convention: one file per decision/trial, pre-registered
with a hypothesis and death condition before testing, verdict appended after. Every file below is
dated and reflects the repo's state on that date, not necessarily today's:

- `2026-07-10_MODEL_ROUTING_V3.md` — the model-routing lane split (Fable/Sol plan, Terra/Gemini
  implement, tri-review pre-main). Current doctrine; see `CLAUDE.md` §Model Routing.
- `2026-07-10_PRODUCT_EXPANSION_RESEARCH.md` — draft market/pricing/adjacency/usability research
  program, subordinate to the profit-first blueprint below.
- `2026-07-11_PROFIT_FIRST_BLUEPRINT.md` — the governing product blueprint adopted 2026-07-11,
  superseding parts of the expansion research.
- `2026-07-12_DESIGN_STANDARDS.md` — adopted design/production-engineering quality bar.
- `2026-07-21_DESIGN_PERSONALIZATION_MONETIZATION_RESEARCH.md` — advisory design research on
  per-user/per-car personalization; not a build authorization on its own.
- `2026-07-22_PROD_READINESS_AUDIT.md` — the original prod-readiness audit + remediation log.
  Historical record — has a "Status update 2026-07-29" section at the top noting which of its
  blockers are now resolved; the body itself is left unchanged.
- `2026-07-24_SIGNING_CONFIG_PROPOSAL.md` — a proposed `project.yml` (protected-surface) signing
  change. Proposal, not applied.
- `2026-07-24_underhood_concept.html` — the "Underhood" visual design mockup (palette, geometry,
  type ramp, IA) referenced as the design source of truth by the implementation plan below.
- `2026-07-24_UNDERHOOD_IMPLEMENTATION_PLAN.md` — implementation plan mapping the Underhood
  concept onto the codebase. The name "Underhood" itself was rejected pending trademark
  clearance; the design direction was adopted.
- `2026-07-24_underhood_trademark_preclearance.md` — internal trademark pre-clearance research
  (not legal advice) — verdict: name effectively blocked.
- `2026-07-27_BRANDING_AND_LAUNCH_PLAN.md` — branding/design/launch research synthesis; decisions
  pending operator at time of writing.
- `2026-07-27_OPTIMIZATION_BACKLOG.md` — engineering backlog translating the branding/launch plan
  into ranked, status-tracked work items.
- `2026-07-28_RECEIPT_PARSE_PLAN.md` — the approved design for the receipt/invoice capture
  feature. The client shipped and the server function is code-complete but not yet deployed to
  prod (see `docs/GARAGE_MASTER_PLAN.md`).
