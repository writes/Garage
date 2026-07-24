import { describe, expect, it } from "vitest";
import {
  deleteVehicleRequest,
  vehicleIdFromData,
  type DeleteVehicleDeps,
} from "../src/functions/deleteVehicle";

function spyDeps(
  claimResult: "claimed" | "already-claimed" | "not-found" = "claimed",
  failOn?: keyof DeleteVehicleDeps,
) {
  const calls: string[] = [];
  const deps: DeleteVehicleDeps = {
    async claimVehicle(uid, vehicleId) {
      calls.push(`claim:${uid}:${vehicleId}`);
      if (failOn === "claimVehicle") throw new Error("boom:claimVehicle");
      return claimResult;
    },
    async purgeSubcollections(vehicleId) {
      calls.push(`purge:${vehicleId}`);
      if (failOn === "purgeSubcollections") throw new Error("boom:purgeSubcollections");
    },
    async purgeStorage(uid, vehicleId) {
      calls.push(`storage:${uid}:${vehicleId}`);
      if (failOn === "purgeStorage") throw new Error("boom:purgeStorage");
    },
  };
  return { calls, deps };
}

describe("vehicleIdFromData", () => {
  it("accepts a plain document id and rejects everything else", () => {
    expect(vehicleIdFromData({ vehicleId: "v1" })).toBe("v1");
    expect(vehicleIdFromData(undefined)).toBeUndefined();
    expect(vehicleIdFromData({})).toBeUndefined();
    expect(vehicleIdFromData({ vehicleId: "" })).toBeUndefined();
    expect(vehicleIdFromData({ vehicleId: 42 })).toBeUndefined();
    expect(vehicleIdFromData({ vehicleId: "a".repeat(129) })).toBeUndefined();
    // A slash would escape vehicles/{id} into an arbitrary document path.
    expect(vehicleIdFromData({ vehicleId: "v1/entries/e1" })).toBeUndefined();
  });
});

describe("deleteVehicleRequest", () => {
  it("rejects an unauthenticated caller before touching any data", async () => {
    const { calls, deps } = spyDeps();
    await expect(deleteVehicleRequest({ auth: null, data: { vehicleId: "v1" } }, deps))
      .rejects.toMatchObject({ code: "unauthenticated" });
    expect(calls).toEqual([]);
  });

  it("rejects a missing or malformed vehicleId before touching any data", async () => {
    const { calls, deps } = spyDeps();
    await expect(deleteVehicleRequest({ auth: { uid: "owner-1" }, data: {} }, deps))
      .rejects.toMatchObject({ code: "invalid-argument" });
    await expect(deleteVehicleRequest({ auth: { uid: "owner-1" }, data: { vehicleId: "a/b" } }, deps))
      .rejects.toMatchObject({ code: "invalid-argument" });
    expect(calls).toEqual([]);
  });

  it("claims first (transactional decrement), then purges subcollections and storage together", async () => {
    const { calls, deps } = spyDeps("claimed");
    const result = await deleteVehicleRequest({ auth: { uid: "owner-1" }, data: { vehicleId: "v1" } }, deps);
    expect(calls).toEqual(["claim:owner-1:v1", "purge:v1", "storage:owner-1:v1"]);
    expect(result).toEqual({ deleted: true, alreadyDeleted: false, storagePurged: true });
  });

  it("still purges subcollections and storage on a retried call whose doc is already gone", async () => {
    const { calls, deps } = spyDeps("not-found");
    const result = await deleteVehicleRequest({ auth: { uid: "owner-1" }, data: { vehicleId: "v1" } }, deps);
    expect(calls).toEqual(["claim:owner-1:v1", "purge:v1", "storage:owner-1:v1"]);
    expect(result).toEqual({ deleted: true, alreadyDeleted: true, storagePurged: true });
  });

  it("re-purges an already-claimed vehicle without reporting it deleted twice", async () => {
    // A mid-purge failure leaves the tombstoned doc in place; the retry must purge again but
    // must NOT be treated as "already deleted" (the data is still there).
    const { calls, deps } = spyDeps("already-claimed");
    const result = await deleteVehicleRequest({ auth: { uid: "owner-1" }, data: { vehicleId: "v1" } }, deps);
    expect(calls).toEqual(["claim:owner-1:v1", "purge:v1", "storage:owner-1:v1"]);
    expect(result).toEqual({ deleted: true, alreadyDeleted: false, storagePurged: true });
  });

  it("propagates a claim failure without purging subcollections or storage", async () => {
    const { calls, deps } = spyDeps("claimed", "claimVehicle");
    await expect(deleteVehicleRequest({ auth: { uid: "owner-1" }, data: { vehicleId: "v1" } }, deps))
      .rejects.toThrow("boom:claimVehicle");
    expect(calls).toEqual(["claim:owner-1:v1"]);
  });

  it("propagates a subcollection purge failure (Firestore is the source of truth for deletion)", async () => {
    const { calls, deps } = spyDeps("claimed", "purgeSubcollections");
    await expect(deleteVehicleRequest({ auth: { uid: "owner-1" }, data: { vehicleId: "v1" } }, deps))
      .rejects.toThrow("boom:purgeSubcollections");
    // Storage purge was kicked off alongside the (failing) subcollection purge, not gated behind it.
    expect(calls).toEqual(["claim:owner-1:v1", "purge:v1", "storage:owner-1:v1"]);
  });

  it("does NOT fail the call when storage purge fails, and reports it for logging", async () => {
    // Fail-soft: by the time storage could fail, the claim + Firestore purge already succeeded,
    // so the vehicle's data is truly gone — only orphaned attachment files remain, and those
    // converge via the client sweep / deleteAccount's own storage purge.
    const { calls, deps } = spyDeps("claimed", "purgeStorage");
    const result = await deleteVehicleRequest({ auth: { uid: "owner-1" }, data: { vehicleId: "v1" } }, deps);
    expect(calls).toEqual(["claim:owner-1:v1", "purge:v1", "storage:owner-1:v1"]);
    expect(result).toEqual({
      deleted: true,
      alreadyDeleted: false,
      storagePurged: false,
      storagePurgeError: "boom:purgeStorage",
    });
  });
});
