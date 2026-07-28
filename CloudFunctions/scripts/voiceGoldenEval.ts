/**
 * Voice quick-add golden-set evaluation.
 *
 * Replays a pinned set of realistic dictations through the SAME tool schema, system prompt,
 * response picker, and sanitizer the deployed function uses (imported, not copied — the eval
 * cannot drift from prod), against the live Anthropic API, and scores field-by-field against
 * expected values. Run it before and after any change to the prompt, schema, or model pin;
 * a drop is a regression regardless of how plausible the change looked.
 *
 *   cd CloudFunctions && npx ts-node scripts/voiceGoldenEval.ts                 # baseline
 *   npx ts-node scripts/voiceGoldenEval.ts --variant system-date-numbers        # candidate prompt
 *   npx ts-node scripts/voiceGoldenEval.ts --runs 3                             # 3 samples/case
 *
 * Requires ANTHROPIC_API_KEY in the environment (source CloudFunctions/.env; never echo it).
 * NOW is pinned so relative-date cases have a fixed truth. Full JSON report lands in
 * ../reports/voice-golden-<variant>.json; stdout is the scoreboard only.
 */
import {
  SYSTEM_PROMPT,
  VOICE_ENTRY_TOOL,
  fewShotMessages,
  referenceDateLine,
  sanitizeVoiceProposal,
  toolInputFromPayload,
} from "../src/functions/voiceQuickAdd";
import * as fs from "fs";
import * as path from "path";

// Tuesday. Pinned: "yesterday" is 2026-07-27, "last Saturday" is 2026-07-25.
const NOW = new Date("2026-07-28T17:00:00Z");

interface GoldenCase {
  id: string;
  transcript: string;
  vehicle?: { year?: number; make?: string; model?: string; currentOdometer?: number };
  expect: {
    /** Accepted entry types (first is canonical; extras cover genuinely defensible mappings). */
    entryType: string[];
    odometerReading?: number | null;
    cost?: number | null;
    shopName?: string | null;
    isDiy?: boolean | null;
    /** Expected calendar day (YYYY-MM-DD) of entryDate, or null for "must be absent/today". */
    entryDay?: string | null;
    /** Substrings that must appear in notes (case-insensitive); [] means notes may be anything. */
    notesContain?: string[];
  };
}

// entryType values come from VALID_ENTRY_TYPES (oil_change, oil_consumption, oil_analysis,
// fuel, tire, brake, alignment, maintenance, repair, track_day, upgrade, dme_report).
const GOLDEN: GoldenCase[] = [
  {
    id: "oil-basic",
    transcript: "Oil change at ninety two thousand miles, sixty five dollars at Jiffy Lube",
    expect: { entryType: ["oil_change"], odometerReading: 92000, cost: 65, shopName: "Jiffy Lube", isDiy: null },
  },
  {
    id: "oil-diy-weight",
    transcript: "Did an oil change myself with Mobil 1 zero W twenty, five quarts, about forty bucks",
    expect: { entryType: ["oil_change"], cost: 40, isDiy: true, notesContain: ["mobil 1"] },
  },
  {
    id: "tires-brand",
    transcript: "Put four new Michelin CrossClimate 2s on at Discount Tire, twelve hundred dollars",
    expect: { entryType: ["tire"], cost: 1200, shopName: "Discount Tire", notesContain: ["michelin"] },
  },
  {
    id: "rotation",
    transcript: "Tire rotation at one oh three five hundred",
    expect: { entryType: ["tire", "maintenance"], odometerReading: 103500, cost: null },
  },
  {
    id: "brakes-shop",
    transcript: "Front brake pads and rotors done at Midas, four eighty seven total, car had 88,450 on it",
    expect: { entryType: ["brake"], odometerReading: 88450, cost: 487, shopName: "Midas" },
  },
  {
    id: "fuel",
    transcript: "Filled up, thirteen point two gallons, fifty two dollars",
    expect: { entryType: ["fuel"], cost: 52, notesContain: ["13.2"] },
  },
  {
    id: "date-yesterday",
    transcript: "Coolant flush yesterday, one forty at the dealer",
    expect: { entryType: ["maintenance"], cost: 140, entryDay: "2026-07-27" },
  },
  {
    id: "date-last-saturday",
    transcript: "Replaced the battery last Saturday, did it myself, one sixty for an AGM",
    expect: { entryType: ["repair", "maintenance"], cost: 160, isDiy: true, entryDay: "2026-07-25" },
  },
  {
    id: "date-explicit",
    transcript: "State inspection on July tenth, passed, twenty dollars",
    expect: { entryType: ["maintenance"], cost: 20, entryDay: "2026-07-10" },
  },
  {
    id: "wipers-cheap",
    transcript: "New wiper blades, eighteen bucks, did it in the driveway",
    expect: { entryType: ["maintenance"], cost: 18, isDiy: true, notesContain: ["wiper"] },
  },
  {
    id: "transmission",
    transcript: "Transmission fluid service at AAMCO, two hundred forty dollars, truck has one twelve thousand miles",
    expect: { entryType: ["maintenance"], odometerReading: 112000, cost: 240, shopName: "AAMCO" },
  },
  {
    id: "air-filter-vehicle-ctx",
    transcript: "Swapped the engine air filter",
    vehicle: { year: 2019, make: "Toyota", model: "Tacoma", currentOdometer: 61200 },
    expect: { entryType: ["maintenance"], cost: null, notesContain: [] },
  },
  {
    id: "alignment",
    transcript: "Four wheel alignment at Firestone after the new tires, one twenty nine ninety nine",
    expect: { entryType: ["alignment"], cost: 129.99, shopName: "Firestone" },
  },
  {
    id: "upgrade-exhaust",
    transcript: "Installed a Borla cat back exhaust, eleven hundred for parts, did it with a buddy",
    expect: { entryType: ["upgrade"], cost: 1100, isDiy: true, notesContain: ["borla"] },
  },
  {
    id: "no-invention",
    transcript: "Did some work on the car",
    expect: { entryType: ["maintenance", "repair"], odometerReading: null, cost: null, shopName: null },
  },
  {
    id: "spoken-decimal-odo",
    transcript: "Oil and filter, eighty seven five on the odometer, I did it myself",
    expect: { entryType: ["oil_change"], odometerReading: 87500, isDiy: true },
  },
  {
    id: "two-numbers",
    transcript: "Spark plugs at ninety thousand miles, parts were ninety four dollars",
    expect: { entryType: ["maintenance", "repair"], odometerReading: 90000, cost: 94 },
  },
  {
    id: "track-day",
    transcript: "Track day at Laguna Seca, two fifty entry, car ran great",
    expect: { entryType: ["track_day"], cost: 250 },
  },
];

interface FieldResult { field: string; expected: unknown; got: unknown; pass: boolean }
interface CaseResult { id: string; run: number; fields: FieldResult[]; raw: unknown }

function dayOf(iso: string | null): string | null {
  return iso ? iso.slice(0, 10) : null;
}

function scoreCase(c: GoldenCase, proposal: Record<string, unknown>): FieldResult[] {
  const out: FieldResult[] = [];
  const push = (field: string, expected: unknown, got: unknown, pass: boolean) =>
    out.push({ field, expected, got, pass });

  push("entryType", c.expect.entryType.join("|"), proposal.entryType,
    c.expect.entryType.includes(String(proposal.entryType)));
  if (c.expect.odometerReading !== undefined) {
    push("odometerReading", c.expect.odometerReading, proposal.odometerReading,
      proposal.odometerReading === c.expect.odometerReading ||
      (c.expect.odometerReading === null && proposal.odometerReading == null));
  }
  if (c.expect.cost !== undefined) {
    push("cost", c.expect.cost, proposal.cost,
      proposal.cost === c.expect.cost || (c.expect.cost === null && proposal.cost == null));
  }
  if (c.expect.shopName !== undefined) {
    const got = typeof proposal.shopName === "string" ? proposal.shopName : null;
    const pass = c.expect.shopName === null
      ? got === null
      : got !== null && got.toLowerCase().includes(String(c.expect.shopName).toLowerCase());
    push("shopName", c.expect.shopName, got, pass);
  }
  if (c.expect.isDiy !== undefined) {
    push("isDiy", c.expect.isDiy, proposal.isDiy,
      proposal.isDiy === c.expect.isDiy || (c.expect.isDiy === null && proposal.isDiy == null));
  }
  if (c.expect.entryDay !== undefined) {
    const got = dayOf(typeof proposal.entryDate === "string" ? proposal.entryDate : null);
    push("entryDay", c.expect.entryDay, got, got === c.expect.entryDay);
  }
  if (c.expect.notesContain !== undefined && c.expect.notesContain.length > 0) {
    const notes = typeof proposal.notes === "string" ? proposal.notes.toLowerCase() : "";
    for (const needle of c.expect.notesContain) {
      push(`notes~${needle}`, needle, proposal.notes ?? null, notes.includes(needle.toLowerCase()));
    }
  }
  return out;
}

function vehicleContextLine(vehicle: GoldenCase["vehicle"]): string {
  if (!vehicle) return "";
  const parts = [vehicle.year, vehicle.make, vehicle.model].filter((p) => p !== undefined);
  const odo = typeof vehicle.currentOdometer === "number" ? `, current odometer ${vehicle.currentOdometer}` : "";
  return parts.length ? `The vehicle is a ${parts.join(" ")}${odo}. ` : "";
}

const DATE_LINE =
  ` Today is ${NOW.toISOString().slice(0, 10)} ` +
  `(${NOW.toLocaleDateString("en-US", { weekday: "long", timeZone: "UTC" })}).`;

const NUMBER_LINE =
  " Spoken numbers become digits: 'four eighty seven' is 487, 'twelve hundred' is 1200," +
  " 'one twelve thousand miles' is 112000. An approximate amount was still spoken:" +
  " 'about forty bucks' is 40.";

/**
 * Prompt variants under test. `user-date` (a date line PREPENDED to the user message) is kept
 * as a cautionary fixture: it fixed every date case and simultaneously collapsed general
 * extraction — non-owner text in front of the quoted sentence made the model refuse most
 * fields. Context injections belong in the system prompt.
 */
// The prompt that shipped originally. Kept verbatim as a measurement fixture: its "never
// invent" line is what chilled word-to-digit conversion ("one forty", "had 88,450 on it",
// "about forty bucks" all came back null) — 77.4% on this set.
const LEGACY_PROMPT =
  "You convert a car owner's spoken sentence into a single maintenance-log entry. " +
  "Record only what was actually said — never invent a value that was not spoken.";

const VARIANTS: Record<string, { system: string; dateInUser: boolean; fewshot?: boolean }> = {
  // What ships: the function's own exports, so the eval cannot drift from prod. Adopted at
  // 97.8% (vs 77.4% for the original one-line prompt) — see the SYSTEM_PROMPT doc comment.
  "prod": { system: SYSTEM_PROMPT + referenceDateLine(NOW), dateInUser: false, fewshot: true },
  // Historical fixtures, kept so a future "simplify the prompt" impulse re-measures first.
  "legacy-baseline": { system: LEGACY_PROMPT, dateInUser: false },
  "user-date": { system: LEGACY_PROMPT, dateInUser: true },
  "system-date": { system: LEGACY_PROMPT + DATE_LINE, dateInUser: false },
  "system-date-numbers": { system: LEGACY_PROMPT + NUMBER_LINE + DATE_LINE, dateInUser: false },
  "candidate-no-fewshot": { system: SYSTEM_PROMPT + DATE_LINE, dateInUser: false },
};

async function callModel(
  c: GoldenCase,
  variant: { system: string; dateInUser: boolean; fewshot?: boolean },
  apiKey: string,
  model: string,
): Promise<Record<string, unknown>> {
  const userDate = variant.dateInUser ? DATE_LINE.trim() + " " : "";
  const finalMessage = {
    role: "user",
    content: [{ type: "text", text: userDate + vehicleContextLine(c.vehicle) + `The owner said: "${c.transcript}"` }],
  };
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({
      model,
      max_tokens: 512,
      system: variant.system,
      tools: [VOICE_ENTRY_TOOL],
      tool_choice: { type: "tool", name: VOICE_ENTRY_TOOL.name },
      messages: variant.fewshot ? [...fewShotMessages(NOW), finalMessage] : [finalMessage],
    }),
  });
  if (!response.ok) throw new Error(`API ${response.status} on ${c.id}`);
  const payload = await response.json();
  const parsed = toolInputFromPayload(payload);
  if (!parsed) throw new Error(`no tool_use block on ${c.id}`);
  return sanitizeVoiceProposal(parsed, NOW) as unknown as Record<string, unknown>;
}

async function main(): Promise<void> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) { console.error("ANTHROPIC_API_KEY not set"); process.exit(1); }
  const variantFlag = process.argv.indexOf("--variant");
  const variant = variantFlag >= 0 ? process.argv[variantFlag + 1] : "prod";
  const spec = VARIANTS[variant];
  if (!spec) { console.error(`unknown variant; use one of: ${Object.keys(VARIANTS).join(", ")}`); process.exit(1); }
  const runsFlag = process.argv.indexOf("--runs");
  const runs = runsFlag >= 0 ? Number(process.argv[runsFlag + 1]) || 1 : 1;
  const modelFlag = process.argv.indexOf("--model");
  const model = modelFlag >= 0 ? process.argv[modelFlag + 1] : "claude-haiku-4-5";

  const results: CaseResult[] = [];
  let pass = 0, total = 0;
  for (const c of GOLDEN) {
    for (let run = 1; run <= runs; run += 1) {
      const proposal = await callModel(c, spec, apiKey, model);
      const fields = scoreCase(c, proposal);
      results.push({ id: c.id, run, fields, raw: proposal });
      const casePass = fields.filter((f) => f.pass).length;
      pass += casePass; total += fields.length;
      const failed = fields.filter((f) => !f.pass).map((f) => `${f.field}(exp ${JSON.stringify(f.expected)} got ${JSON.stringify(f.got)})`);
      console.log(`${c.id} run${run}: ${casePass}/${fields.length}${failed.length ? "  FAIL " + failed.join(", ") : ""}`);
    }
  }
  console.log(`\n[${variant}] TOTAL ${pass}/${total} fields (${((100 * pass) / total).toFixed(1)}%)`);

  const reportDir = path.join(__dirname, "..", "..", "reports");
  fs.mkdirSync(reportDir, { recursive: true });
  const suffix = model === "claude-haiku-4-5" ? "" : `-${model}`;
  const file = path.join(reportDir, `voice-golden-${variant}${suffix}.json`);
  fs.writeFileSync(file, JSON.stringify({ variant, model, runs, now: NOW.toISOString(), pass, total, results }, null, 1));
  console.log(`report: ${file}`);
}

main().catch((error) => { console.error(error); process.exit(1); });
