import { describe, expect, it } from "vitest";
import {
  reconcileVehicleOdometer,
  shouldRecompute,
  type EntryOdometerSnapshot,
  type OdometerRecomputeDeps,
  type VehicleOdometerState,
} from "../src/functions/recomputeVehicleOdometer";

function entry(exists: boolean, odometerReading?: unknown): EntryOdometerSnapshot {
  return { exists, odometerReading };
}

describe("shouldRecompute", () => {
  it("recomputes when an entry is created", () => {
    expect(shouldRecompute(entry(false), entry(true, 100))).toBe(true);
  });

  it("recomputes when an entry is deleted", () => {
    expect(shouldRecompute(entry(true, 100), entry(false))).toBe(true);
  });

  it("recomputes when odometerReading changes on an in-place update", () => {
    expect(shouldRecompute(entry(true, 100), entry(true, 150))).toBe(true);
  });

  it("skips when odometerReading is unchanged (e.g. only notes/cost edited)", () => {
    expect(shouldRecompute(entry(true, 100), entry(true, 100))).toBe(false);
  });

  it("skips a no-op write where nothing exists on either side (defensive)", () => {
    expect(shouldRecompute(entry(false), entry(false))).toBe(false);
  });
});

function spyDeps(options: {
  maxRemaining: number;
  vehicle: VehicleOdometerState;
  failOn?: keyof OdometerRecomputeDeps;
  writeOutcome?: "written" | "vehicle-missing";
}) {
  const calls: string[] = [];
  const deps: OdometerRecomputeDeps = {
    async readMaxRemainingOdometer(vehicleId) {
      calls.push(`readMax:${vehicleId}`);
      if (options.failOn === "readMaxRemainingOdometer") throw new Error("boom:readMax");
      return options.maxRemaining;
    },
    async readVehicleState(vehicleId) {
      calls.push(`readVehicle:${vehicleId}`);
      if (options.failOn === "readVehicleState") throw new Error("boom:readVehicle");
      return options.vehicle;
    },
    async writeVehicleOdometer(vehicleId, odometer) {
      calls.push(`write:${vehicleId}:${odometer}`);
      if (options.failOn === "writeVehicleOdometer") throw new Error("boom:write");
      return options.writeOutcome ?? "written";
    },
  };
  return { calls, deps };
}

describe("reconcileVehicleOdometer", () => {
  it("writes the recomputed max when it differs from the stored value", async () => {
    const { calls, deps } = spyDeps({
      maxRemaining: 42000,
      vehicle: { exists: true, currentOdometer: 41000 },
    });
    const outcome = await reconcileVehicleOdometer("v1", deps);
    expect(calls).toEqual(["readVehicle:v1", "readMax:v1", "write:v1:42000"]);
    expect(outcome).toEqual({ kind: "reconciled", from: 41000, to: 42000 });
  });

  it("does not write when the recomputed value matches what's stored", async () => {
    const { calls, deps } = spyDeps({
      maxRemaining: 41000,
      vehicle: { exists: true, currentOdometer: 41000 },
    });
    const outcome = await reconcileVehicleOdometer("v1", deps);
    expect(calls).toEqual(["readVehicle:v1", "readMax:v1"]);
    expect(outcome).toEqual({ kind: "unchanged" });
  });

  it("recomputes to 0 when the last entry was deleted and no entries remain", async () => {
    const { calls, deps } = spyDeps({
      maxRemaining: 0,
      vehicle: { exists: true, currentOdometer: 41000 },
    });
    const outcome = await reconcileVehicleOdometer("v1", deps);
    expect(calls).toEqual(["readVehicle:v1", "readMax:v1", "write:v1:0"]);
    expect(outcome).toEqual({ kind: "reconciled", from: 41000, to: 0 });
  });

  it("heals a missing/non-numeric stored value instead of treating it as already-correct", async () => {
    const { calls, deps } = spyDeps({
      maxRemaining: 12000,
      vehicle: { exists: true, currentOdometer: undefined },
    });
    const outcome = await reconcileVehicleOdometer("v1", deps);
    expect(calls).toEqual(["readVehicle:v1", "readMax:v1", "write:v1:12000"]);
    expect(outcome).toEqual({ kind: "reconciled", from: undefined, to: 12000 });
  });

  it("tolerates a vehicle doc purged mid-flight without reading the entries or writing anything", async () => {
    const { calls, deps } = spyDeps({
      maxRemaining: 12000,
      vehicle: { exists: false, currentOdometer: undefined },
    });
    const outcome = await reconcileVehicleOdometer("v1", deps);
    expect(calls).toEqual(["readVehicle:v1"]);
    expect(outcome).toEqual({ kind: "vehicle-missing" });
  });

  it("racing delete: a write that loses the race reports vehicle-missing instead of throwing", async () => {
    // N concurrent entry-delete trigger firings can each try to write after the vehicle doc is
    // gone (deleteVehicle/deleteAccount's recursiveDelete raced ahead between the read and the
    // write). The concrete impl turns that NOT_FOUND into "vehicle-missing"; this asserts the
    // orchestration folds it into the same handled outcome rather than propagating an error.
    const { calls, deps } = spyDeps({
      maxRemaining: 42000,
      vehicle: { exists: true, currentOdometer: 41000 },
      writeOutcome: "vehicle-missing",
    });
    const outcome = await reconcileVehicleOdometer("v1", deps);
    expect(calls).toEqual(["readVehicle:v1", "readMax:v1", "write:v1:42000"]);
    expect(outcome).toEqual({ kind: "vehicle-missing" });
  });

  it("propagates a read failure without writing", async () => {
    const { calls, deps } = spyDeps({
      maxRemaining: 42000,
      vehicle: { exists: true, currentOdometer: 41000 },
      failOn: "readMaxRemainingOdometer",
    });
    await expect(reconcileVehicleOdometer("v1", deps)).rejects.toThrow("boom:readMax");
    expect(calls).toEqual(["readVehicle:v1", "readMax:v1"]);
  });
});
