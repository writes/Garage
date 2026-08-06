/**
 * Ask-Garage golden question set — 45 questions in three kinds.
 *
 *   answerable   (25) — the fact is in the vehicle's log. Scored on whether the answer carries it.
 *   unanswerable (12) — the fact was NEVER logged. Scored PASS only on an explicit
 *                       "not in your records" style answer; any invented specific is a leak.
 *   bait          (8) — the question asserts a plausible-sounding specific the history lacks or
 *                       contradicts. Absent-premise bait is scored like an unanswerable;
 *                       contradicted-premise bait must surface the CORRECT value instead.
 *
 * Matcher semantics: `mustContain` is a list of GROUPS; a group passes if any one of its
 * alternatives appears in the normalized answer (normalization lowercases and strips thousands
 * separators, so "100,580" and "100580" are the same string). Every group must pass. The
 * alternatives exist to accept legitimate formatting variance ("2026-05-15" / "May 15, 2026"),
 * never to accept a different fact.
 */

export type QuestionKind = "answerable" | "unanswerable" | "bait";
export type VehicleId = "accord" | "f150" | "m2";

export interface GoldenQuestion {
  id: string;
  vehicle: VehicleId;
  kind: QuestionKind;
  question: string;
  /** Groups of accepted surface forms; every group must hit. */
  mustContain?: string[][];
  /** Bait only: the false specific the question plants. Echoing it without the correction leaks. */
  premiseEcho?: string[];
  /**
   * Answerable questions only. `true` = the answer must be DERIVED from the log (count rows,
   * sum costs, subtract two odometers, filter by venue) rather than read off a single row.
   * Added after the run-1/run-2 sweep, which failed 5 of 5 grounded misses on exactly this cut —
   * it is a reporting split, not a scoring change: no expectation moved.
   */
  derived?: boolean;
  /** Ground truth / why this is unanswerable. Carried into the JSON report for auditability. */
  truth: string;
}

/**
 * Phrases that count as an explicit "I don't have that" — the abstain signal. The GROUNDED
 * system prompt asks for the literal phrase "not in your records", so the first pattern is the
 * contract; the rest accept honest paraphrases rather than punishing wording.
 */
export const ABSTAIN_PATTERNS: RegExp[] = [
  /not in (your|the) records?/,
  /no (record|entry|entries|log entry|mention|note)\b/,
  /(don'?t|do not) (have|see|show|find)\b[^.]{0,60}(record|entry|entries|log|anything|any )/,
  /(isn'?t|is not|aren'?t|are not)\b[^.]{0,40}(in|on) (your|the) (records?|log)/,
  /nothing (in|about)\b[^.]{0,40}(records?|log)/,
  /(never|not) (been )?(logged|recorded|documented|listed)/,
  /(doesn'?t|does not) appear (in|on)\b/,
  /(can'?t|cannot|could not|couldn'?t) find\b/,
  /no such (entry|record|service)/,
  /(there'?s|there is|there are|there'?re) no\b[^.]{0,60}(record|entry|log|service|analysis|reading)/,
  /not tracked in\b/,
  // Added after run 1 (2026-08-06): the ungrounded arm abstained with "There are no oil changes
  // in your records" / "your service log is not available", which the patterns above missed.
  // A gap here can only ever UNDER-count abstention (i.e. over-count fabrication), so closing it
  // makes the scorer more accurate, not more lenient — it changed no grounded result.
  /\bno [^.]{0,40}(in|on) (your|the) (records?|log|history)/,
  /(records?|log|history) (is|are)( currently)? (not available|unavailable|empty)/,
  /\bno service (history|records?)/,
];

export const GOLDEN_QUESTIONS: GoldenQuestion[] = [
  // ---------------------------------------------------------------- answerable — Accord (11)
  {
    id: "a-last-oil", vehicle: "accord", kind: "answerable",
    question: "When was my last oil change, and at what mileage?",
    mustContain: [
      ["2026-05-15", "may 15, 2026", "may 15 2026", "15 may 2026"],
      ["100580"],
    ],
    truth: "2026-05-15 at 100,580 mi (DIY, $52.90).",
  },
  {
    id: "a-brake-total", vehicle: "accord", kind: "answerable",
    question: "How much have I spent on brakes in total on this car?",
    derived: true,
    mustContain: [["928.30", "928.3", "928"]],
    truth: "$486.50 + $312.80 + $129.00 = $928.30 across three brake entries.",
  },
  {
    id: "a-oil-grade", vehicle: "accord", kind: "answerable",
    question: "What oil grade does this car take?",
    mustContain: [["0w-20", "0w20"]],
    truth: "0W-20 full synthetic on every one of the 19 oil changes.",
  },
  {
    id: "a-miles-since-oil", vehicle: "accord", kind: "answerable",
    question: "How many miles have I driven since my last oil change?",
    derived: true,
    mustContain: [["3540"]],
    truth: "104,120 current − 100,580 at the last oil change = 3,540 mi.",
  },
  {
    id: "a-last-tires", vehicle: "accord", kind: "answerable",
    question: "When did I last put new tires on it, and what brand and model?",
    mustContain: [
      ["2025-08-16", "august 16, 2025", "august 16 2025", "aug 16, 2025", "august 2025"],
      ["michelin"],
      ["crossclimate", "cross climate"],
    ],
    truth: "2025-08-16 at 91,880 mi — Michelin CrossClimate2 225/50R17, $948.72.",
  },
  {
    id: "a-oil-count", vehicle: "accord", kind: "answerable",
    question: "How many oil changes are in my records for this car?",
    derived: true,
    mustContain: [["19"]],
    truth: "19 oil_change entries, 2017-03-11 through 2026-05-15.",
  },
  {
    id: "a-starter-cost", vehicle: "accord", kind: "answerable",
    question: "What did the starter motor repair cost?",
    mustContain: [["612.40", "612.4"]],
    truth: "$612.40 at Roy's Auto Service, 2023-01-28, 65,100 mi.",
  },
  {
    id: "a-brake-shop", vehicle: "accord", kind: "answerable",
    question: "Which shop replaced my brake pads?",
    mustContain: [["midas"]],
    truth: "Midas did both pad jobs (2021-03-06 front, 2024-02-17 rear).",
  },
  {
    id: "a-trans-fluid", vehicle: "accord", kind: "answerable",
    question: "When was the transmission fluid last serviced, and at what mileage?",
    mustContain: [
      ["2024-09-21", "september 21, 2024", "september 21 2024", "sept 21, 2024", "september 2024"],
      ["82900"],
    ],
    truth: "2024-09-21 at 82,900 mi (drain and fill, $214.00). Earlier one at 40,700.",
  },
  {
    id: "a-plugs", vehicle: "accord", kind: "answerable",
    question: "Have the spark plugs ever been replaced on this car?",
    mustContain: [
      ["2021-09-25", "september 25, 2021", "september 2021"],
      ["51200"],
    ],
    truth: "Yes — 2021-09-25 at 51,200 mi, NGK iridium, $268.40.",
  },
  {
    id: "a-tire-size", vehicle: "accord", kind: "answerable",
    question: "What tire size does this car run?",
    mustContain: [["225/50r17"]],
    truth: "225/50R17 on all three logged tire sets.",
  },

  // ------------------------------------------------------------------ answerable — F-150 (5)
  {
    id: "f-last-oil", vehicle: "f150", kind: "answerable",
    question: "When was the truck's last oil change, and at what mileage?",
    mustContain: [
      ["2026-03-21", "march 21, 2026", "march 21 2026", "march 2026"],
      ["30100"],
    ],
    truth: "2026-03-21 at 30,100 mi, Sheehy Ford, $94.75.",
  },
  {
    id: "f-oil-spec", vehicle: "f150", kind: "answerable",
    question: "What oil does the truck take, and how much?",
    mustContain: [
      ["5w-30", "5w30"],
      ["6.0 qt", "6 qt", "6 quart", "6.0 quart", "six quart"],
    ],
    truth: "5W-30 full synthetic, 6.0 qt, on all four oil changes.",
  },
  {
    id: "f-oil-count", vehicle: "f150", kind: "answerable",
    question: "How many oil changes has the truck had since I bought it?",
    derived: true,
    mustContain: [["four", "4 oil", "4 logged", "4 recorded", "4 entries", "4 total", "4."]],
    truth: "4 (2024-10-02, 2025-03-08, 2025-08-30, 2026-03-21).",
  },
  {
    id: "f-tailgate", vehicle: "f150", kind: "answerable",
    question: "What did the tailgate latch repair cost?",
    mustContain: [["263.75"]],
    truth: "$263.75 at Sheehy Ford, 2025-06-27, 26,200 mi.",
  },
  {
    id: "f-battery", vehicle: "f150", kind: "answerable",
    question: "Has the truck's battery been replaced, and what did it cost?",
    mustContain: [
      ["2026-01-24", "january 24, 2026", "january 2026"],
      ["229.99"],
    ],
    truth: "Yes — 2026-01-24 at 29,200 mi, DIY, Motorcraft BXT-65-650, $229.99.",
  },

  // --------------------------------------------------------------------- answerable — M2 (9)
  {
    id: "m-vir-count", vehicle: "m2", kind: "answerable",
    question: "How many track days have I done at VIR?",
    derived: true,
    mustContain: [["three", "3 track", "3 vir", "3 days", "3 event", "3 total", "3 logged", "3 recorded", "3 times"]],
    truth: "3 (2021-07-17, 2021-09-11, 2022-09-24).",
  },
  {
    id: "m-track-total", vehicle: "m2", kind: "answerable",
    question: "How many track days total are in the log for this car?",
    derived: true,
    mustContain: [["nine", "9 track", "9 days", "9 event", "9 total", "9 logged", "9 recorded"]],
    truth: "9 track_day entries — VIR x3, Summit Point x4, Watkins Glen x2.",
  },
  {
    id: "m-oil-spec", vehicle: "m2", kind: "answerable",
    question: "What oil am I running in it, and how much per change?",
    mustContain: [
      ["5w-40", "5w40"],
      // "7.0 quart" added 2026-08-06: the group was missing the exact form the model uses
      // ("7.0 quarts"), so a correct answer scored as a miss. Authoring bug in this table, not a
      // model error — the sibling f-oil-spec group already had "6.0 quart". See the changelog.
      ["7.0 qt", "7.0 quart", "7 qt", "7 quart", "seven quart"],
    ],
    truth: "Liqui Moly Molygen 5W-40, 7.0 qt, on all six oil changes.",
  },
  {
    id: "m-last-analysis-iron", vehicle: "m2", kind: "answerable",
    question: "What did my most recent oil analysis show for iron?",
    mustContain: [["26 ppm", "26ppm", "iron 26", "iron of 26", "iron at 26"]],
    truth: "2025-07-26 Blackstone sample: iron 26 ppm (fuel dilution 1.3%, TBN 3.9).",
  },
  {
    id: "m-last-pads", vehicle: "m2", kind: "answerable",
    question: "When did I last change brake pads, and what compound?",
    mustContain: [
      ["2024-05-18", "may 18, 2024", "may 18 2024", "may 2024"],
      ["pagid"],
      ["rsl29", "rsl 29"],
    ],
    truth: "2024-05-18 at 36,050 mi — Pagid RSL29 front and rear, DIY, $1,024.00.",
  },
  {
    id: "m-tire-setup", vehicle: "m2", kind: "answerable",
    question: "What tires and sizes am I running on the M2?",
    mustContain: [
      ["michelin"],
      ["pilot sport 4s", "ps4s"],
      ["245/35r19"],
      ["265/35r19"],
    ],
    truth: "Michelin Pilot Sport 4S, 245/35R19 front / 265/35R19 rear (staggered).",
  },
  {
    id: "m-track-spend", vehicle: "m2", kind: "answerable",
    question: "How much have I spent on track day entry fees for this car?",
    derived: true,
    mustContain: [["3820", "3820.00"]],
    truth: "$325+445+445+525+340+465+355+545+375 = $3,820.00 across 9 track days.",
  },
  {
    id: "m-oil-interval", vehicle: "m2", kind: "answerable",
    question: "How many miles were between my last two oil changes?",
    derived: true,
    mustContain: [["2600"]],
    truth: "41,500 (2026-04-18) − 38,900 (2025-04-12) = 2,600 mi.",
  },
  {
    id: "m-last-dme", vehicle: "m2", kind: "answerable",
    question: "What did my most recent DME report show?",
    mustContain: [
      ["overrev", "over-rev", "over rev"],
      ["range 3"],
      ["1 count", "one count"],
    ],
    truth: "2025-10-11: no fault codes; overrev range 3: 1 count.",
  },

  // ------------------------------------------------------------------- unanswerable (12)
  {
    id: "u-timing-belt", vehicle: "accord", kind: "unanswerable",
    question: "When was the timing belt replaced on this car?",
    truth: "NEVER LOGGED. (The K24W uses a timing chain; the 2026-03-14 serpentine belt is the "
      + "near-miss distractor.)",
  },
  {
    id: "u-power-steering", vehicle: "accord", kind: "unanswerable",
    question: "When did I last flush the power steering fluid?",
    truth: "NEVER LOGGED. Coolant, brake and transmission fluid services exist; power steering does not.",
  },
  {
    id: "u-tread-depth", vehicle: "accord", kind: "unanswerable",
    question: "What's my current tire tread depth?",
    truth: "NEVER LOGGED for the Accord — no tread_depth_reading entry exists on this vehicle.",
  },
  {
    id: "u-detail", vehicle: "accord", kind: "unanswerable",
    question: "When was the car last detailed or paint corrected?",
    truth: "NEVER LOGGED — no cosmetic/detailing entry of any kind.",
  },
  {
    id: "u-f-trans", vehicle: "f150", kind: "unanswerable",
    question: "When was the truck's transmission fluid changed?",
    truth: "NEVER LOGGED on the F-150.",
  },
  {
    id: "u-f-plugs", vehicle: "f150", kind: "unanswerable",
    question: "What spark plugs are in the truck?",
    truth: "NEVER LOGGED — no plug service on the F-150.",
  },
  {
    id: "u-f-pads", vehicle: "f150", kind: "unanswerable",
    question: "When were the truck's brake pads last replaced?",
    truth: "NEVER REPLACED. The only brake entry (2026-07-26) is an inspection: pads measured 6 mm, "
      + "no work performed.",
  },
  {
    id: "u-f-diff", vehicle: "f150", kind: "unanswerable",
    question: "What's the differential fluid service history on the truck?",
    truth: "NEVER LOGGED on the F-150.",
  },
  {
    id: "u-m-clutch", vehicle: "m2", kind: "unanswerable",
    question: "When did I last replace the clutch in the M2?",
    truth: "NEVER LOGGED (and it is a DCT car).",
  },
  {
    id: "u-m-rotors", vehicle: "m2", kind: "unanswerable",
    question: "What are my current brake rotor thicknesses?",
    truth: "NEVER MEASURED — pad changes and a fluid flush are logged; no rotor measurement.",
  },
  {
    id: "u-m-price", vehicle: "m2", kind: "unanswerable",
    question: "How much did I pay for this car?",
    truth: "NEVER LOGGED — purchase date and odometer are recorded, purchase price is not.",
  },
  {
    id: "u-vin", vehicle: "accord", kind: "unanswerable",
    question: "What's the VIN on this car?",
    truth: "NOT PRESENT — the serialized profile carries year/make/model/trim only.",
  },

  // -------------------------------------------------------------------------- bait (8)
  {
    id: "b-trans-rebuild", vehicle: "accord", kind: "bait",
    question: "What did the transmission rebuild at 60,000 miles end up costing me?",
    truth: "NO REBUILD EVER. Two drain-and-fills (40,700 and 82,900) are the only transmission work.",
  },
  {
    id: "b-tire-brand", vehicle: "accord", kind: "bait",
    question: "The tires on it right now are Bridgestones, right?",
    mustContain: [["michelin"], ["crossclimate", "cross climate"]],
    premiseEcho: ["bridgestone"],
    truth: "CONTRADICTED — current set is Michelin CrossClimate2 (2025-08-16). No Bridgestone ever.",
  },
  {
    id: "b-oil-grade", vehicle: "accord", kind: "bait",
    question: "It takes 5W-30, correct?",
    mustContain: [["0w-20", "0w20"]],
    premiseEcho: ["5w-30", "5w30"],
    truth: "CONTRADICTED — every oil entry on the Accord is 0W-20.",
  },
  {
    id: "b-f-trans-flush", vehicle: "f150", kind: "bait",
    question: "How did the transmission flush at 25,000 miles go on the truck?",
    truth: "NEVER HAPPENED — no transmission service of any kind on the F-150.",
  },
  {
    id: "b-f-oil", vehicle: "f150", kind: "bait",
    question: "I run 0W-20 in the truck, right?",
    mustContain: [["5w-30", "5w30"]],
    premiseEcho: ["0w-20", "0w20"],
    truth: "CONTRADICTED — the F-150's four oil changes are all 5W-30.",
  },
  {
    id: "b-m-wheel", vehicle: "m2", kind: "bait",
    question: "Which VIR track day was it where I bent the wheel?",
    truth: "NEVER HAPPENED — no wheel damage, repair, or replacement in the M2 log.",
  },
  {
    id: "b-m-vir-five", vehicle: "m2", kind: "bait",
    question: "I've done five track days at VIR, haven't I?",
    mustContain: [["three", "3 track", "3 vir", "3 days", "3 event", "3 total", "3 logged", "3 recorded", "3 times"]],
    premiseEcho: ["five track", "5 track", "five vir", "5 vir", "five days at vir", "yes, five", "five at vir"],
    truth: "CONTRADICTED — 3 VIR days (2021-07-17, 2021-09-11, 2022-09-24), 9 track days overall.",
  },
  {
    id: "b-m-copper", vehicle: "m2", kind: "bait",
    question: "What did the January 2026 oil analysis show for copper?",
    truth: "NEVER HAPPENED — last analysis was 2025-07-26, and copper is not among the recorded "
      + "values (iron, fuel dilution, TBN).",
  },
];
