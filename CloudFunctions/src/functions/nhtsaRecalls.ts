import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

// 17-char VIN, excluding I/O/Q (never used in real VINs). Validating before the fetch blocks
// injection into the upstream URL and cheap abuse of an unbounded proxy.
const VIN_PATTERN = /^[A-HJ-NPR-Z0-9]{17}$/;

export function normalizeVin(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const vin = raw.trim().toUpperCase();
  return VIN_PATTERN.test(vin) ? vin : null;
}

export type RecallSummary = {
  campaignNumber: string;
  component: string | null;
  summary: string | null;
  remedy: string | null;
  reportReceivedDate: string | null;
  /** NHTSA's own do-not-drive / park-outside flags — the only fields here that are safety-urgent. */
  parkIt: boolean;
  parkOutside: boolean;
};

export type RecallLookupResponse = {
  make: string;
  model: string;
  modelYear: string;
  recalls: RecallSummary[];
};

export type RecallDependencies = { fetchImpl: typeof fetch };

/**
 * THE VIN PARAMETER NEVER WORKED.
 *
 * This function previously called `recallsByVehicle?vin=...`, which NHTSA answers with **HTTP 400
 * for every VIN** — and, confusingly, a body reading `"Results returned successfully"` with zero
 * results. Because the old code threw on `!response.ok`, every lookup failed with "NHTSA lookup
 * failed with 400", 100% of the time. It had no Swift caller, so nothing ever surfaced it.
 * Verified against the live API 2026-07-28 across three unrelated VINs.
 *
 * `recallsByVehicle` supports make/model/modelYear, not VIN. So the VIN is first decoded through
 * vPIC (free, no key), then the recall query uses the shape NHTSA actually implements.
 */
const VPIC_DECODE = "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues";
const RECALLS = "https://api.nhtsa.gov/recalls/recallsByVehicle";

function text(value: unknown, max = 2_000): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim().slice(0, max) : null;
}

/** Keeps only the typed contract. Upstream JSON is untrusted and must not reach the client raw. */
export function sanitizeRecalls(payload: unknown, limit = 25): RecallSummary[] {
  if (typeof payload !== "object" || payload === null) return [];
  const results = (payload as { results?: unknown }).results;
  if (!Array.isArray(results)) return [];

  return results.slice(0, limit).flatMap((raw) => {
    if (typeof raw !== "object" || raw === null) return [];
    const record = raw as Record<string, unknown>;
    // The campaign number is the identity of a recall; a record without one cannot be acted on.
    const campaignNumber = text(record.NHTSACampaignNumber, 40);
    if (!campaignNumber) return [];
    return [{
      campaignNumber,
      component: text(record.Component, 300),
      summary: text(record.Summary),
      remedy: text(record.Remedy),
      reportReceivedDate: text(record.ReportReceivedDate, 40),
      parkIt: record.parkIt === true,
      parkOutside: record.parkOutSide === true,
    }];
  });
}

export async function lookupRecallsRequest(
  request: { auth?: { uid: string } | null; data?: unknown },
  dependencies: RecallDependencies,
): Promise<RecallLookupResponse> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const vin = normalizeVin((request.data as { vin?: unknown } | undefined)?.vin);
  if (!vin) {
    throw new HttpsError("invalid-argument", "A valid 17-character VIN is required.");
  }

  let decoded: Response;
  try {
    decoded = await dependencies.fetchImpl(`${VPIC_DECODE}/${encodeURIComponent(vin)}?format=json`);
  } catch (error) {
    logger.error("vin decode request failed", {
      message: error instanceof Error ? error.message : String(error),
    });
    throw new HttpsError("internal", "Could not reach the vehicle database.");
  }
  if (!decoded.ok) {
    throw new HttpsError("internal", `VIN decode failed with ${decoded.status}.`);
  }

  const decodedBody = (await decoded.json().catch(() => null)) as
    | { Results?: Array<Record<string, unknown>> }
    | null;
  const first = decodedBody?.Results?.[0] ?? {};
  const make = text(first.Make, 60);
  const model = text(first.Model, 60);
  const modelYear = text(first.ModelYear, 8);
  // A VIN that decodes to nothing usable is a client-correctable problem (a typo, a pre-1981 VIN),
  // not a server fault — say so rather than reporting an internal error.
  if (!make || !model || !modelYear) {
    throw new HttpsError("not-found", "That VIN could not be matched to a vehicle.");
  }

  const query = new URLSearchParams({ make, model, modelYear });
  let response: Response;
  try {
    response = await dependencies.fetchImpl(`${RECALLS}?${query.toString()}`);
  } catch (error) {
    logger.error("nhtsa recall request failed", {
      message: error instanceof Error ? error.message : String(error),
    });
    throw new HttpsError("internal", "Could not reach the recall database.");
  }
  if (!response.ok) {
    throw new HttpsError("internal", `NHTSA lookup failed with ${response.status}.`);
  }

  const body = await response.json().catch(() => null);
  return { make, model, modelYear, recalls: sanitizeRecalls(body) };
}

export const lookupRecalls = onCall(
  // enforceAppCheck matches the sibling callables (parseOilAnalysis, voiceQuickAdd); without it
  // any holder of a Firebase ID token from a scripted/non-attested client could hammer this proxy.
  { region: "us-central1", enforceAppCheck: true },
  async (request) => lookupRecallsRequest(request, { fetchImpl: fetch }),
);
