import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

/// Self-heal for the client-side odometer race documented in EntryService.saveLive /
/// EntryService+Mutations.deleteLive: an entry write and its companion vehicle-doc patch are two
/// separate writes (an atomic batch on save, two sequential writes on delete), so a client crash,
/// dropped connection, or concurrent edit between them can leave vehicles/{vehicleId}.currentOdometer
/// stale — pointing above or below the true max of the entries that actually remain. This trigger
/// recomputes the authoritative max server-side on every write that could move it.

/** The subset of an entries/{entryId} write this trigger's cheap gate cares about. */
export interface EntryOdometerSnapshot {
  exists: boolean;
  odometerReading: unknown;
}

/**
 * Pure decision: does this entries/{entryId} write need a recompute at all? A recompute is a
 * Firestore round trip (top-1 query + vehicle read [+ write]), so this gate keeps the trigger
 * cheap by skipping every write that provably can't change the max — editing an entry's notes,
 * cost, or type leaves odometerReading untouched and is a no-op here.
 */
export function shouldRecompute(before: EntryOdometerSnapshot, after: EntryOdometerSnapshot): boolean {
  if (before.exists !== after.exists) return true; // entry created or deleted
  return before.odometerReading !== after.odometerReading; // reading changed in place
}

export interface VehicleOdometerState {
  exists: boolean;
  /** undefined when the field is missing, non-numeric, or non-finite — treated as "unknown/stale". */
  currentOdometer: number | undefined;
}

/// Each step is injected so the recompute decision (differs-from-stored, missing-vehicle
/// tolerance) is unit-tested without touching real Firestore.
export interface OdometerRecomputeDeps {
  /** Top remaining entry's odometerReading for the vehicle, or 0 when no entries remain — mirrors
   * the client's `fetchLatestOdometer(...) ?? 0` fallback in EntryService+Mutations.deleteLive. */
  readMaxRemainingOdometer(vehicleId: string): Promise<number>;
  readVehicleState(vehicleId: string): Promise<VehicleOdometerState>;
  /**
   * Returns "vehicle-missing" instead of throwing when the doc was deleted between the
   * readVehicleState call above and this write — a NOT_FOUND race with
   * deleteVehicle/deleteAccount's recursiveDelete, which N concurrent entry-delete trigger
   * firings can easily lose. MUST NOT fall back to set/merge on that race: resurrecting a
   * vehicle doc that's actively being purged stays impossible either way.
   */
  writeVehicleOdometer(vehicleId: string, odometer: number): Promise<"written" | "vehicle-missing">;
}

export type OdometerRecomputeOutcome =
  | { kind: "reconciled"; from: number | undefined; to: number }
  | { kind: "unchanged" }
  | { kind: "vehicle-missing" };

export async function reconcileVehicleOdometer(
  vehicleId: string,
  deps: OdometerRecomputeDeps,
): Promise<OdometerRecomputeOutcome> {
  const vehicle = await deps.readVehicleState(vehicleId);
  if (!vehicle.exists) {
    // The vehicle doc can legitimately be gone mid-flight: deleteVehicle claims+tombstones the
    // vehicle, then recursiveDelete purges its entries subcollection — which is exactly the write
    // this trigger fires on. Nothing to reconcile, and writing currentOdometer here would
    // resurrect a doc deleteVehicle/deleteAccount is actively purging.
    return { kind: "vehicle-missing" };
  }
  const recomputed = await deps.readMaxRemainingOdometer(vehicleId);
  // Guard (b): only write when the recomputed value actually differs from what's stored, so a
  // burst of entry writes that don't move the max (or repeated deliveries of the same event)
  // don't turn into a write storm. currentOdometer === undefined (missing/non-numeric) always
  // counts as "differs" so a corrupted field gets healed.
  if (vehicle.currentOdometer === recomputed) {
    return { kind: "unchanged" };
  }
  const writeResult = await deps.writeVehicleOdometer(vehicleId, recomputed);
  if (writeResult === "vehicle-missing") {
    // Lost the race with a concurrent purge between the read above and this write — same
    // outcome as if readVehicleState had seen it gone from the start.
    return { kind: "vehicle-missing" };
  }
  return { kind: "reconciled", from: vehicle.currentOdometer, to: recomputed };
}

function numericOrUndefined(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

/** gRPC status code 5 = NOT_FOUND — how the Admin SDK surfaces update() on a missing doc. */
function isFirestoreNotFoundError(error: unknown): boolean {
  return typeof error === "object" && error !== null && (error as { code?: unknown }).code === 5;
}

export const recomputeVehicleOdometer = onDocumentWritten(
  { document: "vehicles/{vehicleId}/entries/{entryId}", region: "us-central1", memory: "256MiB" },
  async (event) => {
    const change = event.data;
    if (!change) return; // no snapshot data on this event — nothing to react to

    const { vehicleId, entryId } = event.params;
    const before: EntryOdometerSnapshot = {
      exists: change.before.exists,
      odometerReading: change.before.exists ? change.before.get("odometerReading") : undefined,
    };
    const after: EntryOdometerSnapshot = {
      exists: change.after.exists,
      odometerReading: change.after.exists ? change.after.get("odometerReading") : undefined,
    };
    if (!shouldRecompute(before, after)) return;

    const db = getFirestore();
    try {
      const outcome = await reconcileVehicleOdometer(vehicleId, {
        async readMaxRemainingOdometer(id) {
          // vehicles/{id}/entries is a genuine Firestore SUBcollection query scoped to one
          // parent — it needs no composite index. Firestore auto-generates a single-field index
          // for every field's equality/range/orderBy use (ascending AND descending) unless the
          // field is explicitly excluded via fieldOverrides, and
          // Configuration/FirestoreIndexes.json's fieldOverrides is empty (odometerReading is not
          // excluded), so a plain `.orderBy("odometerReading", "desc").limit(1)` is auto-indexed.
          // The existing composite index in that file — {vehicleId ASC, odometerReading DESC},
          // collectionGroup "entries", queryScope COLLECTION — supports a DIFFERENT query shape
          // (one that also filters by the entry's own denormalized `vehicleId` field, e.g. a
          // collection-group-style scan); it is unrelated to and not required by this
          // single-parent query. Mirrors the client's identical query in
          // EntryService+Paging.fetchLatestOdometer.
          const snapshot = await db
            .collection("vehicles").doc(id).collection("entries")
            .orderBy("odometerReading", "desc")
            .limit(1)
            .get();
          if (snapshot.empty) return 0;
          return numericOrUndefined(snapshot.docs[0].get("odometerReading")) ?? 0;
        },
        async readVehicleState(id) {
          const doc = await db.collection("vehicles").doc(id).get();
          if (!doc.exists) return { exists: false, currentOdometer: undefined };
          return { exists: true, currentOdometer: numericOrUndefined(doc.get("currentOdometer")) };
        },
        async writeVehicleOdometer(id, odometer) {
          // update(), not set(merge:true): if the vehicle doc was deleted between the read above
          // and this write (the same purge race readVehicleState already guards against), update()
          // rejects NOT_FOUND instead of silently resurrecting a doc deleteVehicle just purged.
          // Catch exactly that race and report it as "vehicle-missing" (never fall back to
          // set/merge) so it collapses into the same handled outcome as an upfront-missing
          // vehicle, instead of surfacing as unhandled error/retry noise.
          try {
            await db.collection("vehicles").doc(id).update({
              currentOdometer: odometer,
              updatedAt: Timestamp.now(),
            });
            return "written";
          } catch (error) {
            if (isFirestoreNotFoundError(error)) return "vehicle-missing";
            throw error;
          }
        },
      });

      if (outcome.kind === "reconciled") {
        logger.info("vehicle odometer reconciled", {
          vehicleId,
          entryId,
          from: outcome.from ?? null,
          to: outcome.to,
        });
      } else if (outcome.kind === "vehicle-missing") {
        logger.info("vehicle odometer recompute skipped: vehicle missing", { vehicleId, entryId });
      }
    } catch (error) {
      logger.error("vehicle odometer recompute failed", {
        vehicleId,
        entryId,
        message: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  },
);
