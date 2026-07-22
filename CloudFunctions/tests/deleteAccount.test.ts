import { describe, expect, it } from "vitest";
import { deleteAccountRequest, type DeleteAccountDeps } from "../src/functions/deleteAccount";

function spyDeps(vehicleIds: string[], failOn?: keyof DeleteAccountDeps) {
  const calls: string[] = [];
  const guard = (name: keyof DeleteAccountDeps) => {
    if (failOn === name) throw new Error(`boom:${name}`);
  };
  const deps: DeleteAccountDeps = {
    async listUserVehicleIds() { calls.push("list"); guard("listUserVehicleIds"); return vehicleIds; },
    async deleteVehicleCascade(id) { calls.push(`vehicle:${id}`); guard("deleteVehicleCascade"); },
    async deleteUserDoc() { calls.push("userDoc"); guard("deleteUserDoc"); },
    async deleteUserQuotas() { calls.push("quotas"); guard("deleteUserQuotas"); },
    async deleteRevenueCatEvents() { calls.push("rcEvents"); guard("deleteRevenueCatEvents"); },
    async deleteUserStorage() { calls.push("storage"); guard("deleteUserStorage"); },
    async deleteAuthUser() { calls.push("auth"); guard("deleteAuthUser"); },
  };
  return { calls, deps };
}

describe("deleteAccountRequest", () => {
  it("rejects an unauthenticated caller before touching any data", async () => {
    const { calls, deps } = spyDeps(["v1"]);
    await expect(deleteAccountRequest({ auth: null }, deps)).rejects.toMatchObject({ code: "unauthenticated" });
    expect(calls).toEqual([]);
  });

  it("cascades all vehicles then user doc then storage, deleting auth LAST", async () => {
    const { calls, deps } = spyDeps(["v1", "v2"]);
    const result = await deleteAccountRequest({ auth: { uid: "owner-1" } }, deps);
    expect(calls).toEqual([
      "list", "vehicle:v1", "vehicle:v2", "userDoc", "quotas", "rcEvents", "storage", "auth",
    ]);
    expect(calls[calls.length - 1]).toBe("auth");
    expect(result).toEqual({ deleted: true, vehiclesDeleted: 2 });
  });

  it("handles a user with no vehicles", async () => {
    const { calls, deps } = spyDeps([]);
    const result = await deleteAccountRequest({ auth: { uid: "owner-1" } }, deps);
    expect(calls).toEqual(["list", "userDoc", "quotas", "rcEvents", "storage", "auth"]);
    expect(result.vehiclesDeleted).toBe(0);
  });

  it("does NOT delete the auth user if a prior data step fails (retry stays possible)", async () => {
    const { calls, deps } = spyDeps(["v1"], "deleteVehicleCascade");
    await expect(deleteAccountRequest({ auth: { uid: "owner-1" } }, deps)).rejects.toThrow("boom:deleteVehicleCascade");
    expect(calls).not.toContain("auth");
  });
});
