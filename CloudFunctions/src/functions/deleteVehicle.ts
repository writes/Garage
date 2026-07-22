import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore } from "firebase-admin/firestore";

export interface DeleteVehicleRequest {
  auth: { uid: string } | null;
  data?: unknown;
}

/// Each step is injected so the destructive orchestration (ownership check, counter decrement,
/// purge ordering, idempotency) is unit-tested without touching real Firestore.
export interface DeleteVehicleDeps {
  /**
   * Transactionally verify ownership, delete the vehicle document, and decrement
   * users/{uid}.vehicleCount (floored at 0, RULES-1 Mechanism A′). Returns "not-found" when the
   * document no longer exists (a retried call), "claimed" when this call deleted it. Must throw
   * permission-denied when the document exists but is owned by another uid.
   */
  claimVehicle(uid: string, vehicleId: string): Promise<"claimed" | "not-found">;
  /** Recursively delete the vehicle's subcollections (safe on an already-deleted parent doc). */
  purgeSubcollections(vehicleId: string): Promise<void>;
}

export interface DeleteVehicleResult {
  deleted: true;
  alreadyDeleted: boolean;
}

export function vehicleIdFromData(data: unknown): string | undefined {
  if (typeof data !== "object" || data === null) return undefined;
  const vehicleId = (data as Record<string, unknown>).vehicleId;
  // A slash would let the id escape vehicles/{id} into an arbitrary document path.
  if (typeof vehicleId !== "string" || vehicleId.length === 0 || vehicleId.length > 128) return undefined;
  return vehicleId.includes("/") ? undefined : vehicleId;
}

export async function deleteVehicleRequest(
  request: DeleteVehicleRequest,
  deps: DeleteVehicleDeps,
): Promise<DeleteVehicleResult> {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in to delete a vehicle.");
  }

  const vehicleId = vehicleIdFromData(request.data);
  if (!vehicleId) {
    throw new HttpsError("invalid-argument", "A vehicleId is required.");
  }

  // Claim FIRST (doc delete + counter decrement are transactional, so the decrement can never
  // happen twice), then purge subcollections. Purge also runs on the retry path so a call that
  // died mid-purge still converges to fully-deleted.
  const claim = await deps.claimVehicle(uid, vehicleId);
  await deps.purgeSubcollections(vehicleId);

  return { deleted: true, alreadyDeleted: claim === "not-found" };
}

export const deleteVehicle = onCall(
  { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 120, memory: "256MiB" },
  async (request): Promise<DeleteVehicleResult> => {
    const db = getFirestore();
    const uid = request.auth?.uid;
    try {
      const result = await deleteVehicleRequest(
        { auth: request.auth ? { uid: request.auth.uid } : null, data: request.data },
        {
          async claimVehicle(ownerUid, vehicleId) {
            const vehicleRef = db.collection("vehicles").doc(vehicleId);
            const userRef = db.collection("users").doc(ownerUid);
            return db.runTransaction(async (transaction) => {
              const vehicle = await transaction.get(vehicleRef);
              if (!vehicle.exists) return "not-found";
              if (vehicle.data()?.userId !== ownerUid) {
                throw new HttpsError("permission-denied", "You do not own this vehicle.");
              }
              const user = await transaction.get(userRef);
              const rawCount = user.data()?.vehicleCount;
              const priorCount = typeof rawCount === "number" && Number.isFinite(rawCount) ? rawCount : 0;
              transaction.delete(vehicleRef);
              transaction.set(userRef, {
                vehicleCount: Math.max(0, Math.floor(priorCount) - 1),
                lastVehicleOp: { id: vehicleId, op: "purge" },
              }, { merge: true });
              return "claimed";
            });
          },
          async purgeSubcollections(vehicleId) {
            // recursiveDelete removes any remaining subcollection documents even when the parent
            // vehicle doc is already gone (same guarantee deleteAccount relies on).
            await db.recursiveDelete(db.collection("vehicles").doc(vehicleId));
          },
        },
      );
      logger.info("vehicle deleted", {
        uid,
        vehicleId: vehicleIdFromData(request.data),
        alreadyDeleted: result.alreadyDeleted,
      });
      return result;
    } catch (error) {
      logger.error("vehicle deletion failed", {
        uid,
        vehicleId: vehicleIdFromData(request.data),
        code: error instanceof HttpsError ? error.code : "internal",
        message: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  },
);
