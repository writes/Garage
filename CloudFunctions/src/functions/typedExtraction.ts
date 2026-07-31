import { isRecord } from "./claudeProxy";

/**
 * Typed extraction (schemaVersion 2) — the shared type-specific field vocabulary spread into
 * BOTH quick-add tools (voice + receipt). Spec: docs/research/2026-07-31_TYPED_EXTRACTION_SPEC.md
 * (rev 3, Gemini + GPT-5.6 Sol reviewed).
 *
 * HARD CONSTRAINT (measured 2026-07-31, raw API probe): strict tool schemas reject >25 optional
 * parameters at request time — a 400 here would kill EVERY scan, not degrade one. The receipt
 * tool carries 8 optional common fields, so this vocabulary must stay ≤15 fields, and
 * tests/typedExtraction.test.ts fails the build if either composed tool exceeds 23 optional
 * parameters. Adding a field means removing one, or splitting the tool per entry-type family.
 */

export const VALID_ENTRY_TYPES = [
  "oil_change", "oil_consumption", "oil_analysis", "fuel", "tire", "brake",
  "alignment", "maintenance", "repair", "track_day", "upgrade", "dme_report",
] as const;
export type EntryTypeValue = typeof VALID_ENTRY_TYPES[number];

export const SERVICE_ACTION_VALUES = [
  "pads_replaced", "rotors_replaced", "fluid_flush", "inspection",
  "new_install", "rotation", "tread_depth_reading", "removed",
] as const;
export const UPGRADE_CATEGORY_VALUES = ["suspension", "engine", "aero", "interior", "wheels", "other"] as const;

export type TypedDetails = {
  workItem: string | null;
  brand: string | null;
  productModel: string | null;
  oilGrade: string | null;
  quantityQuarts: number | null;
  serviceAction: string | null;
  nextDueOdometer: number | null;
  tireSizeFront: string | null;
  tireSizeRear: string | null;
  upgradeCategory: string | null;
};

export const TYPED_FIELD_NAMES = [
  "workItem", "brand", "productModel", "oilGrade", "quantityQuarts",
  "serviceAction",
  "nextDueOdometer", "tireSizeFront", "tireSizeRear", "upgradeCategory",
] as const satisfies ReadonlyArray<keyof TypedDetails>;

/**
 * Which entry types each typed field is meaningful for. The sanitizer nulls a field whose
 * proposal entryType is not listed — cross-type leakage (a schema-valid `gallons` on a brake
 * entry) dies here, at the source, instead of in 12 separate client mappings (Sol #4).
 */
const FIELD_ENTRY_TYPES: Record<keyof TypedDetails, ReadonlyArray<EntryTypeValue>> = {
  workItem: ["maintenance", "repair", "upgrade"],
  brand: ["oil_change", "oil_consumption", "brake", "tire", "upgrade"],
  productModel: ["tire"],
  oilGrade: ["oil_change", "oil_consumption"],
  quantityQuarts: ["oil_change", "oil_consumption"],
  serviceAction: ["brake", "tire"],
  nextDueOdometer: ["maintenance"],
  tireSizeFront: ["tire"],
  tireSizeRear: ["tire"],
  upgradeCategory: ["upgrade"],
};

/**
 * Spread into both V2 tool schemas. Descriptions scope each field to its entry types — with a
 * flat schema that scoping plus the entry-type-aware sanitizer are the cross-type guards.
 * position and filterBrand were TRIMMED in rev 4 final: 0-5/9 positive recall across every
 * measured config; their facts stay in notes and the pickers keep their defaults.
 */
export const TYPED_DETAIL_PROPERTIES = {
  workItem: {
    type: "string",
    description: "Only for maintenance, repair, or upgrade entries: the primary work item or part," +
      " e.g. 'spark plugs', 'alternator replacement', 'coilover kit'. One item — extra work goes in notes.",
  },
  brand: {
    type: "string",
    description: "Brand of the PRIMARY serviced component (oil, pads, tires, or the upgrade part)." +
      " Omit if different brands apply to different components.",
  },
  productModel: { type: "string", description: "Only for tire entries: the tire model name, e.g. 'Pilot Sport 4S'." },
  oilGrade: { type: "string", description: "Only for oil entries: the viscosity grade exactly as stated, e.g. '0W-40'." },
  quantityQuarts: { type: "number", description: "Only for oil entries: quarts of oil used or added." },
  serviceAction: {
    type: "string",
    enum: SERVICE_ACTION_VALUES,
    description: "The PRIMARY action for a brake entry (pads_replaced, rotors_replaced, fluid_flush," +
      " inspection) or tire entry (new_install, rotation, tread_depth_reading, removed)." +
      " Pick the main one; additional work goes in notes.",
  },
  nextDueOdometer: {
    type: "integer",
    description: "Only for maintenance entries: the ABSOLUTE odometer reading when the service is next" +
      " due. If the owner states an interval ('due in 5,000 miles'), add it to the current odometer" +
      " from the vehicle context; omit if there is no current odometer to add to.",
  },
  tireSizeFront: { type: "string", description: "Only for tire entries: front tire size, e.g. '245/40R18'." },
  tireSizeRear: { type: "string", description: "Only for tire entries: rear tire size, only if different from front." },
  upgradeCategory: {
    type: "string",
    enum: UPGRADE_CATEGORY_VALUES,
    description: "Only for upgrade entries: the category of the installed part.",
  },
} as const;

/**
 * SPLIT-CALL ARCHITECTURE (measured 2026-07-31, ablation in scripts/voiceGoldenEval.ts):
 * merging the typed vocabulary into the main extraction tool destroyed common-field accuracy
 * MODEL-INDEPENDENTLY — the 22-field tool with the untouched v1 prompt scored 64.6% core
 * (baseline 98.5%), Sonnet 5 fared no better than Haiku, and three rounds of prompt/few-shot
 * repair plateaued at ~90%. Attention dilutes across a wide optional schema; no wording fixes
 * that. So v2 keeps call 1 BYTE-IDENTICAL to the validated v1 config and extracts typed
 * details in a SECOND call whose tool holds only the entry type's own handful of fields — the
 * narrow regime where extraction is accurate. Bonus: cross-type leakage and the strict-schema
 * optional-parameter ceiling both become structurally impossible.
 */
export const TYPED_SYSTEM_PROMPT =
  "You extract the type-specific service details from a car owner's already-classified" +
  " maintenance-log entry. Fill every field the owner's words support: brands, grades," +
  " quantities, actions, sizes, and named products are all recording, not inventing —" +
  " 'Valvoline five W twenty' is brand Valvoline and grade 5W-20, and a named tire line like" +
  " 'Defender LTX' is the productModel. Omit a field the owner said nothing about —" +
  " never carry a value from one field into another. A value with no matching option in an" +
  " enum field is left out, never rounded to the nearest option. When work spans several" +
  " actions or brands, record the primary one.";

function stringOrNull(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  // Over-length is nulled, never truncated: a silently chopped brand/size is corrupted data
  // (Sol #18); absent is honest. Same rule as out-of-range numbers.
  if (trimmed.length === 0 || trimmed.length > maxLength) return null;
  return trimmed;
}

function numberOrNull(value: unknown, minimumExclusive: number, maximum: number): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value > minimumExclusive && value <= maximum ? value : null;
}

function integerOrNull(value: unknown, minimumExclusive: number, maximum: number): number | null {
  if (typeof value !== "number" || !Number.isSafeInteger(value)) return null;
  return value > minimumExclusive && value <= maximum ? value : null;
}

function enumOrNull(value: unknown, allowed: ReadonlyArray<string>): string | null {
  return typeof value === "string" && allowed.includes(value) ? value : null;
}

/** serviceAction is one wire enum serving two forms; each type accepts only its own verbs. */
const SERVICE_ACTIONS_BY_TYPE: Partial<Record<EntryTypeValue, ReadonlyArray<string>>> = {
  brake: ["pads_replaced", "rotors_replaced", "fluid_flush", "inspection"],
  tire: ["new_install", "rotation", "tread_depth_reading", "removed"],
};

/**
 * Untrusted model output → the typed contract. Strict mode already enforces types and enums at
 * the API, but this sanitizer is the trust boundary and assumes nothing (belt-and-braces, same
 * stance as sanitizeVoiceProposal).
 */
export function sanitizeTypedDetails(value: unknown, entryType: EntryTypeValue): TypedDetails {
  const input = isRecord(value) ? value : {};
  const details: TypedDetails = {
    workItem: stringOrNull(input.workItem, 160),
    brand: stringOrNull(input.brand, 80),
    productModel: stringOrNull(input.productModel, 80),
    oilGrade: stringOrNull(input.oilGrade, 20),
    quantityQuarts: numberOrNull(input.quantityQuarts, 0, 40),
    serviceAction: enumOrNull(input.serviceAction, SERVICE_ACTIONS_BY_TYPE[entryType] ?? []),
    nextDueOdometer: integerOrNull(input.nextDueOdometer, 0, 2_000_000),
    tireSizeFront: stringOrNull(input.tireSizeFront, 20),
    tireSizeRear: stringOrNull(input.tireSizeRear, 20),
    upgradeCategory: enumOrNull(input.upgradeCategory, UPGRADE_CATEGORY_VALUES),
  };
  for (const field of TYPED_FIELD_NAMES) {
    if (!FIELD_ENTRY_TYPES[field].includes(entryType)) details[field] = null;
  }
  return details;
}

/** Presence count for the privacy-safe field-presence log line (names/booleans, never content). */
export function typedFieldCount(details: TypedDetails): number {
  return TYPED_FIELD_NAMES.filter((field) => details[field] !== null).length;
}

/** How many optional parameters a strict tool schema carries — the tested ceiling. */
export function optionalParameterCount(tool: {
  input_schema: { properties: Record<string, unknown>; required?: ReadonlyArray<string> };
}): number {
  const required = new Set(tool.input_schema.required ?? []);
  return Object.keys(tool.input_schema.properties).filter((name) => !required.has(name)).length;
}

export type TypedDetailTool = {
  name: "record_entry_details";
  description: string;
  input_schema: {
    type: "object";
    properties: Record<string, unknown>;
    additionalProperties: false;
  };
  strict: true;
};

/** The typed fields that exist for an entry type; empty means the second call is skipped. */
export function typedFieldsFor(entryType: EntryTypeValue): Array<keyof TypedDetails> {
  return TYPED_FIELD_NAMES.filter((field) => FIELD_ENTRY_TYPES[field].includes(entryType));
}

/**
 * The second-call tool: only the given entry type's own fields, all optional. The widest is
 * tire at 6 properties — two orders of magnitude inside every measured schema limit.
 */
export function buildTypedDetailTool(entryType: EntryTypeValue): TypedDetailTool | null {
  const fields = typedFieldsFor(entryType);
  if (fields.length === 0) return null;
  const properties: Record<string, unknown> = {};
  for (const field of fields) properties[field] = TYPED_DETAIL_PROPERTIES[field];
  return {
    name: "record_entry_details",
    description: `Record the ${entryType} details the owner gave.`,
    input_schema: { type: "object", properties, additionalProperties: false },
    strict: true,
  };
}
