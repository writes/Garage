import { onCall, HttpsError } from "firebase-functions/v2/https";

// 17-char VIN, excluding I/O/Q (never used in real VINs). Validating before the fetch blocks
// injection into the upstream URL and cheap abuse of an unbounded proxy.
const VIN_PATTERN = /^[A-HJ-NPR-Z0-9]{17}$/;

export function normalizeVin(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const vin = raw.trim().toUpperCase();
  return VIN_PATTERN.test(vin) ? vin : null;
}

export const lookupRecalls = onCall(
  // enforceAppCheck matches the sibling callables (parseOilAnalysis, voiceQuickAdd); without it
  // any holder of a Firebase ID token from a scripted/non-attested client could hammer this proxy.
  { region: "us-central1", enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const vin = normalizeVin(request.data?.vin);
    if (!vin) {
      throw new HttpsError("invalid-argument", "A valid 17-character VIN is required.");
    }

    const response = await fetch(
      `https://api.nhtsa.gov/recalls/recallsByVehicle?vin=${encodeURIComponent(vin)}`,
    );

    if (!response.ok) {
      throw new HttpsError("internal", `NHTSA lookup failed with ${response.status}.`);
    }

    return response.json();
  },
);
