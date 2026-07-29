import { getFirestore } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { anthropicApiKey } from "../params";
import {
  QuotaFirestore,
  isRecord,
  nextUtcMidnight,
  safeQuotaCount,
  userHasActiveProEntitlement,
} from "./claudeProxy";
import {
  VALID_ENTRY_TYPES,
  EntryTypeValue,
  referenceDateLine,
  toolInputFromPayload,
} from "./voiceQuickAdd";

// Re-exported so the golden eval imports the exact response picker prod uses (no drift).
export { toolInputFromPayload, referenceDateLine };

/**
 * Receipt quick-add turns a photographed (or PDF) shop receipt/invoice into a *prefill proposal*
 * for the entry form — it never writes an entry itself; the user confirms/edits in the form
 * (Trust Pledge). Model output is untrusted and sanitized to a fixed contract before it leaves
 * this function. Plan: docs/research/2026-07-28_RECEIPT_PARSE_PLAN.md.
 *
 * PII rule (hard, both siblings verbatim): no request content, no model output, no image or
 * document bytes are ever logged — status codes and classified reason names only. Receipts are
 * worse than transcripts: names, addresses, card last-4, VINs.
 */

/**
 * Quota model of record (plan §5; tri-vote checkpoint A may adjust the numbers — they are
 * isolated here as the single source of truth for both buckets).
 */
export const FREE_LIFETIME_RECEIPT_QUOTA = 3;
export const DAILY_RECEIPT_QUOTA = 20;

export const MAX_RECEIPT_IMAGES = 2;
/** Per-image base64 ceiling. The client's 1568px q0.85 parse variant sits far below this. */
export const MAX_IMAGE_BASE64_BYTES = 4 * 1024 * 1024;
/** Matches OilAnalysisPDFPreflighter.maxPDFBase64Bytes on the client. */
export const MAX_RECEIPT_PDF_BASE64_BYTES = 9 * 1024 * 1024;
/** Envelope headroom under the 10 MiB callable payload limit. */
export const MAX_TOTAL_BASE64_BYTES = 9 * 1024 * 1024;

export type ReceiptEntryProposal = {
  entryType: EntryTypeValue;
  odometerReading: number | null;
  cost: number | null;
  shopName: string | null;
  isDiy: boolean | null;
  entryDate: string | null;
  notes: string | null;
  lineItems: string[];
};

export type ReceiptQuickAddRequest = { auth?: { uid: string } | null; data?: unknown };

export type ReceiptQuickAddDependencies = {
  apiKey?: string;
  db: QuotaFirestore;
  fetchImpl: typeof fetch;
  now?: () => Date;
};

export type ReceiptQuotaReservation =
  | { bucketId: string; date: string; entitlementUsed: "pro"; uid: string }
  | { bucketId: string; entitlementUsed: "free"; uid: string };

/**
 * Dual-bucket clone of consumeOilAnalysisQuota (claudeProxy.ts): entitlement selection and
 * charging happen in ONE transaction so a user-profile change can never split them. Free users
 * are admitted for a lifetime teaser of FREE_LIFETIME_RECEIPT_QUOTA scans; Pro users get
 * DAILY_RECEIPT_QUOTA per UTC day. There is deliberately NO pro_required fence in this model
 * (plan §5, fix F4).
 */
export async function consumeReceiptQuota(
  db: QuotaFirestore,
  uid: string,
  now: Date,
): Promise<ReceiptQuotaReservation> {
  const date = now.toISOString().slice(0, 10);
  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (transaction) => {
    const user = await transaction.get(userRef);
    const entitlementUsed = userHasActiveProEntitlement(user.data(), now) ? "pro" : "free";
    const bucketId = entitlementUsed === "pro" ? `${uid}_receipt_${date}` : `${uid}_receipt_lifetime`;
    const quotaRef = db.collection("usage_quotas").doc(bucketId);
    const current = await transaction.get(quotaRef);
    const count = current.exists ? safeQuotaCount(current.data()?.count) : 0;

    if (entitlementUsed === "pro" && count >= DAILY_RECEIPT_QUOTA) {
      throw new HttpsError("resource-exhausted", "Daily receipt quota exceeded.", {
        reason: "receipt_daily_exhausted",
        resetAt: nextUtcMidnight(now),
      });
    }

    if (entitlementUsed === "free" && count >= FREE_LIFETIME_RECEIPT_QUOTA) {
      throw new HttpsError("resource-exhausted", "Free receipt quota exhausted.", {
        reason: "receipt_free_exhausted",
      });
    }

    transaction.set(quotaRef, entitlementUsed === "pro" ? {
      uid,
      kind: "receipt_quickadd",
      date,
      count: count + 1,
      updatedAt: now.toISOString(),
    } : {
      uid,
      kind: "receipt_quickadd_lifetime",
      count: count + 1,
      updatedAt: now.toISOString(),
    }, { merge: true });

    return entitlementUsed === "pro"
      ? { bucketId, date, entitlementUsed, uid }
      : { bucketId, entitlementUsed, uid };
  });
}

/**
 * Returns a previously consumed quota unit only after a genuine upstream infrastructure
 * failure. Mirrors both siblings' policy: a completed model response consumes upstream cost,
 * even when its output is malformed, unrecognized, or not a receipt at all.
 */
export async function refundReceiptQuota(
  db: QuotaFirestore,
  reservation: ReceiptQuotaReservation,
  now: Date,
): Promise<void> {
  const quotaRef = db.collection("usage_quotas").doc(reservation.bucketId);

  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(quotaRef);
    const count = current.exists ? safeQuotaCount(current.data()?.count) : 0;

    transaction.set(quotaRef, reservation.entitlementUsed === "pro" ? {
      uid: reservation.uid,
      kind: "receipt_quickadd",
      date: reservation.date,
      count: Math.max(0, count - 1),
      updatedAt: now.toISOString(),
    } : {
      uid: reservation.uid,
      kind: "receipt_quickadd_lifetime",
      count: Math.max(0, count - 1),
      updatedAt: now.toISOString(),
    }, { merge: true });
  });
}

/**
 * Forced strict tool schema (plan §3). `documentLooksLikeReceipt` is the explicit
 * escape hatch (graft G1): forced tool_choice means the model MUST emit an object even for a
 * photo of a dog, so the boolean — not a refusal — is how "this is not a receipt" surfaces.
 * Plain optional types, zero union-typed params (the ~18-union strict-schema limit documented
 * in claudeProxy.ts).
 *
 * DEVIATION from plan §3, forced by the live API: strict tool use rejects array-constraint
 * keywords — `maxItems` in a strict input_schema 400s the whole request ("complex array
 * constraints" are outside the supported JSON Schema subset; the official SDKs strip them
 * client-side, but this function calls fetch directly). The 20-item cap therefore lives in
 * the description text (model guidance) and in sanitizeReceiptProposal (hard enforcement) —
 * the F3 schema/sanitizer agreement is now description+sanitizer, both saying 20.
 */
export const RECEIPT_ENTRY_TOOL = {
  name: "record_receipt_entry",
  description: "Record the maintenance-log entry described by this vehicle service receipt or invoice.",
  input_schema: {
    type: "object",
    properties: {
      documentLooksLikeReceipt: {
        type: "boolean",
        description: "False when the document is not a vehicle service receipt or invoice " +
          "(a menu, a random photo, an unrelated bill). All other fields may then be omitted.",
      },
      entryType: {
        type: "string",
        enum: VALID_ENTRY_TYPES,
        description: "The single best entry type for the work on this receipt. Use maintenance " +
          "if unsure. A retail parts purchase with no labor is usually the type of the part " +
          "(tire, brake, oil_change) or upgrade.",
      },
      shopName: { type: "string",
        description: "The business name printed at the top of the receipt or invoice." },
      entryDate: { type: "string",
        description: "ISO 8601 date of the SERVICE, exactly as printed. Never the payment-due " +
          "date, statement date, or reprint date. Omit if no date is printed." },
      cost: { type: "number",
        description: "The GRAND TOTAL in USD including tax — never the subtotal, amount " +
          "tendered, or change." },
      odometerReading: { type: "number",
        description: "The vehicle's mileage if printed (often labeled Mileage, Odometer, or " +
          "Miles In). Never an invoice number, RO number, phone number, ZIP, VIN, or part number." },
      isDiy: { type: "boolean",
        description: "True when this is a retail parts purchase (owner did the work), false " +
          "when it is a shop service invoice with labor." },
      lineItems: { type: "array", items: { type: "string" },
        description: "Each service or part line with its price, e.g. 'Synthetic oil 5W-30 x6 — " +
          "$54.00'. At most 20 lines. Omit tax and total lines." },
      notes: { type: "string",
        description: "Anything else material the other fields do not capture: warranty terms, " +
          "next-service recommendation, technician remarks." },
    },
    required: ["entryType", "documentLooksLikeReceipt"],
    additionalProperties: false,
  },
  strict: true,
} as const;

/**
 * Each clause targets a receipt failure class (plan §4); iterate ONLY under the golden eval
 * (scripts/receiptGoldenEval.ts) — a drop is a regression regardless of plausibility:
 * - GRAND TOTAL vs the subtotal/tendered/change stack (the classic receipt money trap).
 * - Odometer vs the RO#/invoice#/phone/ZIP/VIN mileage-shaped numbers invoices are covered in.
 * - SERVICE date vs payment-due/statement/reprint dates.
 * - Conversion-is-recording (the voice chilling-effect lesson, pre-applied to print).
 * - Unreadable values are omitted, never guessed.
 * - Parts-only receipts suggest DIY.
 * - documentLooksLikeReceipt=false is the non-receipt escape hatch (G1).
 * referenceDateLine(now) is appended at call time — the documented voice lesson: without it the
 * model hallucinates past years the sanitizer accepts, and it must live in the SYSTEM prompt.
 */
export const SYSTEM_PROMPT =
  "You extract one vehicle service receipt or invoice into a single maintenance-log entry." +
  " Read the GRAND TOTAL including tax as the cost — never the subtotal, amount tendered, or" +
  " change. The odometer is the vehicle-mileage line (Mileage, Odometer, Miles In) — never an" +
  " invoice number, RO number, phone number, ZIP code, or VIN fragment; when a current odometer" +
  " is stated for the vehicle, cross-check that your reading is plausible against it. Use the" +
  " date the SERVICE was performed — never a payment-due date, statement date, or reprint date." +
  " Converting printed text to digits and dates is recording, not inventing: capture every value" +
  " the receipt prints into its matching field. Omit a value you cannot read — never guess." +
  " A retail parts receipt with no labor lines suggests the owner did the work (isDiy)." +
  " Set documentLooksLikeReceipt to false for anything that is not a vehicle service receipt" +
  " or invoice.";

const DAY_MS = 86_400_000;

function utcDay(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/**
 * One compact text-transcribed worked exchange (the voice `fewShotMessages` pattern — plan
 * deliberately ships a TEXT exemplar, with the eval's few-shot ON/OFF A/B validating that it
 * transfers to vision rather than assuming it). It packs the three receipt traps in one
 * document: an RO number printed beside the mileage, a subtotal/tax/total stack, and a printed
 * service date. The date is COMPUTED from `now` — a hardcoded date would drift stale and teach
 * the model to emit old years.
 */
export function receiptFewShotMessages(now: Date): unknown[] {
  const serviceDate = new Date(now.getTime() - 3 * DAY_MS);
  const serviceDay = utcDay(serviceDate);
  const printedDate = `${serviceDay.slice(5, 7)}/${serviceDay.slice(8, 10)}/${serviceDay.slice(0, 4)}`;
  return [
    {
      role: "user",
      content: [{
        type: "text",
        text: "Extract this vehicle service receipt into a log entry. The receipt reads:\n" +
          "\"MERIDIAN AUTO CARE — 2280 Fulton Ave\n" +
          `RO #48213    Date: ${printedDate}    Mileage: 87,412\n` +
          "Front brake pads & rotors ........ $286.00\n" +
          "Labor 1.5 hr ..................... $142.50\n" +
          "Subtotal $428.50   Tax $34.28\n" +
          "TOTAL $462.78   VISA TEND $462.78\"",
      }],
    },
    {
      role: "assistant",
      content: [{
        type: "tool_use",
        id: "toolu_receipt_example_01",
        name: "record_receipt_entry",
        input: {
          documentLooksLikeReceipt: true,
          entryType: "brake",
          shopName: "Meridian Auto Care",
          entryDate: serviceDay,
          cost: 462.78,
          odometerReading: 87412,
          isDiy: false,
          lineItems: ["Front brake pads & rotors — $286.00", "Labor 1.5 hr — $142.50"],
        },
      }],
    },
    {
      role: "user",
      content: [{ type: "tool_result", tool_use_id: "toolu_receipt_example_01", content: "Recorded." }],
    },
  ];
}

function clampString(value: unknown, maxLength: number): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim().slice(0, maxLength) : null;
}

function clampNumber(value: unknown, minimum: number, maximum: number): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value >= minimum && value <= maximum ? value : null;
}

/** voiceQuickAdd.ts clampEntryDate verbatim: any past date is allowed — backfilling old
 *  receipts is the flagship use-case — while a future date beyond +36h is implausible. */
function clampEntryDate(value: unknown, now: Date): string | null {
  if (typeof value !== "string") return null;
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) return null;
  return parsed <= now.getTime() + 36 * 60 * 60 * 1000 ? new Date(parsed).toISOString() : null;
}

function clampLineItems(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const items: string[] = [];
  for (const member of value) {
    if (items.length >= 20) break;
    if (typeof member !== "string" || member.trim().length === 0) continue;
    items.push(member.trim().slice(0, 160));
  }
  return items;
}

/** Keeps only the typed ReceiptEntryProposal contract from untrusted model output (plan §4). */
export function sanitizeReceiptProposal(value: unknown, now: Date): ReceiptEntryProposal {
  const input = isRecord(value) ? value : {};
  const rawType = typeof input.entryType === "string" ? input.entryType : "";
  const entryType: EntryTypeValue =
    (VALID_ENTRY_TYPES as ReadonlyArray<string>).includes(rawType) ? rawType as EntryTypeValue : "maintenance";
  return {
    entryType,
    odometerReading: clampNumber(input.odometerReading, 0, 2_000_000),
    cost: clampNumber(input.cost, 0, 1_000_000),
    shopName: clampString(input.shopName, 200),
    isDiy: typeof input.isDiy === "boolean" ? input.isDiy : null,
    entryDate: clampEntryDate(input.entryDate, now),
    notes: clampString(input.notes, 2_000),
    lineItems: clampLineItems(input.lineItems),
  };
}

/**
 * Recognizability backstop (mirrors isRecognizableOilAnalysis): with documentLooksLikeReceipt
 * carrying the explicit verdict, arbitrary schema-valid JSON must still not masquerade as a
 * successful extraction — require at least one core receipt signal in the RAW input.
 */
export function isRecognizableReceipt(value: unknown): boolean {
  if (!isRecord(value)) return false;
  return (typeof value.shopName === "string" && value.shopName.trim().length > 0)
    || (typeof value.cost === "number" && Number.isFinite(value.cost))
    || (typeof value.entryDate === "string" && value.entryDate.trim().length > 0);
}

// --- request validation (claudeProxy's isStandardBase64 / magic-byte technique; those helpers
// --- are module-private there, so the pattern is cloned, not imported) -----------------------

const base64Pattern = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const jpegMagic = Buffer.from([0xff, 0xd8, 0xff]);
const pdfMagic = Buffer.from("%PDF-", "utf8");

function isStandardBase64(value: string): boolean {
  return value.length % 4 === 0 && base64Pattern.test(value);
}

/** Decodes at most eight base64 characters — never the full user-supplied payload — to
 *  validate the file signature. JPEG only for images (fix F2): the client always re-encodes. */
function hasMagic(value: string, magic: Buffer): boolean {
  return Buffer.from(value.slice(0, 8), "base64").subarray(0, magic.length).equals(magic);
}

type ReceiptPayload =
  | { kind: "images"; images: string[] }
  | { kind: "pdf"; pdfBase64: string };

function payloadFromData(data: unknown): ReceiptPayload {
  if (!isRecord(data)) throw new HttpsError("invalid-argument", "Receipt data is required.");

  const hasImages = data.images !== undefined;
  const hasPdf = data.pdfBase64 !== undefined;
  if (hasImages === hasPdf) {
    throw new HttpsError("invalid-argument", "Provide exactly one of images or pdfBase64.");
  }

  if (hasPdf) {
    if (typeof data.pdfBase64 !== "string" || data.pdfBase64.length === 0) {
      throw new HttpsError("invalid-argument", "pdfBase64 must be a non-empty string.");
    }
    return { kind: "pdf", pdfBase64: data.pdfBase64 };
  }

  if (!Array.isArray(data.images)
    || data.images.length < 1
    || data.images.length > MAX_RECEIPT_IMAGES
    || data.images.some((image) => typeof image !== "string" || image.length === 0)) {
    throw new HttpsError(
      "invalid-argument",
      `images must be 1-${MAX_RECEIPT_IMAGES} non-empty base64 strings.`,
    );
  }
  return { kind: "images", images: data.images as string[] };
}

/** All validation happens BEFORE any quota spend (plan §4). Total size is checked first so an
 *  oversized envelope fails as such even when a single member also breaks its own cap. */
function validatePayload(payload: ReceiptPayload): void {
  const members = payload.kind === "images" ? payload.images : [payload.pdfBase64];
  const totalBytes = members.reduce((sum, member) => sum + Buffer.byteLength(member, "utf8"), 0);
  if (totalBytes > MAX_TOTAL_BASE64_BYTES) {
    throw new HttpsError("invalid-argument", "Receipt payload exceeds the 9 MB base64 limit.");
  }

  if (payload.kind === "pdf") {
    if (Buffer.byteLength(payload.pdfBase64, "utf8") > MAX_RECEIPT_PDF_BASE64_BYTES) {
      throw new HttpsError("invalid-argument", "PDF data exceeds the 9 MB base64 limit.");
    }
    if (!isStandardBase64(payload.pdfBase64)) {
      throw new HttpsError("invalid-argument", "PDF data must be valid base64.");
    }
    if (!hasMagic(payload.pdfBase64, pdfMagic)) {
      throw new HttpsError("invalid-argument", "PDF data must begin with a PDF signature.");
    }
    return;
  }

  for (const image of payload.images) {
    if (Buffer.byteLength(image, "utf8") > MAX_IMAGE_BASE64_BYTES) {
      throw new HttpsError("invalid-argument", "An image exceeds the 4 MB base64 limit.");
    }
    if (!isStandardBase64(image)) {
      throw new HttpsError("invalid-argument", "Images must be valid base64.");
    }
    if (!hasMagic(image, jpegMagic)) {
      throw new HttpsError("invalid-argument", "Images must be JPEG.");
    }
  }
}

function vehicleContextLine(data: unknown): string {
  if (!isRecord(data) || !isRecord(data.vehicle)) return "";
  const v = data.vehicle;
  const parts = [v.year, v.make, v.model].filter((p) => typeof p === "string" || typeof p === "number");
  const odo = typeof v.currentOdometer === "number" ? `, current odometer ${v.currentOdometer}` : "";
  return parts.length ? `The vehicle is a ${parts.join(" ")}${odo}. ` : "";
}

function sourceBlocks(payload: ReceiptPayload): unknown[] {
  if (payload.kind === "pdf") {
    return [{
      type: "document",
      source: { type: "base64", media_type: "application/pdf", data: payload.pdfBase64 },
    }];
  }
  return payload.images.map((data) => ({
    type: "image",
    source: { type: "base64", media_type: "image/jpeg", data },
  }));
}

export async function receiptQuickAddRequest(
  request: ReceiptQuickAddRequest,
  dependencies: ReceiptQuickAddDependencies,
): Promise<ReceiptEntryProposal> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in.");

  const payload = payloadFromData(request.data);
  validatePayload(payload);

  const apiKey = dependencies.apiKey;
  if (!apiKey) throw new HttpsError("failed-precondition", "Anthropic API key is not configured.");

  const now = (dependencies.now ?? (() => new Date()))();
  const reservation = await consumeReceiptQuota(dependencies.db, request.auth.uid, now);

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
        // Unsuffixed, matching both siblings. Escalation to claude-sonnet-4-6 is permitted only
        // by the pre-registered golden-eval gate (plan §7) — never by vibes.
        model: "claude-haiku-4-5",
        max_tokens: 1024,
        // No extended thinking: the API rejects thinking + forced tool_choice (verified live,
        // claudeProxy). The date line lives in the SYSTEM prompt — the documented voice lesson.
        system: SYSTEM_PROMPT + referenceDateLine(now),
        tools: [RECEIPT_ENTRY_TOOL],
        tool_choice: { type: "tool", name: RECEIPT_ENTRY_TOOL.name },
        messages: [
          ...receiptFewShotMessages(now),
          {
            role: "user",
            content: [
              ...sourceBlocks(payload),
              {
                type: "text",
                text: vehicleContextLine(request.data)
                  + "Extract this vehicle service receipt into a log entry.",
              },
            ],
          },
        ],
      }),
    });
  } catch (error) {
    logger.error("receipt-quickadd anthropic request failed", {
      message: error instanceof Error ? error.message : String(error),
    });
    await refundReceiptQuota(dependencies.db, reservation, now);
    throw new HttpsError("internal", "Claude request failed.");
  }

  if (!response.ok) {
    logger.error("receipt-quickadd anthropic request rejected", { status: response.status });
    // Anthropic did not complete billable inference on a 5xx response. Other HTTP failures
    // and all HTTP-OK model-output errors keep their quota unit (mirrors both siblings).
    if (response.status >= 500) {
      await refundReceiptQuota(dependencies.db, reservation, now);
    }
    throw new HttpsError("internal", `Claude request failed with ${response.status}.`);
  }

  let modelPayload: unknown;
  try {
    modelPayload = await response.json();
  } catch (error) {
    // Classified reason only: V8 parse errors embed source snippets of the content.
    logger.error("receipt-quickadd anthropic response body unreadable", {
      reason: error instanceof Error ? error.name : "unknown",
    });
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }

  const parsed = toolInputFromPayload(modelPayload);
  if (!parsed) {
    logger.error("receipt-quickadd anthropic response had no tool_use block");
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }

  // Typed kill-switch (G1): the model judged the document not a receipt. Quota is KEPT —
  // inference was billed. The client maps this reason to distinct retry copy.
  if (parsed.documentLooksLikeReceipt === false) {
    logger.info("receipt-quickadd document rejected as non-receipt");
    throw new HttpsError("failed-precondition", "Not a service receipt.", { reason: "not_a_receipt" });
  }

  if (!isRecognizableReceipt(parsed)) {
    logger.error("receipt-quickadd unrecognized model output");
    throw new HttpsError("internal", "unrecognized receipt response");
  }

  try {
    return sanitizeReceiptProposal(parsed, now);
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    // Receipt content and model output are never logged (receipts carry names, addresses,
    // card last-4, VINs) — and that includes JSON.parse messages, which embed a snippet of
    // the unparseable source.
    logger.error("receipt-quickadd model output unparseable", {
      reason: error instanceof Error ? error.name : "unknown",
    });
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }
}

export const receiptQuickAdd = onCall(
  { region: "us-central1", enforceAppCheck: true, secrets: [anthropicApiKey] },
  async (request): Promise<ReceiptEntryProposal> => {
    try {
      return await receiptQuickAddRequest(request, {
        apiKey: anthropicApiKey.value(),
        db: getFirestore() as unknown as QuotaFirestore,
        fetchImpl: fetch,
      });
    } catch (error) {
      logger.error("receiptQuickAdd failed", {
        uid: request.auth?.uid,
        code: error instanceof HttpsError ? error.code : "internal",
        message: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  },
);
