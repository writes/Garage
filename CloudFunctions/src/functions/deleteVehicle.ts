import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

export interface DeleteVehicleRequest {
  auth: { uid: string } | null;
  data?: unknown;
}

/// Each step is injected so the destructive orchestration (ownership check, counter decrement,
/// purge ordering, idempotency) is unit-tested without touching real Firestore.
export interface DeleteVehicleDeps {
  /**
   * Transactionally verify ownership, mark the vehicle purging (server tombstone), and decrement
   * users/{uid}.vehicleCount exactly once (floored at 0, RULES-1 Mechanism A′). The vehicle DOC
   * MUST SURVIVE this step: it is the only key that lets a retry, the client sweep, and
   * deleteAccount's vehicle query find still-unpurged subcollections. Returns "claimed" on the
   * first call, "already-claimed" when a prior call already decremented (purge retry), and
   * "not-found" when the document is fully gone. Must throw permission-denied when the document
   * exists but is owned by another uid.
   */
  claimVehicle(uid: string, vehicleId: string): Promise<"claimed" | "already-claimed" | "not-found">;
  /** Recursively delete the vehicle doc AND its subcollections (safe on an already-deleted doc). */
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

  // Claim FIRST (tombstone + one-time counter decrement, transactional), then purge. Because the
  // claim leaves the vehicle doc in place, a purge that dies midway keeps the doc discoverable —
  // by a retried call (claim returns "already-claimed", no double decrement), by the client's
  // tombstone sweep, and by deleteAccount's userId query — so orphaned subcollections always
  // converge to deleted. Only a fully successful purge removes the doc itself.
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
              // A client CAN write purgeState on its own doc, but that only skips the decrement
              // of its own counter (self-inflicted); the security-relevant ownership and counter
              // invariants are unaffected.
              if (vehicle.data()?.purgeState === "purging") return "already-claimed";
              const user = await transaction.get(userRef);
              const rawCount = user.data()?.vehicleCount;
              const priorCount = typeof rawCount === "number" && Number.isFinite(rawCount) ? rawCount : 0;
              // Timestamp, not an ISO string: the iOS client decodes deletedAt as a Date and a
              // string would fail the whole vehicle decode.
              transaction.set(vehicleRef, {
                deletedAt: Timestamp.now(),
                purgeState: "purging",
              }, { merge: true });
              transaction.set(userRef, {
                vehicleCount: Math.max(0, Math.floor(priorCount) - 1),
                lastVehicleOp: { id: vehicleId, op: "purge" },
              }, { merge: true });
              return "claimed";
            });
          },
          async purgeSubcollections(vehicleId) {
            // recursiveDelete removes the vehicle doc and all subcollection documents; it also
            // cleans orphaned subcollections when the parent doc is already gone.
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
