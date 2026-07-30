import { describe, expect, it } from "vitest";
import {
  QUOTA_DOMAIN_MAX,
  foldReceiptCreditFact,
  isTimestampMillis,
  receiptCreditTransactionDocId,
  type ReceiptCreditFact,
} from "../src/functions/creditLedger";

const source = {
  appId: "app-expected",
  environment: "PRODUCTION",
  store: "APP_STORE",
  transactionId: "store-transaction-1",
};

function fact(
  kind: ReceiptCreditFact["kind"],
  timestampMillis: number,
  appUserId = "owner-a",
): ReceiptCreditFact {
  return {
    appUserId,
    eventId: `${kind}-${timestampMillis}`,
    kind,
    source,
    timestampMillis,
  };
}

describe("receipt credit ledger", () => {
  it("canonicalizes lower-case v2 source enums into the webhook transaction key", () => {
    expect(receiptCreditTransactionDocId({
      ...source,
      environment: " sandbox ",
      store: "app_store",
    })).toBe(receiptCreditTransactionDocId({ ...source, environment: "SANDBOX", store: "APP_STORE" }));
  });

  const permutations: Array<Array<ReceiptCreditFact["kind"]>> = [
    ["purchase", "refund", "reversal"],
    ["purchase", "reversal", "refund"],
    ["refund", "purchase", "reversal"],
    ["refund", "reversal", "purchase"],
    ["reversal", "purchase", "refund"],
    ["reversal", "refund", "purchase"],
  ];

  for (const order of permutations) {
    it(`reaches the same facts for ${order.join(" → ")}`, () => {
      const byKind = {
        purchase: fact("purchase", 1_000),
        refund: fact("refund", 2_000, "alias-b"),
        reversal: fact("reversal", 3_000, "alias-b"),
      };
      let ledger: Record<string, unknown> | undefined;
      let quota: Record<string, unknown> | undefined;
      for (const kind of order) {
        const result = foldReceiptCreditFact(ledger, quota, byKind[kind]);
        expect(result.kind).not.toBe("invalid");
        if (result.kind === "invalid") return;
        ledger = result.ledger;
        if (result.kind === "applied") quota = result.quota;
      }

      expect(ledger).toMatchObject({
        clawApplied: false,
        grantApplied: true,
        purchaseAtMillis: 1_000,
        refundAtMillis: 2_000,
        reversalAtMillis: 3_000,
        uid: "owner-a",
      });
      expect(quota).toMatchObject({ clawed: 0, granted: 10, uid: "owner-a" });
    });
  }

  it("uses reversal-wins-ties and applies a later refund again", () => {
    let ledger: Record<string, unknown> | undefined;
    let quota: Record<string, unknown> | undefined;
    for (const nextFact of [
      fact("purchase", 1_000),
      fact("refund", 2_000, "alias-b"),
      fact("reversal", 2_000, "alias-b"),
    ]) {
      const result = foldReceiptCreditFact(ledger, quota, nextFact);
      expect(result.kind).not.toBe("invalid");
      if (result.kind === "invalid") return;
      ledger = result.ledger;
      if (result.kind === "applied") quota = result.quota;
    }
    expect(quota).toMatchObject({ clawed: 0, granted: 10 });

    const reRefund = foldReceiptCreditFact(ledger, quota, fact("refund", 3_000, "alias-b"));
    expect(reRefund).toMatchObject({ kind: "applied", quota: { clawed: 10, granted: 10 } });
  });

  it("fails closed when checked claw arithmetic would exceed QUOTA_DOMAIN_MAX", () => {
    const existingLedger = {
      ...source,
      clawApplied: false,
      createdAtMillis: 1_000,
      eventIds: ["purchase-1000"],
      grantApplied: true,
      packDelta: 10,
      productId: "com.writes.harrysplayhouse.credits.receipts10",
      purchaseAtMillis: 1_000,
      uid: "owner-a",
      updatedAtMillis: 1_000,
    };
    const result = foldReceiptCreditFact(existingLedger, {
      clawed: QUOTA_DOMAIN_MAX - 5,
      count: 0,
      granted: 10,
      reserved: 0,
    }, fact("refund", 2_000, "alias-b"));

    expect(result).toEqual({ kind: "invalid", reason: "clawed_domain_max" });
  });

  it("accepts valid signed timestamps without applying quota-count shape rules", () => {
    expect(isTimestampMillis(-1)).toBe(true);
    expect(isTimestampMillis(1.5)).toBe(false);
    expect(isTimestampMillis(Number.MAX_SAFE_INTEGER)).toBe(false);
  });
});
