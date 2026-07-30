import { describe, expect, it, vi } from "vitest";
import * as logger from "firebase-functions/logger";
import {
  handleRevenueCatWebhookRequest,
  type RevenueCatWebhookResponse,
} from "../src/functions/revenueCatWebhook";
import { receiptCreditTransactionDocId, receiptCreditUidHash } from "../src/functions/creditLedger";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

const expectedAuthorization = "webhook-test-secret";
const fixedNow = new Date("2026-07-10T20:00:00.000Z");
const creditSourceConfig = {
  allowedEnvironments: "PRODUCTION,SANDBOX",
  expectedAppId: "app-expected",
  expectedStore: "APP_STORE",
};
const creditProductId = "com.writes.harrysplayhouse.credits.receipts10";

type ResponseCapture = {
  body?: string;
  statusCode?: number;
  response: RevenueCatWebhookResponse;
};

function captureResponse(): ResponseCapture {
  const capture: ResponseCapture = {
    response: undefined as unknown as RevenueCatWebhookResponse,
  };

  capture.response = {
    status(code: number): RevenueCatWebhookResponse {
      capture.statusCode = code;
      return capture.response;
    },
    send(body: string): void {
      capture.body = body;
    },
  };

  return capture;
}

function request(body: unknown, authorization = expectedAuthorization): { body: unknown; header(name: string): string | undefined } {
  return {
    body,
    header(name: string): string | undefined {
      return name === "Authorization" ? authorization : undefined;
    },
  };
}

// Renewable grants carry an expiration in production; a grant WITHOUT one is the
// fail-closed edge exercised explicitly below (override expiration_at_ms: undefined).
function event(overrides: Record<string, unknown> = {}): { event: Record<string, unknown> } {
  return {
    event: {
      app_user_id: "owner-1",
      entitlement_ids: ["pro"],
      event_timestamp_ms: Date.parse("2026-07-10T10:00:00.000Z"),
      expiration_at_ms: Date.parse("2026-08-10T10:00:00.000Z"),
      id: "event-1",
      type: "RENEWAL",
      ...overrides,
    },
  };
}

function transferEvent(overrides: Record<string, unknown> = {}): { event: Record<string, unknown> } {
  return {
    event: {
      event_timestamp_ms: Date.parse("2026-07-10T10:00:00.000Z"),
      expiration_at_ms: Date.parse("2026-08-10T10:00:00.000Z"),
      id: "transfer-1",
      transferred_from: ["old-owner"],
      transferred_to: ["new-owner"],
      type: "TRANSFER",
      ...overrides,
    },
  };
}

function creditEvent(overrides: Record<string, unknown> = {}): { event: Record<string, unknown> } {
  return event({
    app_id: creditSourceConfig.expectedAppId,
    entitlement_ids: [],
    environment: "PRODUCTION",
    expiration_at_ms: undefined,
    product_id: creditProductId,
    quantity: 1,
    store: creditSourceConfig.expectedStore,
    transaction_id: "store-transaction-1",
    type: "NON_RENEWING_PURCHASE",
    ...overrides,
  });
}

async function send(
  db: InMemoryFirestore,
  body: unknown,
  authorization = expectedAuthorization,
  configuredAuthorization: string | undefined = expectedAuthorization,
  configuredCreditSource: {
    allowedEnvironments?: string;
    expectedAppId?: string;
    expectedStore?: string;
  } = creditSourceConfig,
): Promise<ResponseCapture> {
  const capture = captureResponse();
  await handleRevenueCatWebhookRequest(request(body, authorization), capture.response, {
    db,
    creditSourceConfig: configuredCreditSource,
    expectedAuthorization: configuredAuthorization,
    now: () => fixedNow,
  });
  return capture;
}

describe("handleRevenueCatWebhookRequest", () => {
  it("makes the transaction double reject reads after a write", async () => {
    const db = new InMemoryFirestore();
    const eventRef = db.collection("revenuecat_events").doc("ordering-check");

    await expect(db.runTransaction(async (transaction) => {
      transaction.set(eventRef, { type: "RENEWAL" });
      return transaction.get(eventRef);
    })).rejects.toThrow("Firestore transactions require all reads to be executed before all writes.");
  });

  it("accepts a valid Bearer-authenticated grant and writes the entitlement", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", { profile: { displayName: "Owner" } });

    const result = await send(db, event(), `Bearer ${expectedAuthorization}`);

    expect(result.statusCode).toBe(200);
    expect(result.body).toBe("ok");
    expect(db.data("users/owner-1")).toMatchObject({
      profile: { displayName: "Owner" },
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-10T10:00:00.000Z",
      },
    });
    expect(db.data("revenuecat_events/event-1")).toMatchObject({
      appUserId: "owner-1",
      entitlementIds: ["pro"],
      eventTimestampMs: Date.parse("2026-07-10T10:00:00.000Z"),
      receivedAt: fixedNow.toISOString(),
    });
  });

  it("persists an authoritative expiration timestamp with an active pro grant", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    await send(db, event({
      expiration_at_ms: Date.parse("2026-08-10T10:00:00.000Z"),
      id: "renewal-with-expiry",
    }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-10T10:00:00.000Z",
        expiresAt: "2026-08-10T10:00:00.000Z",
      },
    });
  });

  it("deactivates an EXPIRATION when the expired pro entitlement is listed", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {
      subscription: {
        entitlement: "pro",
        isActive: true,
        expiresAt: "2026-08-10T10:00:00.000Z",
      },
    });

    const result = await send(db, event({ id: "revoke-1", type: "EXPIRATION" }));

    expect(result.statusCode).toBe(200);
    expect(db.data("users/owner-1")).toMatchObject({
      subscription: {
        isActive: false,
        expiresAt: "2026-08-10T10:00:00.000Z",
      },
    });
  });

  it("grants pro only for a supported grant event with the pro entitlement", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    await send(db, event({ id: "renewal-pro", type: "RENEWAL", entitlement_ids: ["pro"] }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { isActive: true },
    });
  });

  it("records an unrelated renewal without changing the active pro entitlement", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
        expiresAt: "2026-08-10T10:00:00.000Z",
      },
    });

    await send(db, event({ entitlement_ids: ["premium_support"], id: "unrelated-renewal" }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
        expiresAt: "2026-08-10T10:00:00.000Z",
      },
    });
    expect(db.data("revenuecat_events/unrelated-renewal")).toMatchObject({
      entitlementIds: ["premium_support"],
      type: "RENEWAL",
    });
  });

  it("records an unrelated expiration without changing the active pro entitlement", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
      },
    });

    await send(db, event({ entitlement_ids: ["premium_support"], id: "unrelated-expiration", type: "EXPIRATION" }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
      },
    });
    expect(db.data("revenuecat_events/unrelated-expiration")).toMatchObject({
      entitlementIds: ["premium_support"],
      type: "EXPIRATION",
    });
  });

  it("records a CANCELLATION without changing the active entitlement", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
        expiresAt: "2026-08-10T10:00:00.000Z",
      },
    });

    await send(db, event({ id: "cancellation-1", type: "CANCELLATION" }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
        expiresAt: "2026-08-10T10:00:00.000Z",
      },
    });
    expect(db.data("revenuecat_events/cancellation-1")).toMatchObject({ type: "CANCELLATION" });
  });

  it("records an unknown event without changing entitlement state", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
      },
    });

    await send(db, event({ id: "unknown-1", type: "BILLING_ISSUE" }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
      },
    });
    expect(db.data("revenuecat_events/unknown-1")).toMatchObject({ type: "BILLING_ISSUE" });
  });

  it("makes a duplicate event id idempotent", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    await send(db, event({ id: "duplicate-1" }));
    const result = await send(db, event({
      id: "duplicate-1",
      entitlement_ids: [],
      event_timestamp_ms: Date.parse("2026-07-11T10:00:00.000Z"),
      type: "EXPIRATION",
    }));

    expect(result.statusCode).toBe(200);
    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { isActive: true, updatedAt: "2026-07-10T10:00:00.000Z" },
    });
  });

  it("records a stale pro expiration without downgrading a newer subscription, but applies a newer one", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-12T10:00:00.000Z",
      },
    });

    const result = await send(db, event({
      entitlement_ids: ["pro"],
      id: "stale-revoke",
      type: "EXPIRATION",
    }));

    expect(result.statusCode).toBe(200);
    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { isActive: true, updatedAt: "2026-07-12T10:00:00.000Z" },
    });
    expect(db.data("revenuecat_events/stale-revoke")).toMatchObject({
      entitlementIds: ["pro"],
    });

    await send(db, event({
      entitlement_ids: ["pro"],
      event_timestamp_ms: Date.parse("2026-07-13T10:00:00.000Z"),
      id: "newer-revoke",
      type: "EXPIRATION",
    }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { isActive: false, updatedAt: "2026-07-13T10:00:00.000Z" },
    });
  });

  it("converges an out-of-order grant/revoke pair to the newest event", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    await send(db, event({
      id: "new-grant",
      event_timestamp_ms: Date.parse("2026-07-12T10:00:00.000Z"),
    }));
    await send(db, event({
      id: "old-revoke",
      entitlement_ids: ["pro"],
      event_timestamp_ms: Date.parse("2026-07-11T10:00:00.000Z"),
      type: "EXPIRATION",
    }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { isActive: true, updatedAt: "2026-07-12T10:00:00.000Z" },
    });
  });

  it("resolves a same-millisecond grant then revoke pair as inactive", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});
    const timestamp = Date.parse("2026-07-12T10:00:00.000Z");

    await send(db, event({ id: "same-ms-grant", event_timestamp_ms: timestamp, type: "RENEWAL" }));
    await send(db, event({
      id: "same-ms-revoke",
      entitlement_ids: ["pro"],
      event_timestamp_ms: timestamp,
      type: "EXPIRATION",
    }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { isActive: false, updatedAt: "2026-07-12T10:00:00.000Z" },
    });
  });

  it("resolves a same-millisecond revoke then grant pair as inactive", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});
    const timestamp = Date.parse("2026-07-12T10:00:00.000Z");

    await send(db, event({ id: "same-ms-revoke", event_timestamp_ms: timestamp, type: "EXPIRATION" }));
    await send(db, event({ id: "same-ms-grant", event_timestamp_ms: timestamp, type: "RENEWAL" }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { isActive: false, updatedAt: "2026-07-12T10:00:00.000Z" },
    });
  });

  it("rejects missing and invalid authorization headers", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    const missing = captureResponse();
    await handleRevenueCatWebhookRequest({
      body: event(),
      header: (): undefined => undefined,
    }, missing.response, {
      db,
      expectedAuthorization,
      now: () => fixedNow,
    });
    const invalid = await send(db, event(), "wrong-secret");

    expect(missing.statusCode).toBe(401);
    expect(invalid.statusCode).toBe(401);
  });

  it("acknowledges RevenueCat TEST pings with 200 and applies nothing", async () => {
    // The dashboard's "Send test event" posts type: "TEST" with entitlement_ids: null, which
    // the parser rejects. Answering 400 leaves the connectivity test permanently red and makes
    // RevenueCat retry every ping as a failed delivery.
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    const result = await send(db, event({
      id: "test-ping-1",
      type: "TEST",
      entitlement_ids: null,   // exactly what RevenueCat's test button sends
      product_id: "test_product",
      store: "PLAY_STORE",
      environment: "SANDBOX",
    }));

    expect(result.statusCode).toBe(200);
    // Nothing applied: no entitlement change, and no event record written.
    expect(db.data("users/owner-1")?.subscription).toBeUndefined();
    expect(db.data("revenuecat_events/test-ping-1")).toBeUndefined();
  });

  it("still rejects an unauthorized TEST ping", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    const result = await send(
      db,
      event({ id: "test-ping-2", type: "TEST", entitlement_ids: null }),
      "wrong-secret",
    );

    expect(result.statusCode).toBe(401);
  });

  it("fails closed when the webhook authorization environment value is absent", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    const result = await send(db, event(), expectedAuthorization, "");

    expect(result.statusCode).toBe(503);
    expect(db.data("revenuecat_events/event-1")).toBeUndefined();
  });

  it("revokes transfer sources, durably grants destinations, and records the transfer", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/old-owner", {
      profile: { displayName: "Old owner" },
      subscription: {
        entitlement: "pro",
        expiresAt: "2026-07-31T10:00:00.000Z",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
      },
    });

    const result = await send(db, transferEvent({
      expiration_at_ms: Date.parse("2026-08-10T10:00:00.000Z"),
    }));

    expect(result.statusCode).toBe(200);
    expect(db.data("users/old-owner")).toMatchObject({
      profile: { displayName: "Old owner" },
      subscription: {
        entitlement: "pro",
        expiresAt: "2026-07-31T10:00:00.000Z",
        isActive: false,
        updatedAt: "2026-07-10T10:00:00.000Z",
      },
    });
    expect(db.data("users/new-owner")).toMatchObject({
      subscription: {
        entitlement: "pro",
        expiresAt: "2026-08-10T10:00:00.000Z",
        isActive: true,
        updatedAt: "2026-07-10T10:00:00.000Z",
      },
    });
    expect(db.data("revenuecat_events/transfer-1")).toMatchObject({
      transferredFrom: ["old-owner"],
      transferredTo: ["new-owner"],
      type: "TRANSFER",
    });
    expect(db.data("revenuecat_events/transfer-1")).not.toHaveProperty("appUserId");
    expect(db.transactionTraces()).toEqual([{
      reads: ["revenuecat_events/transfer-1", "users/old-owner", "users/new-owner"],
      writes: ["revenuecat_events/transfer-1", "users/old-owner", "users/new-owner"],
    }]);
  });

  it("makes a duplicate transfer event id idempotent", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/old-owner", {});

    await send(db, transferEvent({ id: "transfer-duplicate" }));
    const replay = await send(db, transferEvent({
      event_timestamp_ms: Date.parse("2026-07-11T10:00:00.000Z"),
      id: "transfer-duplicate",
      transferred_from: ["new-owner"],
      transferred_to: ["third-owner"],
    }));

    expect(replay.statusCode).toBe(200);
    expect(db.data("users/old-owner")).toMatchObject({
      subscription: { isActive: false, updatedAt: "2026-07-10T10:00:00.000Z" },
    });
    expect(db.data("users/new-owner")).toMatchObject({
      subscription: { isActive: true, updatedAt: "2026-07-10T10:00:00.000Z" },
    });
    expect(db.data("users/third-owner")).toBeUndefined();
    expect(db.transactionTraces()[1]).toEqual({
      reads: ["revenuecat_events/transfer-duplicate"],
      writes: [],
    });
  });

  it("records an older transfer without clobbering newer owner states", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/old-owner", {
      subscription: {
        entitlement: "pro",
        expiresAt: "2026-08-15T10:00:00.000Z",
        isActive: true,
        updatedAt: "2026-07-12T10:00:00.000Z",
      },
    });
    db.seed("users/new-owner", {
      subscription: {
        entitlement: "pro",
        expiresAt: "2026-08-20T10:00:00.000Z",
        isActive: false,
        updatedAt: "2026-07-12T10:00:00.000Z",
      },
    });

    const result = await send(db, transferEvent({ id: "stale-transfer" }));

    expect(result.statusCode).toBe(200);
    expect(db.data("users/old-owner")).toMatchObject({
      subscription: {
        expiresAt: "2026-08-15T10:00:00.000Z",
        isActive: true,
        updatedAt: "2026-07-12T10:00:00.000Z",
      },
    });
    expect(db.data("users/new-owner")).toMatchObject({
      subscription: {
        expiresAt: "2026-08-20T10:00:00.000Z",
        isActive: false,
        updatedAt: "2026-07-12T10:00:00.000Z",
      },
    });
    expect(db.data("revenuecat_events/stale-transfer")).toMatchObject({
      eventTimestampMs: Date.parse("2026-07-10T10:00:00.000Z"),
      type: "TRANSFER",
    });
  });

  it("rejects malformed transfer ownership arrays and expiration before any write", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/old-owner", {
      subscription: { isActive: true, updatedAt: "2026-07-12T10:00:00.000Z" },
    });

    const malformedFrom = await send(db, transferEvent({
      id: "malformed-transfer-from",
      transferred_from: "old-owner",
    }));
    const malformedTo = await send(db, transferEvent({
      id: "malformed-transfer-to",
      transferred_to: [42],
    }));
    const malformedExpiration = await send(db, transferEvent({
      expiration_at_ms: "not-a-timestamp",
      id: "malformed-transfer-expiration",
    }));

    expect(malformedFrom.statusCode).toBe(400);
    expect(malformedTo.statusCode).toBe(400);
    expect(malformedExpiration.statusCode).toBe(400);
    expect(db.data("users/old-owner")).toMatchObject({
      subscription: { isActive: true, updatedAt: "2026-07-12T10:00:00.000Z" },
    });
    expect(db.data("users/new-owner")).toBeUndefined();
    expect(db.data("revenuecat_events/malformed-transfer-from")).toBeUndefined();
    expect(db.data("revenuecat_events/malformed-transfer-to")).toBeUndefined();
    expect(db.data("revenuecat_events/malformed-transfer-expiration")).toBeUndefined();
  });

  it("rejects malformed event bodies before any write", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    const result = await send(db, event({ event_timestamp_ms: "not-a-number" }));

    expect(result.statusCode).toBe(400);
    expect(db.data("revenuecat_events/event-1")).toBeUndefined();
  });

  it("rejects a missing app user id before any write", async () => {
    const db = new InMemoryFirestore();

    const missing = await send(db, event({ app_user_id: "" }));

    expect(missing.statusCode).toBe(400);
    expect(db.data("revenuecat_events/event-1")).toBeUndefined();
  });

  it("revokes immediately on a refund (CANCELLATION with cancel_reason CUSTOMER_SUPPORT)", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
        expiresAt: "2026-08-10T10:00:00.000Z",
      },
    });

    const result = await send(db, event({
      cancel_reason: "CUSTOMER_SUPPORT",
      id: "refund-1",
      type: "CANCELLATION",
    }));

    expect(result.statusCode).toBe(200);
    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { entitlement: "pro", isActive: false, updatedAt: "2026-07-10T10:00:00.000Z" },
    });
    expect(db.data("revenuecat_events/refund-1")).toMatchObject({ type: "CANCELLATION" });
  });

  it("keeps access on a voluntary CANCELLATION (cancel_reason UNSUBSCRIBE)", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
        expiresAt: "2026-08-10T10:00:00.000Z",
      },
    });

    await send(db, event({
      cancel_reason: "UNSUBSCRIBE",
      id: "voluntary-cancel-1",
      type: "CANCELLATION",
    }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { isActive: true, updatedAt: "2026-07-09T10:00:00.000Z" },
    });
  });

  it("fails closed on a renewable grant with no expiration and no prior expiry", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", { profile: { displayName: "Owner" } });

    const result = await send(db, event({
      expiration_at_ms: undefined,
      id: "no-expiry-grant",
      type: "INITIAL_PURCHASE",
    }));

    expect(result.statusCode).toBe(200);
    expect(db.data("users/owner-1")).not.toHaveProperty("subscription");
    expect(db.data("revenuecat_events/no-expiry-grant")).toMatchObject({ type: "INITIAL_PURCHASE" });
  });

  it("preserves the prior expiry when a renewable grant omits expiration", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
        expiresAt: "2026-08-01T10:00:00.000Z",
      },
    });

    await send(db, event({ expiration_at_ms: undefined, id: "no-expiry-renewal" }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: {
        isActive: true,
        updatedAt: "2026-07-10T10:00:00.000Z",
        expiresAt: "2026-08-01T10:00:00.000Z",
      },
    });
  });

  it("records but skips a non-credit NON_RENEWING_PURCHASE without an expiration", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    await send(db, event({
      expiration_at_ms: undefined,
      id: "lifetime-1",
      type: "NON_RENEWING_PURCHASE",
    }));

    expect(db.data("users/owner-1")?.subscription).toBeUndefined();
    expect(db.data("revenuecat_events/lifetime-1")).toMatchObject({ type: "NON_RENEWING_PURCHASE" });
  });

  it("re-grants on REFUND_REVERSED and extends expiry on SUBSCRIPTION_EXTENDED", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {
      subscription: {
        entitlement: "pro",
        isActive: false,
        updatedAt: "2026-07-09T10:00:00.000Z",
        expiresAt: "2026-07-09T10:00:00.000Z",
      },
    });

    await send(db, event({ id: "refund-reversed-1", type: "REFUND_REVERSED" }));
    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { isActive: true, expiresAt: "2026-08-10T10:00:00.000Z" },
    });

    await send(db, event({
      event_timestamp_ms: Date.parse("2026-07-11T10:00:00.000Z"),
      expiration_at_ms: Date.parse("2026-09-10T10:00:00.000Z"),
      id: "extended-1",
      type: "SUBSCRIPTION_EXTENDED",
    }));
    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { isActive: true, expiresAt: "2026-09-10T10:00:00.000Z" },
    });
  });

  it("repairs a skipped transfer destination on re-send once an expiry source exists", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/old-owner", {
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
        expiresAt: "2026-07-31T10:00:00.000Z",
      },
    });

    await send(db, transferEvent({ expiration_at_ms: undefined, id: "retryable-transfer" }));
    expect(db.data("users/new-owner")).toBeUndefined();
    expect(db.data("revenuecat_events/retryable-transfer")).toMatchObject({
      grantSkippedUserIds: ["new-owner"],
    });

    // Support heals the destination with an expiry-bearing grant; the SAME event id re-sent
    // from the RevenueCat dashboard must now reprocess instead of dead-ending on "duplicate".
    db.seed("users/new-owner", {
      subscription: {
        entitlement: "pro",
        isActive: false,
        updatedAt: "2026-07-01T10:00:00.000Z",
        expiresAt: "2026-09-01T10:00:00.000Z",
      },
    });
    const resend = await send(db, transferEvent({ expiration_at_ms: undefined, id: "retryable-transfer" }));

    expect(resend.statusCode).toBe(200);
    expect(db.data("users/new-owner")).toMatchObject({
      subscription: { isActive: true, expiresAt: "2026-09-01T10:00:00.000Z" },
    });
    expect(db.data("revenuecat_events/retryable-transfer")).not.toHaveProperty("grantSkippedUserIds");

    // With the skip marker cleared, a further re-send is a plain duplicate again.
    const third = await send(db, transferEvent({ expiration_at_ms: undefined, id: "retryable-transfer" }));
    expect(third.statusCode).toBe(200);
    expect(db.transactionTraces()[2].writes).toEqual([]);
  });

  it("skips a transfer destination grant when the event has no expiration (fail closed)", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/old-owner", {
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
        expiresAt: "2026-07-31T10:00:00.000Z",
      },
    });

    const result = await send(db, transferEvent({
      expiration_at_ms: undefined,
      id: "no-expiry-transfer",
    }));

    expect(result.statusCode).toBe(200);
    expect(db.data("users/old-owner")).toMatchObject({
      subscription: { isActive: false, updatedAt: "2026-07-10T10:00:00.000Z" },
    });
    expect(db.data("users/new-owner")).toBeUndefined();
    expect(db.data("revenuecat_events/no-expiry-transfer")).toMatchObject({ type: "TRANSFER" });
  });

  it("upserts a missing user and prevents a later stale event from clobbering it", async () => {
    const db = new InMemoryFirestore();
    const createdAt = Date.parse("2026-07-12T10:00:00.000Z");

    const created = await send(db, event({
      app_user_id: "new-owner",
      event_timestamp_ms: createdAt,
      id: "create-missing-owner",
    }));
    const stale = await send(db, event({
      app_user_id: "new-owner",
      entitlement_ids: ["pro"],
      event_timestamp_ms: Date.parse("2026-07-11T10:00:00.000Z"),
      id: "stale-missing-owner-expiration",
      type: "EXPIRATION",
    }));

    expect(created.statusCode).toBe(200);
    expect(stale.statusCode).toBe(200);
    expect(db.data("users/new-owner")).toMatchObject({
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-12T10:00:00.000Z",
      },
    });
    expect(db.data("revenuecat_events/create-missing-owner")).toMatchObject({
      appUserId: "new-owner",
      type: "RENEWAL",
    });
    expect(db.data("revenuecat_events/stale-missing-owner-expiration")).toMatchObject({
      appUserId: "new-owner",
      type: "EXPIRATION",
    });
  });

  const creditFactPermutations: Array<Array<"purchase" | "cancellation" | "reversal">> = [
    ["purchase", "cancellation", "reversal"],
    ["purchase", "reversal", "cancellation"],
    ["cancellation", "purchase", "reversal"],
    ["cancellation", "reversal", "purchase"],
    ["reversal", "purchase", "cancellation"],
    ["reversal", "cancellation", "purchase"],
  ];

  function creditFactEvent(
    fact: "purchase" | "cancellation" | "reversal",
    overrides: Record<string, unknown> = {},
  ): { event: Record<string, unknown> } {
    const timestamps = {
      cancellation: 2_000,
      purchase: 1_000,
      reversal: 3_000,
    };
    const eventType = {
      cancellation: "CANCELLATION",
      purchase: "NON_RENEWING_PURCHASE",
      reversal: "REFUND_REVERSED",
    };
    return creditEvent({
      event_timestamp_ms: timestamps[fact],
      id: `credit-${fact}`,
      type: eventType[fact],
      ...overrides,
    });
  }

  for (const arrivalOrder of creditFactPermutations) {
    it(`folds receipt-credit facts independently of ${arrivalOrder.join(" → ")} arrival`, async () => {
      const db = new InMemoryFirestore();
      for (const fact of arrivalOrder) await send(db, creditFactEvent(fact));
      // Replaying a fact after every possible arrival order is still one grant and no claw.
      await send(db, creditFactEvent("purchase"));

      const txnId = receiptCreditTransactionDocId({
        appId: creditSourceConfig.expectedAppId,
        environment: "PRODUCTION",
        store: creditSourceConfig.expectedStore,
        transactionId: "store-transaction-1",
      });
      expect(db.data("usage_quotas/owner-1_receipt_credits")).toMatchObject({
        clawed: 0,
        granted: 10,
        kind: "receipt_credits",
      });
      expect(db.data(`receipt_credit_txns/${txnId}`)).toMatchObject({
        clawApplied: false,
        grantApplied: true,
        purchaseAtMillis: 1_000,
        refundAtMillis: 2_000,
        reversalAtMillis: 3_000,
        uid: "owner-1",
      });
    });
  }

  for (const arrivalOrder of creditFactPermutations) {
    it(`pins purchase beneficiary across alias facts in ${arrivalOrder.join(" → ")}`, async () => {
      const db = new InMemoryFirestore();
      for (const fact of arrivalOrder) {
        await send(db, creditFactEvent(fact, {
          app_user_id: fact === "purchase" ? "owner-a" : "owner-b",
          id: `alias-${fact}`,
        }));
      }

      expect(db.data("usage_quotas/owner-a_receipt_credits")).toMatchObject({ clawed: 0, granted: 10 });
      expect(db.data("usage_quotas/owner-b_receipt_credits")).toBeUndefined();
      const txnId = receiptCreditTransactionDocId({
        appId: creditSourceConfig.expectedAppId,
        environment: "PRODUCTION",
        store: creditSourceConfig.expectedStore,
        transactionId: "store-transaction-1",
      });
      expect(db.data(`receipt_credit_txns/${txnId}`)).toMatchObject({ uid: "owner-a" });
      const cancellationRecord = db.data("revenuecat_events/alias-cancellation");
      if (arrivalOrder.indexOf("purchase") < arrivalOrder.indexOf("cancellation")) {
        expect(cancellationRecord).toMatchObject({ beneficiaryUidHash: receiptCreditUidHash("owner-a") });
      } else {
        // Before a purchase fact arrives there is intentionally no beneficiary to hash; most
        // importantly, the refund alias is never misrepresented as the ledger beneficiary.
        expect(cancellationRecord).not.toHaveProperty("beneficiaryUidHash");
      }
    });
  }

  it("claws again when a later refund follows refund → reversal", async () => {
    const db = new InMemoryFirestore();
    await send(db, creditFactEvent("purchase"));
    await send(db, creditFactEvent("cancellation", { id: "cycle-refund-one", event_timestamp_ms: 2_000 }));
    await send(db, creditFactEvent("reversal", { id: "cycle-reversal", event_timestamp_ms: 3_000 }));
    await send(db, creditFactEvent("cancellation", { id: "cycle-refund-two", event_timestamp_ms: 4_000 }));

    expect(db.data("usage_quotas/owner-1_receipt_credits")).toMatchObject({ clawed: 10, granted: 10 });
  });

  it("converges concurrent identical credit deliveries to one grant", async () => {
    const db = new InMemoryFirestore();
    await Promise.all([
      send(db, creditEvent({ id: "concurrent-credit" })),
      send(db, creditEvent({ id: "concurrent-credit" })),
    ]);

    expect(db.data("usage_quotas/owner-1_receipt_credits")).toMatchObject({ clawed: 0, granted: 10 });
    expect(db.collectionData("receipt_credit_txns")).toHaveLength(1);
  });

  it("accepts a null entitlement_ids credit grant and records an empty entitlement list", async () => {
    const db = new InMemoryFirestore();
    const result = await send(db, creditEvent({ entitlement_ids: null, id: "null-entitlements" }));

    expect(result.statusCode).toBe(200);
    expect(db.data("usage_quotas/owner-1_receipt_credits")).toMatchObject({ granted: 10 });
    expect(db.data("revenuecat_events/null-entitlements")).toMatchObject({ entitlementIds: [] });
  });

  it("accepts a SANDBOX credit on the production allowlist, flags it, and warns", async () => {
    const db = new InMemoryFirestore();
    const warn = vi.spyOn(logger, "warn").mockImplementation(() => undefined);
    try {
      const result = await send(db, creditEvent({ environment: "SANDBOX", id: "sandbox-accepted" }));
      const txnId = receiptCreditTransactionDocId({
        appId: creditSourceConfig.expectedAppId,
        environment: "SANDBOX",
        store: creditSourceConfig.expectedStore,
        transactionId: "store-transaction-1",
      });

      expect(result.statusCode).toBe(200);
      expect(db.data("usage_quotas/owner-1_receipt_credits")).toMatchObject({ granted: 10 });
      expect(db.data(`receipt_credit_txns/${txnId}`)).toMatchObject({ environment: "SANDBOX" });
      expect(warn).toHaveBeenCalledWith(
        "revenuecat receipt-credit sandbox transaction accepted",
        expect.objectContaining({ eventId: "sandbox-accepted" }),
      );
    } finally {
      warn.mockRestore();
    }
  });

  it("records source rejections without creating a ledger and allows rejected-source replay", async () => {
    const db = new InMemoryFirestore();
    const rejected = [
      creditEvent({ environment: "DEVELOPMENT", id: "rejected-environment" }),
      creditEvent({ id: "rejected-store", store: "PLAY_STORE" }),
      creditEvent({ app_id: "other-app", id: "rejected-app" }),
      creditEvent({ app_id: "", id: "missing-app" }),
      creditEvent({ id: "missing-transaction", transaction_id: "" }),
    ];
    for (const body of rejected) {
      const result = await send(db, body);
      expect(result.statusCode).toBe(200);
      const id = body.event.id as string;
      expect(db.data(`revenuecat_events/${id}`)).toMatchObject({ disposition: "rejected_source_config" });
      expect(db.data(`revenuecat_events/${id}`)).not.toHaveProperty("transactionId");
    }
    expect(db.collectionData("receipt_credit_txns")).toEqual([]);
    expect(db.data("usage_quotas/owner-1_receipt_credits")).toBeUndefined();

    await send(db, creditEvent({ id: "retry-source-config" as string, store: "PLAY_STORE" }));
    const replay = await send(db, creditEvent({ id: "retry-source-config" }));
    expect(replay.statusCode).toBe(200);
    expect(db.data("revenuecat_events/retry-source-config")).toMatchObject({ disposition: "applied" });
    expect(db.data("usage_quotas/owner-1_receipt_credits")).toMatchObject({ granted: 10 });
  });

  it("returns 503 without writing a credit event when required source configuration is unset", async () => {
    const db = new InMemoryFirestore();
    const result = await send(db, creditEvent({ id: "missing-source-config" }), expectedAuthorization, expectedAuthorization, {});

    expect(result.statusCode).toBe(503);
    expect(db.data("revenuecat_events/missing-source-config")).toBeUndefined();
    expect(db.collectionData("receipt_credit_txns")).toEqual([]);
  });

  it("records quantity conflicts as terminal no-ops in either purchase order", async () => {
    for (const order of [[0, 1], [1, 0]]) {
      const db = new InMemoryFirestore();
      const bodies = [
        creditEvent({ id: "quantity-invalid", quantity: 2 }),
        creditEvent({ id: "quantity-valid", quantity: 1 }),
      ];
      for (const index of order) await send(db, bodies[index]);

      expect(db.data("revenuecat_events/quantity-invalid")).toMatchObject({ disposition: "rejected_quantity" });
      expect(db.data("usage_quotas/owner-1_receipt_credits")).toMatchObject({ granted: 10 });
    }
  });

  it("does not recreate any user-linked state after the purchase beneficiary is tombstoned", async () => {
    const db = new InMemoryFirestore();
    await send(db, creditFactEvent("purchase", { app_user_id: "owner-a", id: "tombstone-purchase" }));
    db.seed(`deleted_users/${receiptCreditUidHash("owner-a")}`, { deletedAtMillis: 9_999 });
    const priorLedger = db.collectionData("receipt_credit_txns");
    const priorQuota = db.data("usage_quotas/owner-a_receipt_credits");

    const result = await send(db, creditFactEvent("cancellation", {
      app_user_id: "owner-b",
      id: "tombstone-refund-alias",
    }));

    expect(result.statusCode).toBe(200);
    expect(db.data("revenuecat_events/tombstone-refund-alias")).toBeUndefined();
    expect(db.collectionData("receipt_credit_txns")).toEqual(priorLedger);
    expect(db.data("usage_quotas/owner-a_receipt_credits")).toEqual(priorQuota);

    const sentinel = new InMemoryFirestore();
    await send(sentinel, creditEvent({ app_user_id: "__deleted__", id: "deleted-sentinel" }));
    expect(sentinel.data("revenuecat_events/deleted-sentinel")).toBeUndefined();
    expect(sentinel.collectionData("receipt_credit_txns")).toEqual([]);
  });

  it("never writes subscription state for a credits+pro payload", async () => {
    const db = new InMemoryFirestore();
    const result = await send(db, creditEvent({ entitlement_ids: ["pro"], id: "credits-with-pro" }));

    expect(result.statusCode).toBe(200);
    expect(db.data("users/owner-1")).toBeUndefined();
    expect(db.data("usage_quotas/owner-1_receipt_credits")).toMatchObject({ granted: 10 });
  });

  it("uses an identical ledger key for lower-case v2-style and upper-case webhook sources", async () => {
    const lowerCase = receiptCreditTransactionDocId({
      appId: creditSourceConfig.expectedAppId,
      environment: " sandbox ",
      store: "app_store",
      transactionId: "store-transaction-1",
    });
    const upperCase = receiptCreditTransactionDocId({
      appId: creditSourceConfig.expectedAppId,
      environment: "SANDBOX",
      store: "APP_STORE",
      transactionId: "store-transaction-1",
    });
    expect(lowerCase).toBe(upperCase);

    const db = new InMemoryFirestore();
    await send(db, creditEvent({ environment: "sandbox", id: "lower-source", store: "app_store" }));
    await send(db, creditEvent({ environment: "SANDBOX", id: "upper-source", store: "APP_STORE" }));
    expect(db.collectionData("receipt_credit_txns")).toHaveLength(1);
    expect(db.data("usage_quotas/owner-1_receipt_credits")).toMatchObject({ granted: 10 });
  });
});
