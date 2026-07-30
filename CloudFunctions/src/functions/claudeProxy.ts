import { getFirestore } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { anthropicApiKey } from "../params";

export type OilAnalysisResponse = {
  labName: string;
  pdfPath?: string | null;
  aluminum?: number | null;
  chromium?: number | null;
  iron?: number | null;
  copper?: number | null;
  lead?: number | null;
  tin?: number | null;
  molybdenum?: number | null;
  nickel?: number | null;
  manganese?: number | null;
  silver?: number | null;
  titanium?: number | null;
  silicon?: number | null;
  sodium?: number | null;
  potassium?: number | null;
  viscosity?: string | null;
  insolubles?: number | null;
  milesOnOil?: number | null;
  labRecommendation?: string | null;
};

export type DocumentReferenceLike = {
  readonly path: string;
};

export type DocumentSnapshotLike = {
  exists: boolean;
  data(): Record<string, unknown> | undefined;
};

export type QueryDocumentSnapshotLike = {
  readonly ref: DocumentReferenceLike;
  data(): Record<string, unknown>;
};

export type QuerySnapshotLike = {
  readonly docs: QueryDocumentSnapshotLike[];
};

export type QueryLike = {
  where(fieldPath: string, opStr: string, value: unknown): QueryLike;
  limit(limit: number): QueryLike;
};

export type TransactionLike = {
  get(reference: DocumentReferenceLike): Promise<DocumentSnapshotLike>;
  get(query: QueryLike): Promise<QuerySnapshotLike>;
  set(reference: DocumentReferenceLike, data: Record<string, unknown>, options?: { merge?: boolean }): TransactionLike;
  create(reference: DocumentReferenceLike, data: Record<string, unknown>): TransactionLike;
};

export type QuotaFirestore = {
  collection(path: string): QueryLike & {
    doc(id: string): DocumentReferenceLike;
  };
  runTransaction<T>(updateFunction: (transaction: TransactionLike) => Promise<T>): Promise<T>;
};

export type OilAnalysisRequest = {
  auth?: { uid: string } | null;
  data?: unknown;
};

export type ParseOilAnalysisDependencies = {
  apiKey?: string;
  db: QuotaFirestore;
  fetchImpl: typeof fetch;
  now?: () => Date;
};

/**
 * Forced strict tool use replaced free-text JSON parsing.
 *
 * The old path asked for "structured JSON only", then ran
 * `JSON.parse(text.replace(/```json|```/g, "").trim())`. Every failure mode of that — a stray
 * prose sentence, a fence variant the regex missed, a truncated object — surfaced to the user as
 * "Claude returned malformed JSON" AND kept their quota unit, because inference had been billed.
 * With `strict: true` and a forced `tool_choice`, the model cannot return anything but an object
 * matching this schema, so that entire failure class is gone rather than handled.
 *
 * Field types are plain rather than nullable unions on purpose: the API rejects a strict schema
 * with more than ~18 union-typed parameters ("Schemas contains too many parameters with union
 * types ... exponential compilation", verified live). Optional-and-absent expresses "not in the
 * report" just as well, and `sanitizeOilAnalysisResponse` already treats a missing field as null.
 */
const PPM_FIELDS = [
  "aluminum", "chromium", "iron", "copper", "lead", "tin", "molybdenum",
  "nickel", "manganese", "silver", "titanium", "silicon", "sodium", "potassium",
] as const;

export const OIL_ANALYSIS_TOOL = {
  name: "record_oil_analysis",
  description: "Record every field extracted from the oil analysis report.",
  input_schema: {
    type: "object",
    properties: {
      labName: { type: "string", description: "Laboratory that produced the report." },
      ...Object.fromEntries(PPM_FIELDS.map((field) => [field, {
        type: "number",
        description: `${field} in parts per million, read from the SAMPLE column.`,
      }])),
      viscosity: { type: "string", description: "Viscosity exactly as printed, e.g. '13.4 cSt @ 100C'." },
      insolubles: { type: "number", description: "Insolubles percentage, as a number." },
      milesOnOil: {
        type: "number",
        description: "Miles on the OIL since it was changed — NOT the vehicle's total mileage.",
      },
      labRecommendation: { type: "string", description: "The lab's recommendation, closely paraphrased." },
    },
    required: ["labName"],
    additionalProperties: false,
  },
  strict: true,
} as const;

/**
 * Two instructions here exist because of specific, observed extraction errors, not general
 * politeness. A wear metal printed as `0` is a real measurement — models otherwise treat it as
 * "nothing to report" and omit the field, which turns a clean result into a missing one. And these
 * reports print a universal-average column beside the sample column; reading the wrong one yields
 * plausible numbers that are not this engine's.
 */
export const OIL_ANALYSIS_SYSTEM_PROMPT =
  "You extract oil-analysis reports. Populate every field the report contains. A wear metal " +
  "printed as 0 is a real measurement of zero and must be recorded as 0, never omitted. Read " +
  "values from the SAMPLE column, never from the universal-average column. Omit a field only " +
  "when the report genuinely does not contain it.";

export const MAX_PDF_BASE64_BYTES = 10 * 1024 * 1024;
export const DAILY_OIL_ANALYSIS_QUOTA = 5;
export const FREE_LIFETIME_OIL_ANALYSIS_QUOTA = 10;

type NumericField = Exclude<keyof OilAnalysisResponse, "labName" | "pdfPath" | "viscosity" | "labRecommendation">;

const numericFields: ReadonlyArray<NumericField> = [
  "aluminum",
  "chromium",
  "iron",
  "copper",
  "lead",
  "tin",
  "molybdenum",
  "nickel",
  "manganese",
  "silver",
  "titanium",
  "silicon",
  "sodium",
  "potassium",
  "insolubles",
  "milesOnOil",
];

/**
 * A metal value or a named lab is the minimum signal needed to recognize an
 * oil-analysis report. Supplemental fields alone must not turn arbitrary JSON
 * into a successful report.
 */
const coreMetalFields: ReadonlyArray<NumericField> = [
  "aluminum",
  "chromium",
  "iron",
  "copper",
  "lead",
  "tin",
  "molybdenum",
  "nickel",
  "manganese",
  "silver",
  "titanium",
];

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function dailyQuotaKey(uid: string, date: Date): string {
  return `${uid}_${date.toISOString().slice(0, 10)}`;
}

function lifetimeQuotaKey(uid: string): string {
  return `${uid}_lifetime`;
}

export function safeQuotaCount(value: unknown): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

type OilAnalysisEntitlement = "free" | "pro";

export type OilAnalysisQuotaReservation =
  | {
    bucketId: string;
    date: string;
    entitlementUsed: "pro";
    uid: string;
  }
  | {
    bucketId: string;
    entitlementUsed: "free";
    uid: string;
  };

function parseMillis(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? undefined : parsed;
  }

  if (value instanceof Date) {
    const parsed = value.getTime();
    return Number.isNaN(parsed) ? undefined : parsed;
  }

  if (isRecord(value) && typeof value.toMillis === "function") {
    try {
      const parsed = value.toMillis();
      return typeof parsed === "number" && Number.isFinite(parsed) ? parsed : undefined;
    } catch {
      return undefined;
    }
  }

  return undefined;
}

export function userHasActiveProEntitlement(userData: Record<string, unknown> | undefined, now: Date): boolean {
  const subscription = userData && isRecord(userData.subscription) ? userData.subscription : undefined;
  const expiresAt = subscription?.expiresAt;
  const expiresAtMillis = parseMillis(expiresAt);

  return subscription?.entitlement === "pro"
    && subscription?.isActive === true
    && (expiresAt == null || (expiresAtMillis !== undefined && expiresAtMillis > now.getTime()));
}

export function nextUtcMidnight(now: Date): string {
  return new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate() + 1,
  )).toISOString();
}

/** The receipt-confirmed allowance resets monthly, unlike the daily AI quotas. */
export function nextUtcMonthStart(now: Date): string {
  return new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth() + 1,
    1,
  )).toISOString();
}

/**
 * Selects the entitlement bucket and reserves one analysis in a single
 * transaction so a user-profile change cannot split selection from charging.
 */
export async function consumeOilAnalysisQuota(
  db: QuotaFirestore,
  uid: string,
  now: Date,
): Promise<OilAnalysisQuotaReservation> {
  const date = now.toISOString().slice(0, 10);
  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (transaction) => {
    const user = await transaction.get(userRef);
    const entitlementUsed: OilAnalysisEntitlement = userHasActiveProEntitlement(user.data(), now) ? "pro" : "free";
    const bucketId = entitlementUsed === "pro" ? dailyQuotaKey(uid, now) : lifetimeQuotaKey(uid);
    const quotaRef = db.collection("usage_quotas").doc(bucketId);
    const current = await transaction.get(quotaRef);
    const count = current.exists ? safeQuotaCount(current.data()?.count) : 0;

    if (entitlementUsed === "pro" && count >= DAILY_OIL_ANALYSIS_QUOTA) {
      throw new HttpsError("resource-exhausted", "Daily oil analysis quota exceeded.", {
        reason: "pro_daily_exhausted",
        entitlementUsed: "pro",
        resetAt: nextUtcMidnight(now),
      });
    }

    if (entitlementUsed === "free" && count >= FREE_LIFETIME_OIL_ANALYSIS_QUOTA) {
      throw new HttpsError("resource-exhausted", "Free oil analysis quota exhausted.", {
        reason: "free_lifetime_exhausted",
        entitlementUsed: "free",
      });
    }

    transaction.set(quotaRef, entitlementUsed === "pro" ? {
      uid,
      date,
      count: count + 1,
      updatedAt: now.toISOString(),
    } : {
      uid,
      kind: "oil_analysis_lifetime",
      count: count + 1,
      updatedAt: now.toISOString(),
    }, { merge: true });

    return entitlementUsed === "pro" ? {
      bucketId,
      date,
      entitlementUsed,
      uid,
    } : {
      bucketId,
      entitlementUsed,
      uid,
    };
  });
}

/**
 * Returns a previously consumed quota unit only after a genuine upstream
 * infrastructure failure. A completed model response consumes upstream cost,
 * even when its output is malformed or cannot be recognized as an analysis.
 */
export async function refundOilAnalysisQuota(
  db: QuotaFirestore,
  reservation: OilAnalysisQuotaReservation,
  now: Date,
): Promise<void> {
  const quotaRef = db.collection("usage_quotas").doc(reservation.bucketId);

  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(quotaRef);
    const count = current.exists ? safeQuotaCount(current.data()?.count) : 0;

    transaction.set(quotaRef, reservation.entitlementUsed === "pro" ? {
      uid: reservation.uid,
      date: reservation.date,
      count: Math.max(0, count - 1),
      updatedAt: now.toISOString(),
    } : {
      uid: reservation.uid,
      kind: "oil_analysis_lifetime",
      count: Math.max(0, count - 1),
      updatedAt: now.toISOString(),
    }, { merge: true });
  });
}

function sanitizeString(value: unknown, maxLength: number): string | undefined {
  return typeof value === "string" ? value.slice(0, maxLength) : undefined;
}

function sanitizeNumber(value: unknown, minimum: number, maximum: number): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return undefined;
  }

  return value >= minimum && value <= maximum ? value : undefined;
}

function numericRange(field: NumericField): { minimum: number; maximum: number } {
  if (field === "insolubles") {
    return { minimum: 0, maximum: 100 };
  }

  if (field === "milesOnOil") {
    return { minimum: 0, maximum: 2_000_000 };
  }

  return { minimum: 0, maximum: 1_000_000 };
}

/**
 * Keeps only the typed OilAnalysisResponse contract. Values from a model are
 * untrusted even after they are valid JSON.
 */
export function sanitizeOilAnalysisResponse(value: unknown): OilAnalysisResponse {
  const input = isRecord(value) ? value : {};
  const result: Record<string, unknown> = {
    labName: sanitizeString(input.labName, 200) ?? "Unknown lab",
  };

  for (const field of numericFields) {
    if (!(field in input)) {
      continue;
    }

    const rawValue = input[field];
    if (rawValue === null) {
      result[field] = null;
      continue;
    }

    const range = numericRange(field);
    const sanitized = sanitizeNumber(rawValue, range.minimum, range.maximum);
    // Model output is untrusted. An invalid present value is absence of
    // evidence, not permission to manufacture a nearby plausible value.
    result[field] = sanitized ?? null;
  }

  const stringFields: ReadonlyArray<[keyof Pick<OilAnalysisResponse, "pdfPath" | "viscosity" | "labRecommendation">, number]> = [
    ["pdfPath", 2_000],
    ["viscosity", 100],
    ["labRecommendation", 4_000],
  ];

  for (const [field, maxLength] of stringFields) {
    const rawValue = input[field];
    if (rawValue === null) {
      result[field] = null;
      continue;
    }

    const sanitized = sanitizeString(rawValue, maxLength);
    if (sanitized !== undefined) {
      result[field] = sanitized;
    }
  }

  return result as OilAnalysisResponse;
}

function hasLabNameSignal(value: Record<string, unknown>): boolean {
  return typeof value.labName === "string" && value.labName.trim().length > 0;
}

function isRecognizableOilAnalysis(value: unknown, sanitized: OilAnalysisResponse): boolean {
  if (!isRecord(value)) {
    return false;
  }

  return hasLabNameSignal(value)
    || coreMetalFields.some((field) => typeof sanitized[field] === "number");
}

function pdfBase64FromData(data: unknown): string | undefined {
  return isRecord(data) && typeof data.pdfBase64 === "string" && data.pdfBase64.length > 0
    ? data.pdfBase64
    : undefined;
}

const base64Pattern = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const pdfMagic = Buffer.from("%PDF-", "utf8");

function isStandardBase64(value: string): boolean {
  return value.length % 4 === 0 && base64Pattern.test(value);
}

function hasPdfMagic(value: string): boolean {
  // Five decoded bytes require at most eight base64 characters. Do not decode
  // the full user-supplied payload merely to validate the file signature.
  return Buffer.from(value.slice(0, 8), "base64").subarray(0, pdfMagic.length).equals(pdfMagic);
}

/**
 * Picks the tool input from a forced-tool-use response.
 *
 * A response can contain MORE THAN ONE tool_use block, and they are not equally good: measured
 * against a real report, the first block was sometimes a partial draft carrying only two or three
 * fields while a later block held the full extraction. Taking `content[0]`, or the first tool_use,
 * therefore silently discarded most of the data — the extraction looked like it worked and wrote
 * three fields into the user's vehicle record.
 *
 * Selecting the block with the most populated fields is deterministic and degrades safely: a
 * partial or garbled block can only win when nothing better exists, and `sanitizeOilAnalysisResponse`
 * still drops anything off-contract afterwards.
 */
function toolInputFromPayload(payload: unknown): Record<string, unknown> | undefined {
  if (!isRecord(payload) || !Array.isArray(payload.content)) {
    return undefined;
  }

  let best: Record<string, unknown> | undefined;
  let bestCount = -1;
  for (const block of payload.content) {
    if (!isRecord(block) || block.type !== "tool_use" || !isRecord(block.input)) {
      continue;
    }
    const populated = Object.values(block.input).filter(
      (value) => value !== null && value !== undefined && value !== "",
    ).length;
    if (populated > bestCount) {
      best = block.input;
      bestCount = populated;
    }
  }
  return best;
}


export async function parseOilAnalysisRequest(
  request: OilAnalysisRequest,
  dependencies: ParseOilAnalysisDependencies,
): Promise<OilAnalysisResponse> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const pdfBase64 = pdfBase64FromData(request.data);
  if (!pdfBase64) {
    throw new HttpsError("invalid-argument", "PDF data is required.");
  }

  if (Buffer.byteLength(pdfBase64, "utf8") > MAX_PDF_BASE64_BYTES) {
    throw new HttpsError("invalid-argument", "PDF data exceeds the 10 MB base64 limit.");
  }

  if (!isStandardBase64(pdfBase64)) {
    throw new HttpsError("invalid-argument", "PDF data must be valid base64.");
  }

  if (!hasPdfMagic(pdfBase64)) {
    throw new HttpsError("invalid-argument", "PDF data must begin with a PDF signature.");
  }

  const apiKey = dependencies.apiKey;
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "Anthropic API key is not configured.");
  }

  const now = (dependencies.now ?? (() => new Date()))();
  const reservation = await consumeOilAnalysisQuota(dependencies.db, request.auth.uid, now);

  let response: Response;
  try {
    response = await dependencies.fetchImpl("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        // Haiku 4.5 (operator directive 2026-07-24). Sonnet 4 was deprecated (retires
        // 2026-06-15) and cost 3x for a bounded extraction task.
        // NOTE: `output_config.effort` is NOT supported on Haiku 4.5 — it errors. The
        // low/medium/high/xhigh/max ladder starts at Opus 4.5 / Sonnet 4.6.
        model: "claude-haiku-4-5",
        max_tokens: 4000,
        // Extended thinking was REMOVED here, not forgotten: the API rejects it outright with
        // "Thinking may not be enabled when tool_choice forces tool use" (400, verified against
        // the live API). Forcing the tool is worth more than the thinking budget, because it is
        // what guarantees a schema-valid extraction rather than free text we have to parse.
        system: OIL_ANALYSIS_SYSTEM_PROMPT,
        tools: [OIL_ANALYSIS_TOOL],
        tool_choice: { type: "tool", name: OIL_ANALYSIS_TOOL.name },
        messages: [
          {
            role: "user",
            content: [
              {
                type: "document",
                source: {
                  type: "base64",
                  media_type: "application/pdf",
                  data: pdfBase64,
                },
              },
              {
                type: "text",
                text: "Extract every oil-analysis field from this report.",
              },
            ],
          },
        ],
      }),
    });
  } catch (error) {
    // The raw network failure would otherwise be invisible behind the generic client error.
    logger.error("oil-analysis anthropic request failed", {
      message: error instanceof Error ? error.message : String(error),
    });
    await refundOilAnalysisQuota(dependencies.db, reservation, now);
    throw new HttpsError("internal", "Claude request failed.");
  }

  if (!response.ok) {
    logger.error("oil-analysis anthropic request rejected", { status: response.status });
    // Anthropic did not complete billable inference on a 5xx response. Other
    // HTTP failures and all HTTP-OK model-output errors keep their quota unit.
    if (response.status >= 500) {
      await refundOilAnalysisQuota(dependencies.db, reservation, now);
    }
    throw new HttpsError("internal", `Claude request failed with ${response.status}.`);
  }

  let payload: unknown;
  try {
    payload = await response.json();
  } catch (error) {
    // Classified reason only: V8 parse errors embed source snippets of the content.
    logger.error("oil-analysis anthropic response body unreadable", {
      reason: error instanceof Error ? error.name : "unknown",
    });
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }

  // No fence stripping and no JSON.parse: a forced strict tool call returns an object the API has
  // already validated against the schema. The only remaining question is which block to read.
  const parsed = toolInputFromPayload(payload);
  if (!parsed) {
    logger.error("oil-analysis anthropic response had no tool_use block");
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }

  try {
    const sanitized = sanitizeOilAnalysisResponse(parsed);
    if (!isRecognizableOilAnalysis(parsed, sanitized)) {
      throw new HttpsError("internal", "unrecognized analysis response");
    }
    return sanitized;
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    // Model-output text is intentionally not logged (it can embed the user's document content) —
    // including JSON.parse messages, which embed a snippet of the unparseable source.
    logger.error("oil-analysis model output unparseable", {
      reason: error instanceof Error ? error.name : "unknown",
    });
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }
}

export const parseOilAnalysis = onCall(
  { region: "us-central1", enforceAppCheck: true, secrets: [anthropicApiKey] },
  async (request): Promise<OilAnalysisResponse> => {
    try {
      return await parseOilAnalysisRequest(request, {
        apiKey: anthropicApiKey.value(),
        db: getFirestore() as unknown as QuotaFirestore,
        fetchImpl: fetch,
      });
    } catch (error) {
      logger.error("parseOilAnalysis failed", {
        uid: request.auth?.uid,
        code: error instanceof HttpsError ? error.code : "internal",
        message: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  },
);
