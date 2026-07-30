import { describe, expect, it } from "vitest";
import { receiptQuotaStatusRequest } from "../src/functions/receiptQuotaStatus";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

const now = new Date("2026-07-28T17:00:00.000Z");

function dependencies(db: InMemoryFirestore) {
  return { db, now: () => now };
}

function request(uid = "owner-1") {
  return { auth: { uid } };
}

function seedPro(db: InMemoryFirestore): void {
  db.seed("users/owner-1", {
    subscription: { entitlement: "pro", isActive: true, expiresAt: "2026-09-01T00:00:00.000Z" },
  });
}

describe("receiptQuotaStatusRequest", () => {
  it("reports a fresh free balance", async () => {
    await expect(receiptQuotaStatusRequest(request(), dependencies(new InMemoryFirestore()))).resolves.toEqual({
      entitlement: "free",
      scanRemaining: 20,
      scanCeiling: 20,
      confirmedRemaining: 5,
      confirmedAllowance: 5,
      resetAt: null,
    });
  });

  it("shows partial confirmed usage and outstanding reservations in the effective remaining balance", async () => {
    const db = new InMemoryFirestore();
    db.seed("usage_quotas/owner-1_receipt_lifetime", { count: 3 });
    db.seed("usage_quotas/owner-1_receipt_confirmed_lifetime", { count: 1, reserved: 2 });
    await expect(receiptQuotaStatusRequest(request(), dependencies(db))).resolves.toMatchObject({
      scanRemaining: 17,
      confirmedRemaining: 2,
    });
  });

  it("clamps exhausted free buckets at zero remaining", async () => {
    const db = new InMemoryFirestore();
    db.seed("usage_quotas/owner-1_receipt_lifetime", { count: 20 });
    db.seed("usage_quotas/owner-1_receipt_confirmed_lifetime", { count: 5, reserved: 0 });
    await expect(receiptQuotaStatusRequest(request(), dependencies(db))).resolves.toMatchObject({
      scanRemaining: 0,
      confirmedRemaining: 0,
    });
  });

  it("reports the Pro month reset and monthly ceiling", async () => {
    const db = new InMemoryFirestore();
    seedPro(db);
    await expect(receiptQuotaStatusRequest(request(), dependencies(db))).resolves.toEqual({
      entitlement: "pro",
      scanRemaining: 80,
      scanCeiling: 80,
      confirmedRemaining: 20,
      confirmedAllowance: 20,
      resetAt: "2026-08-01T00:00:00.000Z",
    });
  });

  it("releases expired abandoned reservations before returning the snapshot", async () => {
    const db = new InMemoryFirestore();
    db.seed("usage_quotas/owner-1_receipt_confirmed_lifetime", { count: 1, reserved: 1 });
    db.seed("receipt_scan_tokens/expired-token", {
      uid: "owner-1",
      entitlementUsed: "free",
      confirmedBucketId: "owner-1_receipt_confirmed_lifetime",
      resetAtMillis: null,
      createdAtMillis: now.getTime() - 48 * 60 * 60 * 1_000,
      expiresAtMillis: now.getTime() - 1,
      consumed: false,
    });

    await expect(receiptQuotaStatusRequest(request(), dependencies(db))).resolves.toMatchObject({ confirmedRemaining: 4 });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ count: 1, reserved: 0 });
    expect(db.data("receipt_scan_tokens/expired-token")).toMatchObject({ consumed: true, released: true });
  });
});
