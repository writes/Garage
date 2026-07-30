import { describe, expect, it, vi } from "vitest";
import {
  reconcileReceiptCreditPurchaseRequest,
} from "../src/functions/reconcileReceiptCreditPurchase";
import {
  foldReceiptCreditFact,
  receiptCreditTransactionDocId,
  receiptCreditUidHash,
} from "../src/functions/creditLedger";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

const now = new Date("2026-07-30T17:00:00.000Z");
const uid = "owner-1";
const transactionId = "1000000123456789";

function request() {
  return { auth: { uid }, data: { transactionId } };
}

function purchase(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    object: "purchase",
    id: "purch_1",
    customer_id: uid,
    original_customer_id: uid,
    product_id: "prod_credits",
    purchased_at: now.getTime() - 1_000,
    status: "owned",
    store_purchase_identifier: transactionId,
    store: "app_store",
    environment: "sandbox",
    quantity: 1,
    ...overrides,
  };
}

function product(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    object: "product",
    id: "prod_credits",
    app_id: "com.writes.harrysplayhouse",
    store_identifier: "com.writes.harrysplayhouse.credits.receipts10",
    ...overrides,
  };
}

function fetchSequence(...responses: Array<Response | Record<string, unknown>>): typeof fetch {
  return vi.fn(async () => {
    const next = responses.shift();
    if (next instanceof Response) return next;
    return new Response(JSON.stringify(next), { status: 200 });
  }) as unknown as typeof fetch;
}

function dependencies(db: InMemoryFirestore, fetchImpl: typeof fetch, config: Partial<{
  allowedEnvironments: string;
  expectedAppId: string;
  expectedStore: string;
}> = {}) {
  return {
    db,
    fetchImpl,
    now: () => now,
    projectId: "project-1",
    revenueCatSecretApiKey: "secret-key\n",
    creditSourceConfig: {
      allowedEnvironments: config.allowedEnvironments ?? "PRODUCTION,SANDBOX",
      expectedAppId: config.expectedAppId ?? "com.writes.harrysplayhouse",
      expectedStore: config.expectedStore ?? "APP_STORE",
    },
  };
}

describe("reconcileReceiptCreditPurchaseRequest", () => {
  it("fails closed as unavailable without the bound v2 secret", async () => {
    const db = new InMemoryFirestore();
    const fetchImpl = fetchSequence({ items: [purchase()] }, product());
    const deps = { ...dependencies(db, fetchImpl), revenueCatSecretApiKey: "" };

    await expect(reconcileReceiptCreditPurchaseRequest(request(), deps)).rejects.toMatchObject({ code: "unavailable" });
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("looks up one owned v2 purchase, grants it through the shared ledger fold, and returns a composite quota", async () => {
    const db = new InMemoryFirestore();
    const fetchImpl = fetchSequence({ items: [purchase()] }, product());

    const response = await reconcileReceiptCreditPurchaseRequest(request(), dependencies(db, fetchImpl));

    expect(response).toMatchObject({
      transactionState: "granted",
      quota: {
        entitlement: "free",
        confirmedRemaining: 5,
        creditsGranted: 10,
        creditsRemaining: 10,
        creditsScanRemaining: 40,
        creditsDeficit: 0,
      },
    });
    expect(fetchImpl).toHaveBeenNthCalledWith(
      1,
      "https://api.revenuecat.com/v2/projects/project-1/purchases?store_purchase_identifier=1000000123456789",
      expect.objectContaining({ headers: { Authorization: "Bearer secret-key" } }),
    );
    expect(db.data(`usage_quotas/${uid}_receipt_credits`)).toMatchObject({ granted: 10, clawed: 0, count: 0, reserved: 0 });
    expect(db.data(`receipt_credit_txns/${receiptCreditTransactionDocId({
      appId: "com.writes.harrysplayhouse",
      store: "app_store",
      environment: "sandbox",
      transactionId,
    })}`)).toMatchObject({ eventIds: [`reconcile:${transactionId}`], grantApplied: true, uid });
  });

  it("is idempotent with an already webhook-folded transaction rather than double-granting", async () => {
    const db = new InMemoryFirestore();
    const source = {
      appId: "com.writes.harrysplayhouse",
      store: "APP_STORE",
      environment: "SANDBOX",
      transactionId,
    };
    const webhookFold = foldReceiptCreditFact(undefined, undefined, {
      appUserId: uid,
      eventId: "webhook:event-1",
      kind: "purchase",
      source,
      timestampMillis: now.getTime() - 1_000,
    });
    if (webhookFold.kind !== "applied") throw new Error("test fixture should fold");
    db.seed(`receipt_credit_txns/${receiptCreditTransactionDocId(source)}`, webhookFold.ledger);
    db.seed(`usage_quotas/${uid}_receipt_credits`, webhookFold.quota);
    const fetchImpl = fetchSequence({ items: [purchase()] }, product());

    const response = await reconcileReceiptCreditPurchaseRequest(request(), dependencies(db, fetchImpl));

    expect(response.transactionState).toBe("granted");
    expect(db.data(`usage_quotas/${uid}_receipt_credits`)).toMatchObject({ granted: 10, clawed: 0 });
    expect(db.data(`receipt_credit_txns/${receiptCreditTransactionDocId(source)}`)?.eventIds).toEqual([
      "webhook:event-1",
      `reconcile:${transactionId}`,
    ]);
  });

  it.each([
    ["sandbox not allowed", purchase(), product(), { allowedEnvironments: "PRODUCTION" }],
    ["wrong app", purchase(), product({ app_id: "other.app" }), {}],
    ["wrong store", purchase({ store: "play_store" }), product(), {}],
    ["outbound transferred", purchase({ customer_id: "other", original_customer_id: uid }), product(), {}],
    ["inbound transferred", purchase({ customer_id: uid, original_customer_id: "other" }), product(), {}],
    ["refunded", purchase({ status: "refunded" }), product(), {}],
    ["foreign uid", purchase({ customer_id: "other", original_customer_id: "other" }), product(), {}],
  ] as const)("maps %s purchase provenance to uniform not-found", async (_name, purchaseResponse, productResponse, config) => {
    const db = new InMemoryFirestore();
    const fetchImpl = fetchSequence({ items: [purchaseResponse] }, productResponse);

    await expect(reconcileReceiptCreditPurchaseRequest(request(), dependencies(db, fetchImpl, config))).rejects.toMatchObject({
      code: "not-found",
      message: "Receipt-credit purchase was not found.",
    });
    expect(db.data(`usage_quotas/${uid}_receipt_credits`)).toBeUndefined();
  });

  it("maps an upstream 429 with Retry-After to unavailable instead of a false missing grant", async () => {
    const db = new InMemoryFirestore();
    const fetchImpl = fetchSequence(new Response("slow down", { status: 429, headers: { "Retry-After": "7" } }));

    await expect(reconcileReceiptCreditPurchaseRequest(request(), dependencies(db, fetchImpl))).rejects.toMatchObject({
      code: "unavailable",
      details: { retryAfterSeconds: 7 },
    });
  });

  it("maps empty and ambiguous searches to not-found, never an outage-shaped unavailable", async () => {
    const emptyDb = new InMemoryFirestore();
    await expect(reconcileReceiptCreditPurchaseRequest(
      request(),
      dependencies(emptyDb, fetchSequence({ items: [] })),
    )).rejects.toMatchObject({ code: "not-found" });

    const ambiguousDb = new InMemoryFirestore();
    await expect(reconcileReceiptCreditPurchaseRequest(
      request(),
      dependencies(ambiguousDb, fetchSequence({ items: [purchase(), purchase({ id: "purch_2" })] })),
    )).rejects.toMatchObject({ code: "not-found" });
  });

  it("maps a v2 timeout to retryable unavailable", async () => {
    const db = new InMemoryFirestore();
    const fetchImpl = vi.fn(async () => {
      throw new DOMException("deadline", "TimeoutError");
    }) as unknown as typeof fetch;

    await expect(reconcileReceiptCreditPurchaseRequest(request(), dependencies(db, fetchImpl))).rejects.toMatchObject({
      code: "unavailable",
    });
  });

  it("treats a malformed v2 response as unavailable and never folds a synthetic grant", async () => {
    const db = new InMemoryFirestore();
    const fetchImpl = fetchSequence({ malformed: true });

    await expect(reconcileReceiptCreditPurchaseRequest(request(), dependencies(db, fetchImpl))).rejects.toMatchObject({ code: "unavailable" });
    expect(db.collectionData("receipt_credit_txns")).toEqual([]);
  });

  it("enforces the per-user ten-per-day server rate limit before making an upstream request", async () => {
    const db = new InMemoryFirestore();
    db.seed(`usage_quotas/${uid}_receipt_credit_reconcile_2026-07-30`, {
      uid,
      kind: "receipt_credit_reconcile_daily",
      count: 10,
    });
    const fetchImpl = fetchSequence({ items: [purchase()] }, product());

    await expect(reconcileReceiptCreditPurchaseRequest(request(), dependencies(db, fetchImpl))).rejects.toMatchObject({
      code: "resource-exhausted",
    });
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("is inert after tombstone-first deletion, preventing a deletion-racing reconciliation grant", async () => {
    const db = new InMemoryFirestore();
    db.seed(`deleted_users/${receiptCreditUidHash(uid)}`, { deletedAtMillis: now.getTime() });
    const fetchImpl = fetchSequence({ items: [purchase()] }, product());

    await expect(reconcileReceiptCreditPurchaseRequest(request(), dependencies(db, fetchImpl))).rejects.toMatchObject({ code: "not-found" });
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(db.collectionData("receipt_credit_txns")).toEqual([]);
  });
});
