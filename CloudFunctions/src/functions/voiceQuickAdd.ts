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

/**
 * Voice quick-add is a Pro feature (the flagship AI hook, per the 2026-07-21 Law-1 vote). It turns
 * a spoken sentence into a *prefill proposal* for the entry form — it never writes an entry itself;
 * the user confirms/edits in the form (Trust Pledge). Model output is untrusted and sanitized to a
 * fixed contract before it leaves this function.
 */

export const DAILY_VOICE_QUICKADD_QUOTA = 30;
export const MAX_TRANSCRIPT_CHARS = 2_000;

export const VALID_ENTRY_TYPES = [
  "oil_change", "oil_consumption", "oil_analysis", "fuel", "tire", "brake",
  "alignment", "maintenance", "repair", "track_day", "upgrade", "dme_report",
] as const;
export type EntryTypeValue = typeof VALID_ENTRY_TYPES[number];

export type VoiceEntryProposal = {
  entryType: EntryTypeValue;
  odometerReading: number | null;
  cost: number | null;
  shopName: string | null;
  isDiy: boolean | null;
  entryDate: string | null;
  notes: string | null;
};

export type VoiceQuickAddRequest = { auth?: { uid: string } | null; data?: unknown };

export type VoiceQuickAddDependencies = {
  apiKey?: string;
  db: QuotaFirestore;
  fetchImpl: typeof fetch;
  now?: () => Date;
};

export type VoiceQuotaReservation = { bucketId: string; uid: string };

/** Pro-only daily quota. A non-Pro user is fenced with a typed permission error the client upsells. */
export async function consumeVoiceQuota(db: QuotaFirestore, uid: string, now: Date): Promise<VoiceQuotaReservation> {
  const userRef = db.collection("users").doc(uid);
  return db.runTransaction(async (transaction) => {
    const user = await transaction.get(userRef);
    if (!userHasActiveProEntitlement(user.data(), now)) {
      throw new HttpsError("permission-denied", "Voice quick-add is a Pro feature.", { reason: "pro_required" });
    }
    const bucketId = `${uid}_voice_${now.toISOString().slice(0, 10)}`;
    const quotaRef = db.collection("usage_quotas").doc(bucketId);
    const current = await transaction.get(quotaRef);
    const count = current.exists ? safeQuotaCount(current.data()?.count) : 0;
    if (count >= DAILY_VOICE_QUICKADD_QUOTA) {
      throw new HttpsError("resource-exhausted", "Daily voice quota exceeded.", {
        reason: "voice_daily_exhausted",
        resetAt: nextUtcMidnight(now),
      });
    }
    transaction.set(quotaRef, {
      uid, kind: "voice_quickadd", count: count + 1, updatedAt: now.toISOString(),
    }, { merge: true });
    return { bucketId, uid };
  });
}

/**
 * Returns a previously consumed quota unit only after a genuine upstream infrastructure
 * failure. Mirrors refundOilAnalysisQuota's policy (claudeProxy.ts): a completed model
 * response consumes upstream cost, even when its output is malformed or unrecognized.
 */
export async function refundVoiceQuota(
  db: QuotaFirestore,
  reservation: VoiceQuotaReservation,
  now: Date,
): Promise<void> {
  const quotaRef = db.collection("usage_quotas").doc(reservation.bucketId);

  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(quotaRef);
    const count = current.exists ? safeQuotaCount(current.data()?.count) : 0;

    transaction.set(quotaRef, {
      uid: reservation.uid,
      kind: "voice_quickadd",
      count: Math.max(0, count - 1),
      updatedAt: now.toISOString(),
    }, { merge: true });
  });
}

function clampString(value: unknown, maxLength: number): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim().slice(0, maxLength) : null;
}

function clampNumber(value: unknown, minimum: number, maximum: number): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value >= minimum && value <= maximum ? value : null;
}

function clampEntryDate(value: unknown, now: Date): string | null {
  if (typeof value !== "string") return null;
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) return null;
  // A future entry date beyond tomorrow is implausible for a maintenance log; drop it.
  return parsed <= now.getTime() + 36 * 60 * 60 * 1000 ? new Date(parsed).toISOString() : null;
}

/** Keeps only the typed VoiceEntryProposal contract from untrusted model output. */
export function sanitizeVoiceProposal(value: unknown, now: Date): VoiceEntryProposal {
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
  };
}

function transcriptFromData(data: unknown): string | undefined {
  return isRecord(data) && typeof data.transcript === "string" && data.transcript.trim().length > 0
    ? data.transcript
    : undefined;
}

function vehicleContextLine(data: unknown): string {
  if (!isRecord(data) || !isRecord(data.vehicle)) return "";
  const v = data.vehicle;
  const parts = [v.year, v.make, v.model].filter((p) => typeof p === "string" || typeof p === "number");
  const odo = typeof v.currentOdometer === "number" ? `, current odometer ${v.currentOdometer}` : "";
  return parts.length ? `The vehicle is a ${parts.join(" ")}${odo}. ` : "";
}

/**
 * Picks the tool input from a forced-tool-use response, preferring the block that carries the most
 * populated fields. See claudeProxy for why: a response can hold several tool_use blocks and the
 * first is sometimes a partial draft, so reading `content[0]` silently discards most of what the
 * model heard.
 */
export function toolInputFromPayload(payload: unknown): Record<string, unknown> | undefined {
  if (!isRecord(payload) || !Array.isArray(payload.content)) return undefined;

  let best: Record<string, unknown> | undefined;
  let bestCount = -1;
  for (const block of payload.content) {
    if (!isRecord(block) || block.type !== "tool_use" || !isRecord(block.input)) continue;
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

/**
 * `entryType` is an ENUM in the schema, not a free string. That is the whole point of moving this
 * call to strict tool use: the model previously returned prose-wrapped JSON that was regex-stripped
 * and parsed, and an out-of-vocabulary entry type silently became "maintenance" — so a spoken brake
 * job could be filed as generic maintenance with no signal that anything went wrong. The API now
 * rejects any value outside this list before we ever see it.
 */
export const VOICE_ENTRY_TOOL = {
  name: "record_entry",
  description: "Record the maintenance-log entry described by the owner.",
  input_schema: {
    type: "object",
    properties: {
      entryType: {
        type: "string",
        enum: VALID_ENTRY_TYPES,
        description: "The single best entry type for what was spoken. Use maintenance if unsure.",
      },
      odometerReading: {
        type: "number",
        description: "Odometer in miles, if spoken. Spoken words become digits: 'ninety thousand' is 90000.",
      },
      cost: { type: "number", description: "Cost in USD, if spoken. 'twelve hundred bucks' is 1200." },
      shopName: { type: "string", description: "Shop or garage name if one is named anywhere in the sentence." },
      isDiy: { type: "boolean", description: "True if the owner said they did the work themselves." },
      entryDate: { type: "string", description: "ISO 8601 date. Omit for today." },
      notes: { type: "string", description: "Anything spoken that the other fields do not capture." },
    },
    required: ["entryType"],
    additionalProperties: false,
  },
  strict: true,
} as const;

/**
 * Every clause here is evidence-backed by scripts/voiceGoldenEval.ts (18 dictations, scored
 * field-by-field, 3 runs each — reports/voice-golden-*.json):
 *
 * - The original one-line prompt ("record only what was said — never invent") scored 77.4%:
 *   its chilling effect made the model treat word-to-digit CONVERSION as invention, so
 *   "four eighty seven total" and "had 88,450 on it" came back null, deterministically.
 *   Reframing conversion-as-recording plus the worked example below fixed exactly that.
 * - Without a reference date the model HALLUCINATED years: "July tenth" became 2024-07-10,
 *   "last Saturday" a Saturday from 2024 — past dates the sanitizer accepts. The date line
 *   must be in the SYSTEM prompt: prepended to the user message it fixed dates but collapsed
 *   every other field (the model stopped trusting the quoted sentence).
 * - The weekday anchors exist because Haiku cannot reliably count weekdays backwards
 *   ("last Saturday" resolved to a Sunday, 3/3) — the anchors hand it the answer.
 * - The dme_report fence stops "inspection … passed" from misfiling as a diagnostics report.
 *
 * Baseline 77.4% -> this configuration 97.8% (Haiku; residue is sporadic cost omission).
 * Sonnet 5 on the same set scored 85.5% WITHOUT the few-shot — the example, not the model
 * tier, is what carries the accuracy, so the cheap model stays.
 */
export const SYSTEM_PROMPT =
  "You convert a car owner's spoken sentence into a single maintenance-log entry." +
  " Never fabricate a value the owner did not speak — but converting spoken words to digits is" +
  " recording, not inventing. Capture every number the owner said into its matching field:" +
  " 'one forty' is 140, 'one twenty nine ninety nine' is 129.99, 'about forty bucks' is 40," +
  " 'eighty seven five' on an odometer is 87500, 'had 88,450 on it' means the odometer read" +
  " 88450. Omit a field only when the owner said nothing about it." +
  " dme_report is only for engine-computer (DME/ECU) diagnostic report exports.";

const DAY_MS = 86_400_000;

function utcDay(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function utcWeekday(date: Date): string {
  return date.toLocaleDateString("en-US", { weekday: "long", timeZone: "UTC" });
}

/** See the SYSTEM_PROMPT note: anchors, not arithmetic, are what make relative dates land. */
export function referenceDateLine(now: Date): string {
  const anchors = [-1, -2, -3, -4, -5, -6, -7]
    .map((offset) => {
      const d = new Date(now.getTime() + offset * DAY_MS);
      return `${utcWeekday(d)} was ${utcDay(d)}`;
    })
    .join(", ");
  return ` Today is ${utcWeekday(now)} ${utcDay(now)}. Going back: ${anchors}.`;
}

/**
 * One worked exchange, packing the forms instructions alone could not unlock on Haiku:
 * compressed cost with an "about" hedge, "had … on it" odometer phrasing, a shop, and a
 * relative date. The example's date is COMPUTED from `now` ("last Wednesday", matching its
 * transcript) — a hardcoded date would drift stale and teach the model to emit old years.
 */
export function fewShotMessages(now: Date): unknown[] {
  const daysSinceWednesday = ((new Date(now).getUTCDay() - 3) + 7) % 7 || 7;
  const lastWednesday = utcDay(new Date(now.getTime() - daysSinceWednesday * DAY_MS));
  return [
    {
      role: "user",
      content: [{
        type: "text",
        text: "The owner said: \"Timing belt and water pump at Pep Boys, about six fifty total," +
          " truck had one oh five two fifty on it, last Wednesday\"",
      }],
    },
    {
      role: "assistant",
      content: [{
        type: "tool_use",
        id: "toolu_voice_example_01",
        name: "record_entry",
        input: {
          entryType: "repair",
          odometerReading: 105250,
          cost: 650,
          shopName: "Pep Boys",
          entryDate: lastWednesday,
          notes: "Timing belt and water pump",
        },
      }],
    },
    {
      role: "user",
      content: [{ type: "tool_result", tool_use_id: "toolu_voice_example_01", content: "Recorded." }],
    },
  ];
}

export async function voiceQuickAddRequest(
  request: VoiceQuickAddRequest,
  dependencies: VoiceQuickAddDependencies,
): Promise<VoiceEntryProposal> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in.");

  const transcript = transcriptFromData(request.data);
  if (!transcript) throw new HttpsError("invalid-argument", "A transcript is required.");
  if (transcript.length > MAX_TRANSCRIPT_CHARS) {
    throw new HttpsError("invalid-argument", "Transcript is too long.");
  }

  const apiKey = dependencies.apiKey;
  if (!apiKey) throw new HttpsError("failed-precondition", "Anthropic API key is not configured.");

  const now = (dependencies.now ?? (() => new Date()))();
  const reservation = await consumeVoiceQuota(dependencies.db, request.auth.uid, now);

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
        // Unsuffixed, matching claudeProxy. The pinned-date form was the same model reached by a
        // different name, and two conventions for one model invites them drifting apart.
        model: "claude-haiku-4-5",
        max_tokens: 512,
        system: SYSTEM_PROMPT + referenceDateLine(now),
        tools: [VOICE_ENTRY_TOOL],
        tool_choice: { type: "tool", name: VOICE_ENTRY_TOOL.name },
        messages: [
          ...fewShotMessages(now),
          {
            role: "user",
            content: [{ type: "text", text: vehicleContextLine(request.data) + `The owner said: "${transcript}"` }],
          },
        ],
      }),
    });
  } catch (error) {
    logger.error("voice-quickadd anthropic request failed", {
      message: error instanceof Error ? error.message : String(error),
    });
    await refundVoiceQuota(dependencies.db, reservation, now);
    throw new HttpsError("internal", "Claude request failed.");
  }

  if (!response.ok) {
    logger.error("voice-quickadd anthropic request rejected", { status: response.status });
    // Anthropic did not complete billable inference on a 5xx response. Other HTTP failures
    // and all HTTP-OK model-output errors keep their quota unit (mirrors claudeProxy).
    if (response.status >= 500) {
      await refundVoiceQuota(dependencies.db, reservation, now);
    }
    throw new HttpsError("internal", `Claude request failed with ${response.status}.`);
  }

  let payload: unknown;
  try {
    payload = await response.json();
  } catch (error) {
    // Classified reason only: V8 parse errors embed source snippets of the content.
    logger.error("voice-quickadd anthropic response body unreadable", {
      reason: error instanceof Error ? error.name : "unknown",
    });
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }

  const parsed = toolInputFromPayload(payload);
  if (!parsed) {
    logger.error("voice-quickadd anthropic response had no tool_use block");
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }

  try {
    return sanitizeVoiceProposal(parsed, now);
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    // The transcript and model output are never logged (spoken content is user PII) — and
    // that includes JSON.parse messages, which embed a snippet of the unparseable source.
    logger.error("voice-quickadd model output unparseable", {
      reason: error instanceof Error ? error.name : "unknown",
    });
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }
}

export const voiceQuickAdd = onCall(
  { region: "us-central1", enforceAppCheck: true, secrets: [anthropicApiKey] },
  async (request): Promise<VoiceEntryProposal> => {
    try {
      return await voiceQuickAddRequest(request, {
        apiKey: anthropicApiKey.value(),
        db: getFirestore() as unknown as QuotaFirestore,
        fetchImpl: fetch,
      });
    } catch (error) {
      logger.error("voiceQuickAdd failed", {
        uid: request.auth?.uid,
        code: error instanceof HttpsError ? error.code : "internal",
        message: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  },
);
