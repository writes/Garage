# Ask-Garage cost/latency probe — 2026-08-07

The prerequisite named by the 2026-08-06 grounding eval (PR #59) before any Law-1 scheduling
vote: measure per-turn **cost** and **latency** for the two levers that passed the quality gate.
Raw data: `reports/askgarage-cost-probe.json` (per-call usage + latency for all 90 live calls);
harness: `CloudFunctions/scripts/askGarageCostProbe.ts` (reuses the eval's exact `systemFor`
prompt construction — one source of truth, no drift).

## Method

- **Exact input baselines** via `/v1/messages/count_tokens` per (vehicle × lever) — required
  because Sonnet 5 uses a different tokenizer than Haiku 4.5, so no shared count is valid.
- **One live sweep**: all 45 golden questions × 1 run per lever, `usage` and wall-clock latency
  from the API itself. Sonnet 5 runs adaptive thinking by default and thinking bills as output
  tokens, so output cost/latency are only measurable live.
- Pricing: Haiku 4.5 $1/$5 per MTok; Sonnet 5 **intro $2/$10 through 2026-08-31**, then $3/$15.
  (Launch window straddles the intro cliff — both reported.)

## Results

| axis | Haiku+computed-aggregates | Sonnet-grounded |
|---|---|---|
| quality (from PR #59) | 96% answerable, 0 leaks, 2 lookup regressions | **100% answerable, 0 leaks, zero variance** |
| mean tokens/turn (in / out) | 2432 / 53 | 2395 / 97 |
| latency p50 / p90 / max | **1.24s / 2.17s / 2.61s** | 3.31s / 4.33s / 6.58s |
| $/turn uncached | **$0.00270** | $0.00576 intro · $0.00864 standard |
| $/1k user-days @ 5 q/day | **$13.49** | $28.80 intro · $43.21 standard |
| $/user-month @ full 5 q/day quota | ~$0.40 | ~$0.86 intro · ~$1.30 standard |
| prompt-cache eligibility | **NONE** — all 3 vehicles below Haiku's 4096-token floor | all 3 vehicles clear Sonnet's 1024-token floor |
| extra build surface | server-side aggregates computation (new correctness surface, must be tested per aggregate class) | none — serialize log only |

## Findings

1. **Cost does not differentiate the levers.** At the profit-first quota (5 AI questions/day),
   worst case is Sonnet standard at ~$1.30/user-month at 100% quota utilization — real
   utilization will be a fraction of that. Both levers are rounding errors against Pro revenue.
2. **The real trade is latency vs quality vs build surface.** Haiku answers in ~1.2s but needs
   the server-side computed-aggregates block built and tested (the eval showed that block is
   *load-bearing* — grounded-only Haiku fails at 82% with fabrication leaks), and it cost 2
   lookup regressions (attention dilution). Sonnet is ~3.3s p50 full-completion (streaming
   TTFT will feel faster in UI), is 100%/0-leak with zero variance, and needs no aggregates
   component at all.
3. **Prompt caching is a Sonnet-only lever at typical history sizes.** Haiku 4.5's minimum
   cacheable prefix is 4096 tokens; none of the three synthetic vehicles (105 entries total)
   reach it, so the "cached" column for Haiku is unachievable today — do not count it in any
   plan. Sonnet's 1024 floor is cleared by every vehicle; multi-turn conversations on Sonnet
   would pay ~0.1× on the history span (measured cache-read turn: $0.00149 intro).
4. **Honest caveats.** Latencies are full-completion without streaming; a production chat would
   stream (perceived latency ≈ TTFT, lower than p50 shown). Sonnet's mean 97 output tokens
   indicates adaptive thinking stayed minimal on these queries — harder real-user questions may
   think more and cost/lag more. Synthetic histories are ~35 entries/vehicle; input cost scales
   roughly linearly with heavier real logs. All numbers are single-run (n=45 per lever).

## Recommendation carried into the Law-1 scheduling vote

Cost removes itself as an objection. If/when the build is scheduled, the probe favors
**Sonnet-grounded** as the launch lever (max quality, zero extra correctness surface, caching
headroom, acceptable streamed latency), with Haiku+computed as the cost-reduction option to
revisit only if real spend ever becomes material. The scheduling decision itself — build now
vs post-launch vs defer — goes to the tri-vote; this probe is evidence, not a verdict.
