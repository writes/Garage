import { describe, expect, it } from "vitest";
import {
  consumeReceiptQuota,
  refundReceiptQuota,
} from "../src/functions/receiptQuota";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

const now = new Date("2026-07-30T17:00:00.000Z");
const uid = "owner-1";

function seedBaseConfirmedExhausted(db: InMemoryFirestore): void {
  db.seed(`usage_quotas/${uid}_receipt_lifetime`, { count: 5 });
  db.seed(`usage_quotas/${uid}_receipt_confirmed_lifetime`, { count: 5, reserved: 0 });
}

function seedCredits(db: InMemoryFirestore, values: Partial<Record<"granted" | "clawed" | "count" | "reserved" | "scanCount", number>> = {}): void {
  db.seed(`usage_quotas/${uid}_receipt_credits`, {
    uid,
    kind: "receipt_credits",
    granted: values.granted ?? 10,
    clawed: values.clawed ?? 0,
    count: values.count ?? 0,
    reserved: values.reserved ?? 0,
  });
  db.seed(`usage_quotas/${uid}_receipt_credit_scans`, {
    uid,
    kind: "receipt_credit_scans",
    count: values.scanCount ?? 0,
  });
}

async function rejection(promise: Promise<unknown>): Promise<{ code: string; details: unknown }> {
  try {
    await promise;
    throw new Error("Expected quota rejection");
  } catch (error) {
    return error as { code: string; details: unknown };
  }
}

describe("receipt-credit fallback admission", () => {
  it("uses credits only after the current base confirmed route denies, and binds the token to credit buckets", async () => {
    const db = new InMemoryFirestore();
    seedBaseConfirmedExhausted(db);
    seedCredits(db);

    const reservation = await consumeReceiptQuota(db, uid, now);

    expect(reservation).toMatchObject({
      entitlementUsed: "free",
      scanBucketId: `${uid}_receipt_credit_scans`,
      confirmedBucketId: `${uid}_receipt_credits`,
      quota: {
        // Legacy fields remain the exhausted current base route.
        confirmedRemaining: 0,
        confirmedAllowance: 5,
        creditsRemaining: 9,
        creditsScanRemaining: 39,
        creditsGranted: 10,
        creditsDeficit: 0,
      },
    });
    expect(reservation.quota).not.toHaveProperty("creditsPurchasingEnabled");
    expect(reservation.quota).not.toHaveProperty("transactionState");
    expect(db.data(`usage_quotas/${uid}_receipt_credits`)).toMatchObject({ count: 0, reserved: 1 });
    expect(db.data(`usage_quotas/${uid}_receipt_credit_scans`)).toMatchObject({ count: 1 });
    expect(db.data(`receipt_scan_tokens/${reservation.tokenId}`)).toMatchObject({
      confirmedBucketId: `${uid}_receipt_credits`,
      resetAtMillis: null,
    });
  });

  it("keeps the byte-stable base denial payload when the base scan and fallback both deny", async () => {
    const db = new InMemoryFirestore();
    db.seed(`usage_quotas/${uid}_receipt_lifetime`, { count: 20 });
    const error = await rejection(consumeReceiptQuota(db, uid, now));

    expect(error.code).toBe("resource-exhausted");
    expect(JSON.stringify(error.details)).toBe(JSON.stringify({
      reason: "receipt_scan_exhausted",
      scope: "free_lifetime",
    }));
  });

  it("keeps the byte-stable base denial payload when base confirmation and credits both deny", async () => {
    const db = new InMemoryFirestore();
    seedBaseConfirmedExhausted(db);
    seedCredits(db, { count: 10, reserved: 0, scanCount: 40 });
    const error = await rejection(consumeReceiptQuota(db, uid, now));

    expect(error.code).toBe("resource-exhausted");
    expect(JSON.stringify(error.details)).toBe(JSON.stringify({
      reason: "receipt_confirmed_exhausted",
      scope: "free_lifetime",
    }));
  });

  it("reads the post-expiry credit state before fallback admission so an expired credit token is not stranded", async () => {
    const db = new InMemoryFirestore();
    seedBaseConfirmedExhausted(db);
    seedCredits(db, { reserved: 1, scanCount: 1 });
    db.seed("receipt_scan_tokens/expired-credit", {
      uid,
      entitlementUsed: "free",
      confirmedBucketId: `${uid}_receipt_credits`,
      resetAtMillis: null,
      createdAtMillis: now.getTime() - 86_400_001,
      expiresAtMillis: now.getTime() - 1,
      consumed: false,
    });

    await consumeReceiptQuota(db, uid, now);

    // Release (-1) and new admission (+1) happen from the same post-release map.
    expect(db.data(`usage_quotas/${uid}_receipt_credits`)).toMatchObject({ reserved: 1 });
    expect(db.data(`usage_quotas/${uid}_receipt_credit_scans`)).toMatchObject({ count: 2 });
    expect(db.data("receipt_scan_tokens/expired-credit")).toMatchObject({
      consumed: true,
      released: true,
      releaseReason: "expired",
    });
  });

  it("refunds both a credit reservation and its scan-pool unit, and records a stable refund release reason", async () => {
    const db = new InMemoryFirestore();
    seedBaseConfirmedExhausted(db);
    seedCredits(db);
    const reservation = await consumeReceiptQuota(db, uid, now);

    await refundReceiptQuota(db, reservation, now);

    expect(db.data(`usage_quotas/${uid}_receipt_credits`)).toMatchObject({ reserved: 0, count: 0 });
    expect(db.data(`usage_quotas/${uid}_receipt_credit_scans`)).toMatchObject({ count: 0 });
    expect(db.data(`receipt_scan_tokens/${reservation.tokenId}`)).toMatchObject({
      consumed: true,
      released: true,
      releaseReason: "refund",
    });
  });

  it("uses the monotonic granted scan pool after a refunded pack is bought again", async () => {
    const db = new InMemoryFirestore();
    seedBaseConfirmedExhausted(db);
    // A refunded pack has no effective confirmed credits but retains its 40 historical scan slots.
    seedCredits(db, { granted: 10, clawed: 10, count: 0, reserved: 0, scanCount: 40 });
    const error = await rejection(consumeReceiptQuota(db, uid, now));
    expect(error.details).toMatchObject({ reason: "receipt_confirmed_exhausted" });

    // A rebuy raises granted monotonically to 20, reopening the 4x scan ceiling without erasing
    // the already-spent historical scan slots.
    seedCredits(db, { granted: 20, clawed: 10, count: 0, reserved: 0, scanCount: 40 });
    const reservation = await consumeReceiptQuota(db, uid, now);
    expect(reservation.confirmedBucketId).toBe(`${uid}_receipt_credits`);
    expect(db.data(`usage_quotas/${uid}_receipt_credit_scans`)).toMatchObject({ count: 41 });
  });
});
