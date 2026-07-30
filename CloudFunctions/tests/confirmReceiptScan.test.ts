import { describe, expect, it } from "vitest";
import { confirmReceiptScanRequest } from "../src/functions/confirmReceiptScan";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

const now = new Date("2026-07-28T17:00:00.000Z");
const freeToken = "11111111-1111-4111-8111-111111111111";
const proToken = "22222222-2222-4222-8222-222222222222";

function dependencies(db: InMemoryFirestore, clock = now) {
  return { db, now: () => clock };
}

function request(token: string, uid = "owner-1") {
  return { auth: { uid }, data: { token } };
}

function seedFreeReservation(db: InMemoryFirestore, options: {
  token?: string;
  uid?: string;
  expiresAtMillis?: number;
  consumed?: boolean;
} = {}): string {
  const token = options.token ?? freeToken;
  const uid = options.uid ?? "owner-1";
  db.seed(`usage_quotas/${uid}_receipt_lifetime`, { count: 1 });
  db.seed(`usage_quotas/${uid}_receipt_confirmed_lifetime`, { count: 0, reserved: 1 });
  db.seed(`receipt_scan_tokens/${token}`, {
    uid,
    entitlementUsed: "free",
    confirmedBucketId: `${uid}_receipt_confirmed_lifetime`,
    resetAtMillis: null,
    createdAtMillis: now.getTime() - 1_000,
    expiresAtMillis: options.expiresAtMillis ?? now.getTime() + 24 * 60 * 60 * 1_000,
    consumed: options.consumed ?? false,
  });
  return token;
}

function seedProReservation(db: InMemoryFirestore, period = "2026-07"): void {
  const createdAtMillis = Date.parse("2026-07-31T23:00:00.000Z");
  db.seed(`usage_quotas/owner-1_receipt_scan_${period}`, { count: 1 });
  db.seed(`usage_quotas/owner-1_receipt_confirmed_${period}`, { count: 0, reserved: 1 });
  db.seed(`receipt_scan_tokens/${proToken}`, {
    uid: "owner-1",
    entitlementUsed: "pro",
    confirmedBucketId: `owner-1_receipt_confirmed_${period}`,
    resetAtMillis: Date.parse("2026-08-01T00:00:00.000Z"),
    createdAtMillis,
    expiresAtMillis: createdAtMillis + 24 * 60 * 60 * 1_000,
    consumed: false,
  });
}

describe("confirmReceiptScanRequest", () => {
  it("converts a valid reservation into one confirmed receipt and returns the effective snapshot", async () => {
    const db = new InMemoryFirestore();
    seedFreeReservation(db);

    await expect(confirmReceiptScanRequest(request(freeToken), dependencies(db))).resolves.toEqual({
      entitlement: "free",
      scanRemaining: 19,
      scanCeiling: 20,
      confirmedRemaining: 4,
      confirmedAllowance: 5,
      resetAt: null,
    });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ count: 1, reserved: 0 });
    expect(db.data(`receipt_scan_tokens/${freeToken}`)).toMatchObject({ consumed: true, consumedAtMillis: now.getTime() });
  });

  it("is idempotent, including a retry after the token expiry timestamp", async () => {
    const db = new InMemoryFirestore();
    seedFreeReservation(db);
    const first = await confirmReceiptScanRequest(request(freeToken), dependencies(db));
    const retry = await confirmReceiptScanRequest(
      request(freeToken),
      dependencies(db, new Date(now.getTime() + 48 * 60 * 60 * 1_000)),
    );
    expect(retry).toEqual(first);
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ count: 1, reserved: 0 });
  });

  it("rejects a released token instead of reporting a confirmation that never happened", async () => {
    // A token voided by the expiry sweep or a refund path is consumed+released with its
    // reservation already returned. Only a real confirmation may be idempotent-success —
    // success here would hide the miss from the client's confirm-failure telemetry.
    const db = new InMemoryFirestore();
    seedFreeReservation(db, { consumed: true });
    db.seed(`receipt_scan_tokens/${freeToken}`, {
      ...db.data(`receipt_scan_tokens/${freeToken}`),
      released: true,
    });

    await expect(confirmReceiptScanRequest(request(freeToken), dependencies(db))).rejects.toMatchObject({
      code: "failed-precondition",
      details: { reason: "receipt_token_expired" },
    });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ count: 0, reserved: 1 });
  });

  it("rejects an expired unconsumed token and releases its reservation in the same transaction", async () => {
    const db = new InMemoryFirestore();
    seedFreeReservation(db, { expiresAtMillis: now.getTime() - 1 });

    await expect(confirmReceiptScanRequest(request(freeToken), dependencies(db))).rejects.toMatchObject({
      code: "failed-precondition",
      details: { reason: "receipt_token_expired" },
    });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ count: 0, reserved: 0 });
    expect(db.data(`receipt_scan_tokens/${freeToken}`)).toMatchObject({
      consumed: true,
      consumedAtMillis: now.getTime(),
      released: true,
    });
  });

  it("rejects a malformed token before any Firestore read", async () => {
    const db = new InMemoryFirestore();
    await expect(confirmReceiptScanRequest(request("not-a-token"), dependencies(db))).rejects.toMatchObject({
      code: "invalid-argument",
    });
    expect(db.transactionTraces()).toEqual([]);
  });

  it("uses the same not-found response for missing and foreign tokens", async () => {
    const missingDb = new InMemoryFirestore();
    const missing = await confirmReceiptScanRequest(request(freeToken), dependencies(missingDb)).catch((error) => error);

    const foreignDb = new InMemoryFirestore();
    seedFreeReservation(foreignDb, { uid: "other-owner" });
    const foreign = await confirmReceiptScanRequest(request(freeToken), dependencies(foreignDb)).catch((error) => error);

    expect(missing).toMatchObject({ code: "not-found", message: "Receipt scan token was not found." });
    expect(foreign).toMatchObject({ code: "not-found", message: "Receipt scan token was not found." });
  });

  it("keeps a free token bound to its free bucket when the owner upgrades before confirming", async () => {
    const db = new InMemoryFirestore();
    seedFreeReservation(db);
    db.seed("users/owner-1", {
      subscription: { entitlement: "pro", isActive: true, expiresAt: "2026-09-01T00:00:00.000Z" },
    });

    await confirmReceiptScanRequest(request(freeToken), dependencies(db));
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ count: 1, reserved: 0 });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_2026-07")).toBeUndefined();
  });

  it("keeps a Pro token bound to its admitting month after the UTC month boundary", async () => {
    const db = new InMemoryFirestore();
    seedProReservation(db, "2026-07");

    const snapshot = await confirmReceiptScanRequest(
      request(proToken),
      dependencies(db, new Date("2026-08-01T00:30:00.000Z")),
    );
    expect(snapshot).toMatchObject({ entitlement: "pro", resetAt: "2026-08-01T00:00:00.000Z" });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_2026-07")).toMatchObject({ count: 1, reserved: 0 });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_2026-08")).toBeUndefined();
  });
});
