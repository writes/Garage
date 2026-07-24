import { describe, expect, it } from "vitest";
import {
  handleRevenueCatWebhookRequest,
  type RevenueCatWebhookResponse,
} from "../src/functions/revenueCatWebhook";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

const expectedAuthorization = "webhook-test-secret";
const fixedNow = new Date("2026-07-10T20:00:00.000Z");

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

async function send(
  db: InMemoryFirestore,
  body: unknown,
  authorization = expectedAuthorization,
  configuredAuthorization: string | undefined = expectedAuthorization,
): Promise<ResponseCapture> {
  const capture = captureResponse();
  await handleRevenueCatWebhookRequest(request(body, authorization), capture.response, {
    db,
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

  it("grants a lifetime NON_RENEWING_PURCHASE without an expiration", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    await send(db, event({
      expiration_at_ms: undefined,
      id: "lifetime-1",
      type: "NON_RENEWING_PURCHASE",
    }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { entitlement: "pro", isActive: true, updatedAt: "2026-07-10T10:00:00.000Z" },
    });
    expect(db.data("users/owner-1")?.subscription).not.toHaveProperty("expiresAt");
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
});
