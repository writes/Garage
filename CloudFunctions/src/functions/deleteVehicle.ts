import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

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
  /**
   * Delete every Storage object under this vehicle's attachment prefix
   * (users/{uid}/entry-attachments/{vehicleId}/...). Safe on a prefix with no objects. May throw —
   * the orchestration below treats that as fail-soft (see the comment at the call site).
   */
  purgeStorage(uid: string, vehicleId: string): Promise<void>;
}

export interface DeleteVehicleResult {
  deleted: true;
  alreadyDeleted: boolean;
  storagePurged: boolean;
  /** Present only when storagePurged is false — the underlying error message, for structured logging. */
  storagePurgeError?: string;
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

  // Firestore subcollections and Storage objects are independent resources, so both purges start
  // together (right after the claim) instead of one blocking the other.
  const subcollectionsPurge = deps.purgeSubcollections(vehicleId);
  const storagePurge = deps.purgeStorage(uid, vehicleId).then(
    () => ({ purged: true as const, error: undefined as string | undefined }),
    (error: unknown) => ({ purged: false as const, error: error instanceof Error ? error.message : String(error) }),
  );

  // Subcollection purge is on the hard-fail path: Firestore is the source of truth for "this
  // vehicle's data is gone," so a real failure here must fail the whole call and stay retryable.
  await subcollectionsPurge;

  // Storage purge is fail-soft: by the time it could fail, the claim + Firestore purge have
  // already succeeded, so the vehicle and all its documents are truly gone — only orphaned
  // attachment files would remain. Failing the whole call here would surface an error to the user
  // for data that IS deleted, and it isn't necessary: the client's tombstone sweep and
  // deleteAccount's own deleteUserStorage both re-sweep this exact users/{uid}/entry-attachments/
  // prefix, so any objects left behind by a transient Storage error still converge to deleted on
  // the next pass. Log-and-continue, never throw.
  const storageResult = await storagePurge;

  return {
    deleted: true,
    alreadyDeleted: claim === "not-found",
    storagePurged: storageResult.purged,
    ...(storageResult.purged ? {} : { storagePurgeError: storageResult.error }),
  };
}

export const deleteVehicle = onCall(
  { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 120, memory: "256MiB" },
  async (request): Promise<DeleteVehicleResult> => {
    const db = getFirestore();
    const bucket = getStorage().bucket();
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
          async purgeStorage(ownerUid, vehicleId) {
            // Mirrors deleteAccount's deleteUserStorage (same bucket.deleteFiles-by-prefix
            // pattern), scoped to just this vehicle's attachments instead of the whole user.
            await bucket.deleteFiles({ prefix: `users/${ownerUid}/entry-attachments/${vehicleId}/` });
          },
        },
      );
      logger.info("vehicle deleted", {
        uid,
        vehicleId: vehicleIdFromData(request.data),
        alreadyDeleted: result.alreadyDeleted,
        storagePurged: result.storagePurged,
      });
      if (!result.storagePurged) {
        // Non-fatal (see the fail-soft comment in deleteVehicleRequest) but worth a signal: an
        // operator watching logs can spot a persistently-failing bucket instead of relying purely
        // on the client sweep / deleteAccount convergence to quietly clean it up later.
        logger.warn("vehicle storage purge failed; deferring to client sweep / deleteAccount convergence", {
          uid,
          vehicleId: vehicleIdFromData(request.data),
          message: result.storagePurgeError,
        });
      }
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
