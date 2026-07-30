import { describe, expect, it } from "vitest";
import { receiptQuotaStatusRequest } from "../src/functions/receiptQuotaStatus";
import { receiptCreditTransactionDocId } from "../src/functions/creditLedger";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

const now = new Date("2026-07-28T17:00:00.000Z");

function dependencies(db: InMemoryFirestore) {
  return {
    db,
    now: () => now,
    creditSourceConfig: {
      expectedAppId: "com.writes.harrysplayhouse",
      expectedStore: "APP_STORE",
      allowedEnvironments: "PRODUCTION,SANDBOX",
    },
  };
}

function request(uid = "owner-1", transactionId?: string) {
  return { auth: { uid }, ...(transactionId === undefined ? {} : { data: { transactionId } }) };
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
      creditsRemaining: 0,
      creditsScanRemaining: 0,
      creditsGranted: 0,
      creditsDeficit: 0,
      creditsPurchasingEnabled: false,
      sweepIncomplete: false,
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
      creditsRemaining: 0,
      creditsScanRemaining: 0,
      creditsGranted: 0,
      creditsDeficit: 0,
      creditsPurchasingEnabled: false,
      sweepIncomplete: false,
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

  it.each([10, 12, 50, 51, 100])("drains %i expired credit reservations server-side before the consistent snapshot", async (count) => {
    const db = new InMemoryFirestore();
    db.seed("usage_quotas/owner-1_receipt_credits", {
      uid: "owner-1",
      kind: "receipt_credits",
      granted: count,
      clawed: 0,
      count: 0,
      reserved: count,
    });
    for (let index = 0; index < count; index += 1) {
      db.seed(`receipt_scan_tokens/expired-${index}`, {
        uid: "owner-1",
        entitlementUsed: "free",
        confirmedBucketId: "owner-1_receipt_credits",
        resetAtMillis: null,
        createdAtMillis: now.getTime() - 86_400_001,
        expiresAtMillis: now.getTime() - 1,
        consumed: false,
      });
    }

    const snapshot = await receiptQuotaStatusRequest(request(), dependencies(db));

    expect(snapshot.sweepIncomplete).toBe(false);
    expect(snapshot.creditsRemaining).toBe(count);
    expect(db.data("usage_quotas/owner-1_receipt_credits")).toMatchObject({ reserved: 0 });
    expect(db.collectionData("receipt_scan_tokens").every(({ data }) => data.consumed === true)).toBe(true);
  });

  it("reports sweepIncomplete after the bounded 10-round status drain and leaves a retryable remainder", async () => {
    const db = new InMemoryFirestore();
    db.seed("usage_quotas/owner-1_receipt_credits", {
      uid: "owner-1",
      kind: "receipt_credits",
      granted: 520,
      clawed: 0,
      count: 0,
      reserved: 520,
    });
    for (let index = 0; index < 520; index += 1) {
      db.seed(`receipt_scan_tokens/expired-${index}`, {
        uid: "owner-1",
        entitlementUsed: "free",
        confirmedBucketId: "owner-1_receipt_credits",
        resetAtMillis: null,
        createdAtMillis: now.getTime() - 86_400_001,
        expiresAtMillis: now.getTime() - 1,
        consumed: false,
      });
    }

    const snapshot = await receiptQuotaStatusRequest(request(), dependencies(db));

    expect(snapshot.sweepIncomplete).toBe(true);
    // Ten bounded sweep rounds release 100 tokens. The final snapshot is read-only, and the
    // client keeps refetching with no cap, so the remaining 420 continue to converge.
    expect(db.data("usage_quotas/owner-1_receipt_credits")).toMatchObject({ reserved: 420 });
    expect(db.collectionData("receipt_scan_tokens").filter(({ data }) => data.consumed !== true)).toHaveLength(420);
  });

  it("reads the final status transaction in the required order and resolves exactly one own candidate", async () => {
    const db = new InMemoryFirestore();
    const transactionId = "1000000123456789";
    const source = {
      appId: "com.writes.harrysplayhouse",
      store: "APP_STORE",
      environment: "SANDBOX",
      transactionId,
    };
    db.seed(`receipt_credit_txns/${receiptCreditTransactionDocId(source)}`, {
      uid: "owner-1",
      grantApplied: true,
      clawApplied: false,
    });
    db.seed("app_config/receipt_credits", { purchasingEnabled: true, expiresAtMillis: now.getTime() + 1 });

    const result = await receiptQuotaStatusRequest(request("owner-1", transactionId), dependencies(db));
    const finalTrace = db.transactionTraces().at(-1);

    expect(result).toMatchObject({ transactionState: "granted", creditsPurchasingEnabled: true, sweepIncomplete: false });
    expect(finalTrace?.reads).toEqual([
      "users/owner-1",
      "usage_quotas/owner-1_receipt_lifetime",
      "usage_quotas/owner-1_receipt_confirmed_lifetime",
      "usage_quotas/owner-1_receipt_credits",
      "usage_quotas/owner-1_receipt_credit_scans",
      "app_config/receipt_credits",
      `receipt_credit_txns/${receiptCreditTransactionDocId({ ...source, environment: "PRODUCTION" })}`,
      `receipt_credit_txns/${receiptCreditTransactionDocId(source)}`,
    ]);
  });

  it.each([
    ["own granted", { uid: "owner-1", grantApplied: true }, "granted"],
    ["own refunded", { uid: "owner-1", grantApplied: true, refundAtMillis: now.getTime() }, "refunded"],
    ["foreign", { uid: "other", grantApplied: true }, "unknown"],
    ["absent", undefined, "unknown"],
  ] as const)("returns %s transaction state without leaking foreign records", async (_name, ledger, expected) => {
    const db = new InMemoryFirestore();
    const transactionId = "1000000123456789";
    const source = {
      appId: "com.writes.harrysplayhouse",
      store: "APP_STORE",
      environment: "PRODUCTION",
      transactionId,
    };
    if (ledger) db.seed(`receipt_credit_txns/${receiptCreditTransactionDocId(source)}`, ledger);

    await expect(receiptQuotaStatusRequest(request("owner-1", transactionId), dependencies(db))).resolves.toMatchObject({
      transactionState: expected,
    });
  });

  it("returns unknown when multiple allowed-environment candidates are owned by the caller", async () => {
    const db = new InMemoryFirestore();
    const transactionId = "1000000123456789";
    for (const environment of ["PRODUCTION", "SANDBOX"]) {
      db.seed(`receipt_credit_txns/${receiptCreditTransactionDocId({
        appId: "com.writes.harrysplayhouse",
        store: "APP_STORE",
        environment,
        transactionId,
      })}`, { uid: "owner-1", grantApplied: true });
    }
    await expect(receiptQuotaStatusRequest(request("owner-1", transactionId), dependencies(db))).resolves.toMatchObject({
      transactionState: "unknown",
    });
  });

  it("fails capability closed for an expired operator purchasing window", async () => {
    const db = new InMemoryFirestore();
    db.seed("app_config/receipt_credits", { purchasingEnabled: true, expiresAtMillis: now.getTime() - 1 });
    await expect(receiptQuotaStatusRequest(request(), dependencies(db))).resolves.toMatchObject({
      creditsPurchasingEnabled: false,
    });
  });
});
