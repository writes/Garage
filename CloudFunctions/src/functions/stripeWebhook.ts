import { getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";

type RevenueCatEvent = {
  app_user_id?: string;
  entitlement_ids?: string[];
  event_timestamp_ms?: number;
  id?: string;
  type?: string;
};

function isAuthorizedRequest(authorizationHeader: string | undefined, expectedValue: string | undefined): boolean {
  if (!authorizationHeader || !expectedValue || expectedValue.length === 0) {
    return false;
  }

  return authorizationHeader === expectedValue || authorizationHeader === `Bearer ${expectedValue}`;
}

export const handleRevenueCatWebhook = onRequest({ region: "us-central1" }, async (request, response) => {
  const db = getFirestore();
  const expectedAuthorization = process.env.REVENUECAT_WEBHOOK_AUTH;
  const authorizationHeader = request.header("Authorization");

  if (!isAuthorizedRequest(authorizationHeader, expectedAuthorization)) {
    response.status(401).send("Unauthorized.");
    return;
  }

  const event = request.body?.event as RevenueCatEvent | undefined;
  const appUserId = event?.app_user_id as string | undefined;
  const eventId = event?.id;

  if (!appUserId) {
    response.status(400).send("Missing RevenueCat app user id.");
    return;
  }

  if (!eventId) {
    response.status(400).send("Missing RevenueCat event id.");
    return;
  }

  const eventRef = db.collection("revenuecat_events").doc(eventId);
  const userRef = db.collection("users").doc(appUserId);
  const isActive = Boolean(event.entitlement_ids?.includes("pro"));
  const updatedAt = event.event_timestamp_ms ? new Date(event.event_timestamp_ms).toISOString() : new Date().toISOString();

  await db.runTransaction(async (transaction) => {
    const existingEvent = await transaction.get(eventRef);

    if (existingEvent.exists) {
      return;
    }

    transaction.set(eventRef, {
      appUserId,
      entitlementIds: event.entitlement_ids ?? [],
      receivedAt: new Date().toISOString(),
      type: event.type ?? null,
      updatedAt,
    });

    transaction.set(userRef, {
      subscription: {
        entitlement: "pro",
        isActive,
        updatedAt,
      },
    }, { merge: true });
  });

  response.status(200).send("ok");
});
