import { describe, expect, it } from "vitest";
import { FieldValue } from "firebase-admin/firestore";
import {
  deleteAccountRequest,
  eraseRevenueCatSubscriberImpl,
  receiptCreditTransactionAnonymizationFields,
  type DeleteAccountDeps,
} from "../src/functions/deleteAccount";

function spyDeps(vehicleIds: string[], failOn?: keyof DeleteAccountDeps) {
  const calls: string[] = [];
  const guard = (name: keyof DeleteAccountDeps) => {
    if (failOn === name) throw new Error(`boom:${name}`);
  };
  const deps: DeleteAccountDeps = {
    async writeDeletionTombstone() { calls.push("tombstone"); guard("writeDeletionTombstone"); },
    async listUserVehicleIds() { calls.push("list"); guard("listUserVehicleIds"); return vehicleIds; },
    async deleteVehicleCascade(id) { calls.push(`vehicle:${id}`); guard("deleteVehicleCascade"); },
    async deleteUserDoc() { calls.push("userDoc"); guard("deleteUserDoc"); },
    async deleteUserQuotas() { calls.push("quotas"); guard("deleteUserQuotas"); },
    async deleteReceiptScanTokens() { calls.push("receiptTokens"); guard("deleteReceiptScanTokens"); },
    async deleteRevenueCatEvents() { calls.push("rcEvents"); guard("deleteRevenueCatEvents"); },
    async deleteReceiptCreditEvents() {
      calls.push("creditEvents");
      guard("deleteReceiptCreditEvents");
      // Refund-first ledgers have no pinned uid; the purged events' docId set is how
      // anonymization reaches them — assert the orchestration threads it through.
      return ["txn-doc-from-event"];
    },
    async anonymizeReceiptCreditTransactions(_uid: string, extraDocIds: string[]) {
      calls.push(`creditTxnAnonymize:${extraDocIds.join(",")}`);
      guard("anonymizeReceiptCreditTransactions");
    },
    async eraseRevenueCatSubscriber() { calls.push("rcErase"); guard("eraseRevenueCatSubscriber"); },
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
      "tombstone", "list", "vehicle:v1", "vehicle:v2", "userDoc", "quotas", "receiptTokens", "rcEvents", "creditEvents", "creditTxnAnonymize:txn-doc-from-event", "rcErase", "storage", "auth",
    ]);
    expect(calls[calls.length - 1]).toBe("auth");
    expect(calls[0]).toBe("tombstone");
    expect(calls.indexOf("creditEvents")).toBeLessThan(calls.indexOf("creditTxnAnonymize:txn-doc-from-event"));
    expect(result).toEqual({ deleted: true, vehiclesDeleted: 2 });
  });

  it("handles a user with no vehicles", async () => {
    const { calls, deps } = spyDeps([]);
    const result = await deleteAccountRequest({ auth: { uid: "owner-1" } }, deps);
    expect(calls).toEqual(["tombstone", "list", "userDoc", "quotas", "receiptTokens", "rcEvents", "creditEvents", "creditTxnAnonymize:txn-doc-from-event", "rcErase", "storage", "auth"]);
    expect(result.vehiclesDeleted).toBe(0);
  });

  it("does NOT delete the auth user if a prior data step fails (retry stays possible)", async () => {
    const { calls, deps } = spyDeps(["v1"], "deleteVehicleCascade");
    await expect(deleteAccountRequest({ auth: { uid: "owner-1" } }, deps)).rejects.toThrow("boom:deleteVehicleCascade");
    expect(calls).not.toContain("auth");
  });
});

describe("eraseRevenueCatSubscriberImpl", () => {
  const fetchSpy = (status: number) => {
    const urls: string[] = [];
    const impl = (async (url: RequestInfo | URL) => {
      urls.push(String(url));
      return new Response(null, { status });
    }) as typeof fetch;
    return { urls, impl };
  };

  it("skips (and does not fetch) when the key is unset or whitespace", async () => {
    const { urls, impl } = fetchSpy(200);
    await eraseRevenueCatSubscriberImpl("owner-1", impl, undefined, undefined);
    await eraseRevenueCatSubscriberImpl("owner-1", impl, "  \n", undefined);
    expect(urls).toEqual([]);
  });

  it("deletes the subscriber at RevenueCat, trimming a pasted trailing newline", async () => {
    const { urls, impl } = fetchSpy(200);
    await eraseRevenueCatSubscriberImpl("owner-1", impl, "sk_test\n", " project-1\n");
    expect(urls).toEqual(["https://api.revenuecat.com/v2/projects/project-1/customers/owner-1"]);
  });

  it("treats 404 as idempotent success (lost response + retry)", async () => {
    const { impl } = fetchSpy(404);
    await expect(eraseRevenueCatSubscriberImpl("owner-1", impl, "sk", "project-1")).resolves.toBeUndefined();
  });

  it("propagates a real API failure so the cascade fails and the user can retry", async () => {
    const { impl } = fetchSpy(500);
    await expect(eraseRevenueCatSubscriberImpl("owner-1", impl, "sk", "project-1")).rejects.toThrow("500");
  });

  it("requires the RC v2 project identifier once a secret is configured", async () => {
    const { impl } = fetchSpy(200);
    await expect(eraseRevenueCatSubscriberImpl("owner-1", impl, "sk", undefined)).rejects.toMatchObject({
      code: "unavailable",
    });
  });
});

describe("receipt-credit ledger anonymization", () => {
  it("sentinel-anonymizes the beneficiary and deletes raw transaction and event identifiers", () => {
    const fields = receiptCreditTransactionAnonymizationFields();
    expect(fields.uid).toBe("__deleted__");
    expect(fields.transactionId.isEqual(FieldValue.delete())).toBe(true);
    expect(fields.eventIds.isEqual(FieldValue.delete())).toBe(true);
  });
});
