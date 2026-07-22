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

/** Pro-only daily quota. A non-Pro user is fenced with a typed permission error the client upsells. */
export async function consumeVoiceQuota(db: QuotaFirestore, uid: string, now: Date): Promise<{ bucketId: string }> {
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
    return { bucketId };
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

function modelTextFromPayload(payload: unknown): string | undefined {
  if (!isRecord(payload) || !Array.isArray(payload.content)) return undefined;
  const block = payload.content[0];
  return isRecord(block) && typeof block.text === "string" ? block.text : undefined;
}

const SYSTEM_PROMPT =
  "You convert a car owner's spoken sentence into a single maintenance-log entry. " +
  "Return ONLY a JSON object with these keys: entryType (one of: " + VALID_ENTRY_TYPES.join(", ") + "), " +
  "odometerReading (integer miles or null), cost (number USD or null), shopName (string or null), " +
  "isDiy (boolean or null), entryDate (ISO 8601 string or null; null means today), notes (string or null). " +
  "Choose the single best entryType; if unsure use maintenance. Never invent values that were not spoken.";

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
  await consumeVoiceQuota(dependencies.db, request.auth.uid, now);

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
        model: "claude-haiku-4-5-20251001",
        max_tokens: 512,
        system: SYSTEM_PROMPT,
        messages: [{
          role: "user",
          content: [{ type: "text", text: vehicleContextLine(request.data) + `The owner said: "${transcript}"` }],
        }],
      }),
    });
  } catch (error) {
    logger.error("voice-quickadd anthropic request failed", {
      message: error instanceof Error ? error.message : String(error),
    });
    throw new HttpsError("internal", "Claude request failed.");
  }

  if (!response.ok) {
    logger.error("voice-quickadd anthropic request rejected", { status: response.status });
    throw new HttpsError("internal", `Claude request failed with ${response.status}.`);
  }

  let payload: unknown;
  try {
    payload = await response.json();
  } catch (error) {
    logger.error("voice-quickadd anthropic response body unreadable", {
      message: error instanceof Error ? error.message : String(error),
    });
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }

  const text = modelTextFromPayload(payload);
  if (!text) {
    logger.error("voice-quickadd anthropic response had no text block");
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }

  try {
    const parsed = JSON.parse(text.replace(/```json|```/g, "").trim()) as unknown;
    return sanitizeVoiceProposal(parsed, now);
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    // The transcript and model output are never logged (spoken content is user PII).
    logger.error("voice-quickadd model output unparseable", {
      message: error instanceof Error ? error.message : String(error),
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
