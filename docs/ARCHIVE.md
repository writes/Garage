# docs/ARCHIVE.md — append-only doctrine overflow (Organ IV)

> History is never mutated, only **moved** here. When the "Current State" block in
> `CLAUDE.md`/`AGENTS.md`/`GEMINI.md` exceeds its budget (≤10 bullets), the superseded bullet
> is moved here verbatim with a `Moved <date> → §section` citation (one-in-one-out). This is
> the long memory; the doctrine file stays compact and scannable.

## Archived state bullets (newest first)

- **⚖️ SessionStart hook PENDING operator approval** — `.claude/hooks/session-handoff-inject.sh`
  exists; wiring it in `.claude/settings.json` was blocked by the self-modification guard and
  needs the operator's explicit OK (see HANDOFF NEXT ACTION). *(Moved 2026-07-10 → superseded:
  the wiring was in fact committed with the v1 install (`5679a11`) and verified working; the
  bullet was stale — landmine #9.)*
- **🟢 Consensus resolver verified** — `scripts/brain/consensus.py selftest` 17/17 (unanimous /
  2-of-3 no-veto / 1-1-1 highest-confidence fallback / injective canonicalization). Ledger:
  `DECISION_LEDGER.jsonl`. *(Moved 2026-07-10 → replaced by the Model routing v3 bullet
  (one-in-one-out); the 17/17 fact lives on in the blueprint Feature Registry row 1.)*
