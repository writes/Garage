import { getFirestore } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { anthropicApiKey } from "../params";
import {
  QuotaFirestore,
  isRecord,
} from "./claudeProxy";
import {
  consumeReceiptQuota,
  refundReceiptQuota,
  voidReceiptReservation,
  type ReceiptQuotaSnapshot,
} from "./receiptQuota";
import {
  VALID_ENTRY_TYPES,
  EntryTypeValue,
  referenceDateLine,
  schemaVersionFromData,
  toolInputFromPayload,
} from "./voiceQuickAdd";
import {
  TYPED_SYSTEM_PROMPT,
  TypedDetails,
  buildTypedDetailTool,
  sanitizeTypedDetails,
  typedFieldCount,
} from "./typedExtraction";

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

export {
  FREE_LIFETIME_CONFIRMED_QUOTA,
  FREE_LIFETIME_SCAN_CEILING,
  PRO_MONTHLY_CONFIRMED_QUOTA,
  PRO_MONTHLY_SCAN_CEILING,
} from "./receiptQuota";
export type { ReceiptQuotaSnapshot } from "./receiptQuota";

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

/** Additive wire extension: the existing proposal fields remain top-level and unchanged. */
export type ReceiptQuickAddResponse = ReceiptEntryProposal & {
  token: string;
  quota: ReceiptQuotaSnapshot;
};

/** schemaVersion 2: typed detail fields join the same flat envelope, plus the version marker. */
export type ReceiptQuickAddResponseV2 = ReceiptQuickAddResponse & TypedDetails & {
  proposalSchemaVersion: 2;
};

export type ReceiptQuickAddRequest = { auth?: { uid: string } | null; data?: unknown };

export type ReceiptQuickAddDependencies = {
  apiKey?: string;
  db: QuotaFirestore;
  fetchImpl: typeof fetch;
  now?: () => Date;
};

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
 * Every clause here is evidence-backed by scripts/receiptGoldenEval.ts (18 synthetic receipts,
 * scored field-by-field, 2 runs each — reports/receipt-golden-prod.json). Iterate ONLY under the
 * eval; a drop is a regression regardless of plausibility.
 *
 * Cycle-1 clauses (the original ship set, 96.8% overall / 100% money):
 * - GRAND TOTAL vs the subtotal/tendered/change stack (the classic receipt money trap).
 * - Odometer vs the RO#/invoice#/phone/ZIP/VIN mileage-shaped numbers invoices are covered in.
 * - SERVICE date vs payment-due/statement/reprint dates.
 * - Conversion-is-recording (the voice chilling-effect lesson, pre-applied to print).
 * - Unreadable values are omitted, never guessed.
 * - Parts-only receipts suggest DIY.
 * - documentLooksLikeReceipt=false is the non-receipt escape hatch (G1).
 *
 * Cycle-2 clauses (added 2026-07-29; 96.8% -> 98.1% overall, money held at 100%):
 * - The `upgrade` fence: a battery-replacement invoice was filed as `upgrade` 2/2 — the model
 *   read "new AGM battery, install + register" as a chosen improvement rather than a dead part
 *   being replaced. Naming the failed-part case fixed it 2/2 (96.8% -> 97.2%).
 * - Classify-by-main-work: a 30,000-mile service (oil/filter + rotate + cabin filter + brake
 *   inspection) was filed as `oil_change` from its first line, which would lose the rest of the
 *   service. Naming the multi-line-package case fixed it 2/2 (97.2% -> 98.1%).
 *
 * MEASURED DEAD END — do not re-add (cycle 3, 2026-07-29): "replacing or resealing a gasket,
 * seal, or hose is a repair" fixed the valve-cover-reseal case 2/2 and raised the overall score
 * to 98.6%, but it over-fired on the transmission-fluid-service trap ("Drain/fill, new gasket +
 * filter"), flipping it maintenance -> repair and taking a deliberately engineered trap case
 * from 2/2 to 1/2. A gasket named incidentally inside a fluid service overrode the
 * classify-by-main-work rule. Trading trap coverage for a boundary case is a bad trade even at
 * net +1 field; reverted. Residual known misses at 98.1%: the valve-cover invoice reading
 * `maintenance` rather than `repair` (genuinely ambiguous — the receipt states no failure), and
 * a single-digit odometer misread on the 7-degree-skewed photo (a vision limit, not a prompt
 * one — this is the pre-registered P1 VisionKit evidence case, plan §8).
 *
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
  " upgrade is only for an aftermarket or performance modification the owner chose to add —" +
  " never for replacing a part that failed, died, or wore out. A new battery, alternator," +
  " starter, or belt is a repair even when the replacement part is newer or better than the" +
  " original." +
  " When one receipt covers several jobs, classify by the main work, not by the first line:" +
  " a multi-line scheduled mileage service (e.g. a 30,000 mile service) is maintenance, not" +
  " the type of one item inside it; work that fixes something broken, leaking, or worn out is" +
  " repair even when routine items were done in the same visit." +
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

/**
 * The v2 second call (split-call architecture — typedExtraction.ts header): the same document
 * pages, a narrow tool with only the classified entry type's fields. Fails SOFT to all-null —
 * typed details are an enhancement; a failure here must never sink an already-good proposal or
 * touch its quota/token bookkeeping.
 */
async function extractReceiptTypedDetails(args: {
  apiKey: string;
  fetchImpl: typeof fetch;
  payload: ReceiptPayload;
  vehicleLine: string;
  entryType: EntryTypeValue;
}): Promise<TypedDetails> {
  const empty = sanitizeTypedDetails({}, args.entryType);
  const tool = buildTypedDetailTool(args.entryType);
  if (!tool) return empty;
  let response: Response;
  try {
    response = await args.fetchImpl("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": args.apiKey,
        "anthropic-version": "2023-06-01",
      },
      signal: AbortSignal.timeout(40_000),
      body: JSON.stringify({
        model: "claude-haiku-4-5",
        max_tokens: 512,
        temperature: 0,
        system: TYPED_SYSTEM_PROMPT,
        tools: [tool],
        tool_choice: { type: "tool", name: tool.name },
        messages: [
          {
            role: "user",
            content: [
              ...sourceBlocks(args.payload),
              {
                type: "text",
                text: args.vehicleLine + `This receipt is a ${args.entryType} entry.`
                  + ` Extract the ${args.entryType} details it shows.`,
              },
            ],
          },
        ],
      }),
    });
  } catch (error) {
    logger.warn("receipt-quickadd typed-details request failed", {
      reason: error instanceof Error ? error.name : "unknown",
    });
    return empty;
  }
  if (!response.ok) {
    logger.warn("receipt-quickadd typed-details request rejected", { status: response.status });
    return empty;
  }
  let modelPayload: unknown;
  try {
    modelPayload = await response.json();
  } catch {
    return empty;
  }
  const parsed = toolInputFromPayload(modelPayload, tool.name);
  return parsed ? sanitizeTypedDetails(parsed, args.entryType) : empty;
}

export async function receiptQuickAddRequest(
  request: ReceiptQuickAddRequest,
  dependencies: ReceiptQuickAddDependencies,
): Promise<ReceiptQuickAddResponse | ReceiptQuickAddResponseV2> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in.");

  const payload = payloadFromData(request.data);
  validatePayload(payload);

  const apiKey = dependencies.apiKey;
  if (!apiKey) throw new HttpsError("failed-precondition", "Anthropic API key is not configured.");

  const schemaVersion = schemaVersionFromData(request.data);
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
      signal: AbortSignal.timeout(55_000),
      body: JSON.stringify({
        // Unsuffixed, matching both siblings. Escalation to claude-sonnet-4-6 is permitted only
        // by the pre-registered golden-eval gate (plan §7) — never by vibes.
        model: "claude-haiku-4-5",
        max_tokens: 1024,
        // No extended thinking: the API rejects thinking + forced tool_choice (verified live,
        // claudeProxy). The date line lives in the SYSTEM prompt — the documented voice lesson.
        // Byte-identical to v1 for BOTH schema versions (split-call architecture — see
        // typedExtraction.ts header): typed details ride a second, narrow call below.
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
      reason: error instanceof Error ? error.name : "unknown",
    });
    await refundReceiptQuota(dependencies.db, reservation, now);
    if (error instanceof Error && (error.name === "AbortError" || error.name === "TimeoutError")) {
      throw new HttpsError("deadline-exceeded", "Claude request timed out.");
    }
    throw new HttpsError("internal", "Claude request failed.");
  }

  if (!response.ok) {
    logger.error("receipt-quickadd anthropic request rejected", { status: response.status });
    // 429 and 5xx responses are not billed. A completed 4xx response keeps its scan unit but
    // has no proposal to confirm, so its reservation token is released below.
    if (response.status >= 500 || response.status === 429) {
      await refundReceiptQuota(dependencies.db, reservation, now);
    } else {
      await voidReceiptReservation(dependencies.db, reservation, now);
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
    await voidReceiptReservation(dependencies.db, reservation, now);
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }

  const parsed = toolInputFromPayload(modelPayload, RECEIPT_ENTRY_TOOL.name);
  if (!parsed) {
    logger.error("receipt-quickadd anthropic response had no tool_use block");
    await voidReceiptReservation(dependencies.db, reservation, now);
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }

  // Typed kill-switch (G1): the model judged the document not a receipt. Quota is KEPT —
  // inference was billed. The client maps this reason to distinct retry copy.
  if (parsed.documentLooksLikeReceipt === false) {
    logger.info("receipt-quickadd document rejected as non-receipt");
    await voidReceiptReservation(dependencies.db, reservation, now);
    throw new HttpsError("failed-precondition", "Not a service receipt.", { reason: "not_a_receipt" });
  }

  if (!isRecognizableReceipt(parsed)) {
    logger.error("receipt-quickadd unrecognized model output");
    await voidReceiptReservation(dependencies.db, reservation, now);
    throw new HttpsError("internal", "unrecognized receipt response");
  }

  try {
    const proposal = sanitizeReceiptProposal(parsed, now);
    const typed: TypedDetails | null = schemaVersion === 2
      ? await extractReceiptTypedDetails({
        apiKey, fetchImpl: dependencies.fetchImpl, payload,
        vehicleLine: vehicleContextLine(request.data), entryType: proposal.entryType,
      })
      : null;
    // Field PRESENCE only, never content (receipts carry names, addresses, card last-4, VINs).
    // This is the one signal that distinguishes "extraction returned nothing" from "the client
    // dropped the payload" when a tester reports an empty prefilled form.
    logger.info("receipt-quickadd proposal fields", {
      schemaVersion,
      entryType: proposal.entryType,
      hasOdometer: proposal.odometerReading !== null,
      hasCost: proposal.cost !== null,
      hasShopName: proposal.shopName !== null,
      hasEntryDate: proposal.entryDate !== null,
      hasNotes: proposal.notes !== null,
      lineItemCount: proposal.lineItems.length,
      typedFieldCount: typed === null ? 0 : typedFieldCount(typed),
    });
    const envelope = { ...proposal, token: reservation.tokenId, quota: reservation.quota };
    return typed === null ? envelope : { ...envelope, ...typed, proposalSchemaVersion: 2 };
  } catch (error) {
    await voidReceiptReservation(dependencies.db, reservation, now);
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
  { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 120, secrets: [anthropicApiKey] },
  async (request): Promise<ReceiptQuickAddResponse | ReceiptQuickAddResponseV2> => {
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
