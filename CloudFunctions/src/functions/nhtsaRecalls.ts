import { onCall, HttpsError } from "firebase-functions/v2/https";

export const lookupRecalls = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const vin = request.data?.vin as string | undefined;
  if (!vin) {
    throw new HttpsError("invalid-argument", "VIN is required.");
  }

  const response = await fetch(
    `https://api.nhtsa.gov/recalls/recallsByVehicle?vin=${encodeURIComponent(vin)}`
  );

  if (!response.ok) {
    throw new HttpsError("internal", `NHTSA lookup failed with ${response.status}.`);
  }

  return response.json();
});
