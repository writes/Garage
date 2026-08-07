/**
 * Ask-Garage COST/LATENCY PROBE — the prerequisite the 2026-08-06 session left for the Law-1
 * scheduling tri-vote (see reports/askgarage-golden-v2.json for the quality evidence).
 *
 * Measures the two levers that PASSED the grounding gate:
 *   A. claude-haiku-4-5-20251001 :: grounded-computed  (96% answerable, 0 leaks)
 *   B. claude-sonnet-5           :: grounded           (100% answerable, 0 leaks)
 *
 *   cd CloudFunctions && npx tsx scripts/askGarageCostProbe.ts
 *
 * WHAT IS MEASURED (and why it cannot be pure arithmetic off the eval reports):
 *   1. Exact input-token baselines via /v1/messages/count_tokens per (vehicle x lever).
 *      Sonnet 5 uses a NEW tokenizer (~30% more tokens for identical text than the Haiku-era
 *      tokenizer), so a single shared count would be wrong for one of the levers.
 *   2. One live sweep: all 45 golden questions x 1 run per lever, capturing the API's own
 *      usage.input_tokens / usage.output_tokens and wall-clock latency per call. Sonnet 5 runs
 *      adaptive thinking by default and thinking bills as OUTPUT tokens, so output cost and
 *      latency are only knowable from a live run, never from the answer text in the reports.
 *
 * COST MODEL (USD per 1M tokens, from the claude-api skill pricing table, cached 2026-06-24):
 *   Haiku 4.5:  $1 in / $5 out.
 *   Sonnet 5:   $3 in / $15 out standard; INTRO $2 in / $10 out through 2026-08-31 — both are
 *               reported because the launch window straddles the intro-pricing cliff.
 * Caching arithmetic (5-minute TTL): write 1.25x, read 0.1x. Minimum cacheable prefix is
 * 4096 tokens on Haiku 4.5 and 1024 on Sonnet 5 — the report flags whether each lever's
 * system prompt even clears its model's floor, because below it caching silently no-ops.
 *
 * Requires ANTHROPIC_API_KEY in the environment; never echo it.
 * Report: ../../reports/askgarage-cost-probe.json; stdout is the scoreboard.
 */
import * as fs from "fs";
import * as path from "path";
import { GOLDEN_QUESTIONS } from "./askGarageGolden";
import type { GoldenQuestion } from "./askGarageGolden";
import { isAdaptiveThinkingGeneration, systemFor } from "./askGarageGoldenEval";
import type { VariantName } from "./askGarageGoldenEval";

const REQUEST_TIMEOUT_MS = 120_000;

interface Lever {
  key: string;
  model: string;
  variant: VariantName;
  /** USD per 1M tokens. */
  pricing: Array<{ label: string; inPerM: number; outPerM: number }>;
  /** Minimum cacheable prefix for this model (tokens). */
  cacheMinTokens: number;
}

const LEVERS: Lever[] = [
  {
    key: "haiku+computed",
    model: "claude-haiku-4-5-20251001",
    variant: "grounded-computed",
    pricing: [{ label: "standard", inPerM: 1, outPerM: 5 }],
    cacheMinTokens: 4096,
  },
  {
    key: "sonnet-grounded",
    model: "claude-sonnet-5",
    variant: "grounded",
    pricing: [
      { label: "intro (through 2026-08-31)", inPerM: 2, outPerM: 10 },
      { label: "standard", inPerM: 3, outPerM: 15 },
    ],
    cacheMinTokens: 1024,
  },
];

function headers(apiKey: string): Record<string, string> {
  return {
    "content-type": "application/json",
    "x-api-key": apiKey,
    "anthropic-version": "2023-06-01",
  };
}

function requestBody(lever: Lever, question: GoldenQuestion): object {
  const adaptive = isAdaptiveThinkingGeneration(lever.model);
  return {
    model: lever.model,
    max_tokens: adaptive ? 4000 : 700,
    ...(adaptive ? {} : { temperature: 0 }),
    system: systemFor(lever.variant, question),
    messages: [{ role: "user", content: [{ type: "text", text: question.question }] }],
  };
}

async function post(url: string, body: object, apiKey: string): Promise<any> {
  let lastError = "";
  for (let attempt = 1; attempt <= 5; attempt += 1) {
    let response: Response;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: headers(apiKey),
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (error) {
      lastError = `network: ${(error as Error).message}`;
      await sleep(1000 * 2 ** attempt);
      continue;
    }
    if (response.status === 429 || response.status >= 500) {
      const retryAfter = Number(response.headers.get("retry-after")) || 2 ** attempt;
      lastError = `API ${response.status}`;
      await sleep(Math.min(retryAfter, 30) * 1000);
      continue;
    }
    if (!response.ok) {
      // Print only the API's own message — never the request, which carries the history payload.
      let apiMessage = "";
      try {
        const parsed = await response.json() as { error?: { message?: string } };
        apiMessage = typeof parsed.error?.message === "string" ? ` — ${parsed.error.message}` : "";
      } catch { /* body unavailable */ }
      throw new Error(`API ${response.status}${apiMessage}`);
    }
    return response.json();
  }
  throw new Error(`gave up after 5 attempts (${lastError})`);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => { setTimeout(resolve, ms); });
}

async function mapPool<T, R>(items: T[], limit: number, worker: (item: T) => Promise<R>): Promise<R[]> {
  const results = new Array<R>(items.length);
  let next = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    for (;;) {
      const index = next;
      next += 1;
      if (index >= items.length) return;
      results[index] = await worker(items[index]);
    }
  });
  await Promise.all(runners);
  return results;
}

function percentile(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0;
  const index = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[Math.max(0, index)];
}

interface SweepCase {
  id: string;
  kind: GoldenQuestion["kind"];
  vehicle: string;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
}

async function main(): Promise<void> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) { console.error("ANTHROPIC_API_KEY not set"); process.exit(1); }

  const leverReports: object[] = [];

  for (const lever of LEVERS) {
    console.log(`\n=== ${lever.key} (${lever.model} :: ${lever.variant}) ===`);

    // ---- Phase 1: exact system-prompt token baseline per vehicle (count_tokens is free).
    // One representative question per vehicle: the counted total is system + that question;
    // the question is ~20 tokens, so this is effectively the per-vehicle prompt size on THIS
    // model's tokenizer.
    const perVehicle: Record<string, number> = {};
    for (const vehicle of ["accord", "f150", "m2"]) {
      const question = GOLDEN_QUESTIONS.find((q) => q.vehicle === vehicle)!;
      const counted = await post(
        "https://api.anthropic.com/v1/messages/count_tokens",
        {
          model: lever.model,
          system: systemFor(lever.variant, question),
          messages: [{ role: "user", content: [{ type: "text", text: question.question }] }],
        },
        apiKey,
      );
      perVehicle[vehicle] = counted.input_tokens as number;
      console.log(`  count_tokens ${vehicle}: ${counted.input_tokens} input tokens`);
    }

    // ---- Phase 2: live sweep — 45 questions x 1 run, usage + latency from the API itself.
    const sweep = await mapPool(GOLDEN_QUESTIONS, 4, async (question): Promise<SweepCase> => {
      const started = Date.now();
      const payload = await post(
        "https://api.anthropic.com/v1/messages",
        requestBody(lever, question),
        apiKey,
      );
      const latencyMs = Date.now() - started;
      return {
        id: question.id,
        kind: question.kind,
        vehicle: question.vehicle,
        inputTokens: payload.usage?.input_tokens ?? 0,
        outputTokens: payload.usage?.output_tokens ?? 0,
        latencyMs,
      };
    });

    const totalIn = sweep.reduce((sum, c) => sum + c.inputTokens, 0);
    const totalOut = sweep.reduce((sum, c) => sum + c.outputTokens, 0);
    const meanIn = totalIn / sweep.length;
    const meanOut = totalOut / sweep.length;
    const latencies = sweep.map((c) => c.latencyMs).sort((a, b) => a - b);
    const latency = {
      p50Ms: percentile(latencies, 50),
      p90Ms: percentile(latencies, 90),
      maxMs: percentile(latencies, 100),
      meanMs: Math.round(latencies.reduce((sum, value) => sum + value, 0) / latencies.length),
    };

    const costs = lever.pricing.map(({ label, inPerM, outPerM }) => {
      const perTurnUncached = (meanIn * inPerM + meanOut * outPerM) / 1e6;
      // Conversation caching: the per-vehicle system prompt (rules + computed summary + log)
      // is the stable prefix; only the question varies. Turn 1 writes at 1.25x; turns 2+ read
      // at 0.1x. Approximating the cacheable span as the mean measured input minus the
      // ~25-token question.
      const cacheable = Math.max(0, meanIn - 25);
      const perTurnCachedRead = ((meanIn - cacheable * 0.9) * inPerM + meanOut * outPerM) / 1e6;
      return {
        label,
        perTurnUncachedUsd: perTurnUncached,
        perTurnCachedReadUsd: perTurnCachedRead,
        perUserDayAt5Qs: perTurnUncached * 5,
        per1kUserDaysAt5Qs: perTurnUncached * 5 * 1000,
      };
    });

    const cacheEligible = Object.fromEntries(
      Object.entries(perVehicle).map(([vehicle, tokens]) => [vehicle, tokens >= lever.cacheMinTokens]),
    );

    console.log(`  sweep: ${sweep.length} calls  mean in ${meanIn.toFixed(0)} / out ${meanOut.toFixed(0)} tokens`);
    console.log(`  latency ms: p50 ${latency.p50Ms}  p90 ${latency.p90Ms}  max ${latency.maxMs}  mean ${latency.meanMs}`);
    for (const cost of costs) {
      console.log(`  cost [${cost.label}]: $${cost.perTurnUncachedUsd.toFixed(5)}/turn uncached, `
        + `$${cost.perTurnCachedReadUsd.toFixed(5)}/turn on cache read, `
        + `$${cost.per1kUserDaysAt5Qs.toFixed(2)} per 1k user-days @5 q/day`);
    }
    console.log(`  cache-eligible (system >= ${lever.cacheMinTokens}-token floor): ${JSON.stringify(cacheEligible)}`);

    leverReports.push({
      lever: lever.key,
      model: lever.model,
      variant: lever.variant,
      countTokensBaselinePerVehicle: perVehicle,
      cacheMinTokens: lever.cacheMinTokens,
      cacheEligiblePerVehicle: cacheEligible,
      sweep: { cases: sweep, totalInputTokens: totalIn, totalOutputTokens: totalOut, meanInputTokens: meanIn, meanOutputTokens: meanOut },
      latency,
      costs,
    });
  }

  const reportDir = path.join(__dirname, "..", "..", "reports");
  fs.mkdirSync(reportDir, { recursive: true });
  const file = path.join(reportDir, "askgarage-cost-probe.json");
  fs.writeFileSync(file, JSON.stringify({
    probedAt: new Date().toISOString(),
    pricingSource: "claude-api skill pricing table (cached 2026-06-24); Sonnet 5 intro pricing ends 2026-08-31",
    method: "count_tokens baseline per (vehicle x lever) + one live sweep of all 45 golden questions per lever; usage/latency from the API",
    levers: leverReports,
  }, null, 1));
  console.log(`\nreport: ${file}`);
}

main().catch((error) => { console.error(error); process.exit(1); });
