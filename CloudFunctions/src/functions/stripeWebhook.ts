import { getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";

export const handleRevenueCatWebhook = onRequest(async (request, response) => {
  const db = getFirestore();
  const event = request.body?.event;
  const appUserId = event?.app_user_id as string | undefined;

  if (!appUserId) {
    response.status(400).send("Missing RevenueCat app user id.");
    return;
  }

  const isActive = Boolean(event?.entitlement_ids?.includes("pro"));

  await db.collection("users").doc(appUserId).set({
    subscription: {
      entitlement: "pro",
      isActive,
      updatedAt: new Date().toISOString(),
    },
  }, { merge: true });

  response.status(200).send("ok");
});

