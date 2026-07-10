import { getFirestore } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";

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

type DocumentReferenceLike = object;

type DocumentSnapshotLike = {
  exists: boolean;
  data(): Record<string, unknown> | undefined;
};

type TransactionLike = {
  get(reference: DocumentReferenceLike): Promise<DocumentSnapshotLike>;
  set(reference: DocumentReferenceLike, data: Record<string, unknown>, options?: { merge?: boolean }): TransactionLike;
};

export type QuotaFirestore = {
  collection(path: string): {
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

export const MAX_PDF_BASE64_BYTES = 10 * 1024 * 1024;
export const DAILY_OIL_ANALYSIS_QUOTA = 5;

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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function dailyQuotaKey(uid: string, date: Date): string {
  return `${uid}_${date.toISOString().slice(0, 10)}`;
}

function safeQuotaCount(value: unknown): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

export async function consumeDailyOilAnalysisQuota(
  db: QuotaFirestore,
  uid: string,
  now: Date,
): Promise<string> {
  const date = now.toISOString().slice(0, 10);
  const quotaId = dailyQuotaKey(uid, now);
  const quotaRef = db.collection("usage_quotas").doc(quotaId);

  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(quotaRef);
    const count = current.exists ? safeQuotaCount(current.data()?.count) : 0;

    if (count >= DAILY_OIL_ANALYSIS_QUOTA) {
      throw new HttpsError("resource-exhausted", "Daily oil analysis quota exceeded.");
    }

    transaction.set(quotaRef, {
      uid,
      date,
      count: count + 1,
      updatedAt: now.toISOString(),
    }, { merge: true });
  });

  return quotaId;
}

function sanitizeString(value: unknown, maxLength: number): string | undefined {
  return typeof value === "string" ? value.slice(0, maxLength) : undefined;
}

function sanitizeNumber(value: unknown, minimum: number, maximum: number): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return undefined;
  }

  return Math.min(Math.max(value, minimum), maximum);
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
    const rawValue = input[field];
    if (rawValue === null) {
      result[field] = null;
      continue;
    }

    const range = numericRange(field);
    const sanitized = sanitizeNumber(rawValue, range.minimum, range.maximum);
    if (sanitized !== undefined) {
      result[field] = sanitized;
    }
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

function pdfBase64FromData(data: unknown): string | undefined {
  return isRecord(data) && typeof data.pdfBase64 === "string" && data.pdfBase64.length > 0
    ? data.pdfBase64
    : undefined;
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

  const apiKey = dependencies.apiKey;
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "Anthropic API key is not configured.");
  }

  const now = (dependencies.now ?? (() => new Date()))();
  await consumeDailyOilAnalysisQuota(dependencies.db, request.auth.uid, now);

  const response = await dependencies.fetchImpl("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-20250514",
      max_tokens: 2000,
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
              text: "Extract all oil analysis fields from this report and return structured JSON only.",
            },
          ],
        },
      ],
    }),
  });

  if (!response.ok) {
    throw new HttpsError("internal", `Claude request failed with ${response.status}.`);
  }

  let payload: { content?: Array<{ text?: string }> };
  try {
    payload = await response.json() as { content?: Array<{ text?: string }> };
  } catch {
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }

  const text = payload.content?.[0]?.text ?? "{}";

  try {
    return sanitizeOilAnalysisResponse(JSON.parse(text.replace(/```json|```/g, "").trim()) as unknown);
  } catch {
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }
}

export const parseOilAnalysis = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request): Promise<OilAnalysisResponse> => parseOilAnalysisRequest(request, {
    apiKey: process.env.ANTHROPIC_API_KEY,
    db: getFirestore() as unknown as QuotaFirestore,
    fetchImpl: fetch,
  }),
);
