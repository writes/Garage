import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldPath } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { getStorage } from "firebase-admin/storage";

export interface DeleteAccountRequest {
  auth: { uid: string } | null;
}

/// Each step is injected so the destructive orchestration (order + guards) is unit-tested without
/// touching real Firestore/Storage/Auth.
export interface DeleteAccountDeps {
  listUserVehicleIds(uid: string): Promise<string[]>;
  deleteVehicleCascade(vehicleId: string): Promise<void>;
  deleteUserDoc(uid: string): Promise<void>;
  deleteUserQuotas(uid: string): Promise<void>;
  deleteReceiptScanTokens(uid: string): Promise<void>;
  deleteRevenueCatEvents(uid: string): Promise<void>;
  eraseRevenueCatSubscriber(uid: string): Promise<void>;
  deleteUserStorage(uid: string): Promise<void>;
  deleteAuthUser(uid: string): Promise<void>;
}

/// Erases the subscriber record AT RevenueCat (the third party), not just our Firestore mirror —
/// without this, a deleted user's email + full purchase history persisted at RevenueCat forever.
/// Fail-soft when the key is unset: erasure is skipped with a logged warning rather than breaking
/// account deletion for deployments that have not provisioned the key yet. The key is read from
/// the runtime env (CloudFunctions/.env.* or Secret Manager) and trimmed because a trailing
/// newline in a pasted secret has broken auth in this repo before.
export async function eraseRevenueCatSubscriberImpl(
  uid: string,
  fetchImpl: typeof fetch,
  secretKey: string | undefined,
): Promise<void> {
  const key = (secretKey ?? "").trim();
  if (!key) {
    logger.warn("revenuecat erasure skipped: REVENUECAT_SECRET_API_KEY unset; subscriber record retained", { uid });
    return;
  }
  const response = await fetchImpl(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
    {
      method: "DELETE",
      headers: { Authorization: `Bearer ${key}` },
      signal: AbortSignal.timeout(15_000),
    },
  );
  // 404 is idempotent success: a lost response + client retry must not fail the cascade.
  if (response.ok || response.status === 404) return;
  throw new Error(`RevenueCat subscriber deletion failed with ${response.status}`);
}

export interface DeleteAccountResult {
  deleted: true;
  vehiclesDeleted: number;
}


export async function deleteAccountRequest(
  request: DeleteAccountRequest,
  deps: DeleteAccountDeps,
): Promise<DeleteAccountResult> {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in to delete your account.");
  }

  // Data FIRST, auth LAST. If any step fails the user can still sign in and retry, and we never
  // orphan Firestore/Storage data behind a deleted auth user (which nothing could then reach).
  // Per-step logging: on a mid-cascade failure the log shows exactly how far deletion got.
  let step = "listUserVehicleIds";
  try {
    const vehicleIds = await deps.listUserVehicleIds(uid);
    step = "deleteVehicleCascade";
    for (const vehicleId of vehicleIds) {
      await deps.deleteVehicleCascade(vehicleId);
    }
    step = "deleteUserDoc";
    await deps.deleteUserDoc(uid);
    step = "deleteUserQuotas";
    await deps.deleteUserQuotas(uid);
    step = "deleteReceiptScanTokens";
    await deps.deleteReceiptScanTokens(uid);
    step = "deleteRevenueCatEvents";
    await deps.deleteRevenueCatEvents(uid);
    step = "eraseRevenueCatSubscriber";
    await deps.eraseRevenueCatSubscriber(uid);
    step = "deleteUserStorage";
    await deps.deleteUserStorage(uid);
    step = "deleteAuthUser";
    await deps.deleteAuthUser(uid);

    return { deleted: true, vehiclesDeleted: vehicleIds.length };
  } catch (error) {
    logger.error("account deletion failed", {
      uid,
      step,
      message: error instanceof Error ? error.message : String(error),
    });
    throw error;
  }
}

export const deleteAccount = onCall(
  { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 300, memory: "512MiB" },
  async (request): Promise<DeleteAccountResult> => {
    const db = getFirestore();
    const auth = getAuth();
    const bucket = getStorage().bucket();
    const result = await deleteAccountRequest(
      { auth: request.auth ? { uid: request.auth.uid } : null },
      {
        async listUserVehicleIds(uid) {
          const snapshot = await db.collection("vehicles").where("userId", "==", uid).get();
          return snapshot.docs.map((docRef) => docRef.id);
        },
        async deleteVehicleCascade(vehicleId) {
          // recursiveDelete removes the vehicle doc AND all 9 subcollections (entries, gallery,
          // detailing_records, parts_inventory, wear_snapshots, tire_sets, reminders, warranties,
          // recalls) in one call.
          await db.recursiveDelete(db.collection("vehicles").doc(vehicleId));
        },
        async deleteUserDoc(uid) {
          await db.collection("users").doc(uid).delete();
        },
        async deleteUserQuotas(uid) {
          // usage_quotas doc ids are all prefixed `${uid}_` (daily `${uid}_${date}`,
          // `${uid}_lifetime`, `${uid}_voice_${date}`). Firebase uids are fixed-length, so no uid
          // is a prefix of another — this range never touches another user's rows.
          const snapshot = await db.collection("usage_quotas")
            .where(FieldPath.documentId(), ">=", `${uid}_`)
            .where(FieldPath.documentId(), "<", `${uid}_\uf8ff`)
            .get();
          await Promise.all(snapshot.docs.map((quotaDoc) => quotaDoc.ref.delete()));
        },
        async deleteReceiptScanTokens(uid) {
          const snapshot = await db.collection("receipt_scan_tokens").where("uid", "==", uid).get();
          // Firestore writes cap a batch at 500 documents. Tokens have no TTL yet, so retain
          // correctness for long-lived accounts rather than assuming their history is small.
          for (let index = 0; index < snapshot.docs.length; index += 500) {
            const batch = db.batch();
            for (const tokenDoc of snapshot.docs.slice(index, index + 500)) batch.delete(tokenDoc.ref);
            await batch.commit();
          }
        },
        async deleteRevenueCatEvents(uid) {
          const snapshot = await db.collection("revenuecat_events").where("appUserId", "==", uid).get();
          await Promise.all(snapshot.docs.map((eventDoc) => eventDoc.ref.delete()));
        },
        async eraseRevenueCatSubscriber(uid) {
          await eraseRevenueCatSubscriberImpl(uid, fetch, process.env.REVENUECAT_SECRET_API_KEY);
        },
        async deleteUserStorage(uid) {
          await bucket.deleteFiles({ prefix: `users/${uid}/` });
        },
        async deleteAuthUser(uid) {
          try {
            await auth.deleteUser(uid);
          } catch (error) {
            // Idempotent: if a prior attempt already removed the auth user (e.g. the HTTP response
            // was lost and the client retried), treat 'not found' as success.
            if ((error as { code?: string }).code !== "auth/user-not-found") throw error;
          }
        },
      },
    );
    // Irreversible operation — keep a server-side audit trail (no PII beyond the uid).
    logger.info("account deleted", { uid: request.auth?.uid, vehiclesDeleted: result.vehiclesDeleted });
    return result;
  },
);
