# docs/research/ — pre-registration + verdict trial docs (Organ IV)

Per-decision / per-experiment records for **Tier A** ideas (those the intake agent promoted from
`docs/research-assay/audit/`) and for any substantive hypothesis worth a controlled test.

## The rule: pre-register WITH a death condition BEFORE testing

Create one file per trial, **before** running it:

```
docs/research/YYYY-MM-DD_SHORT-TITLE.md
```

It must contain, written *before* you look at the result:

1. **Hypothesis** — "X improves Y via mechanism Z."
2. **Surface & blast radius** — which app surface it touches; what could break.
3. **Method** — exactly how it will be tested (build/test/benchmark/user-flow), and the
   pass/measure definition.
4. **Death condition** — the pre-committed result that KILLS the idea (sends it to the graveyard
   as Tier D). If you can't name one, you aren't ready to test.
5. **Decision link** — the `DECISION_LEDGER.jsonl` row (if a consensus vote gated it).

Then, *after* the test, append:

6. **Verdict** — what happened vs the death condition; promote / kill / iterate.
7. **Graveyard ref** — if killed, the `docs/research-assay/audit/` entry that records it (so it
   is never re-evaluated — Law 4).

> Pre-registration + a death condition is what keeps the multiple-testing count honest and stops
> motivated reasoning from rescuing a dead idea. A verdict here is durable; the compact
> punchline goes into the doctrine "Current State" bullets, the verbose history stays here.

<!-- (no trials yet) -->
