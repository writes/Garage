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

function event(overrides: Record<string, unknown> = {}): { event: Record<string, unknown> } {
  return {
    event: {
      app_user_id: "owner-1",
      entitlement_ids: ["pro"],
      event_timestamp_ms: Date.parse("2026-07-10T10:00:00.000Z"),
      id: "event-1",
      type: "RENEWAL",
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

  it("deactivates an EXPIRATION when the expired pro entitlement is listed", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    const result = await send(db, event({ id: "revoke-1", type: "EXPIRATION" }));

    expect(result.statusCode).toBe(200);
    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { isActive: false },
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
      },
    });

    await send(db, event({ entitlement_ids: ["premium_support"], id: "unrelated-renewal" }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
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
      },
    });

    await send(db, event({ id: "cancellation-1", type: "CANCELLATION" }));

    expect(db.data("users/owner-1")).toMatchObject({
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-09T10:00:00.000Z",
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

  it("records a stale event but does not downgrade a newer subscription", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {
      subscription: {
        entitlement: "pro",
        isActive: true,
        updatedAt: "2026-07-12T10:00:00.000Z",
      },
    });

    const result = await send(db, event({ entitlement_ids: [], id: "stale-revoke", type: "EXPIRATION" }));

    expect(result.statusCode).toBe(200);
    expect(db.data("users/owner-1")).toMatchObject({
      subscription: { isActive: true, updatedAt: "2026-07-12T10:00:00.000Z" },
    });
    expect(db.data("revenuecat_events/stale-revoke")).toMatchObject({
      entitlementIds: [],
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
      entitlement_ids: [],
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

  it("rejects malformed event bodies before any write", async () => {
    const db = new InMemoryFirestore();
    db.seed("users/owner-1", {});

    const result = await send(db, event({ event_timestamp_ms: "not-a-number" }));

    expect(result.statusCode).toBe(400);
    expect(db.data("revenuecat_events/event-1")).toBeUndefined();
  });

  it("rejects missing and unknown app user ids", async () => {
    const db = new InMemoryFirestore();

    const missing = await send(db, event({ app_user_id: "" }));
    const unknown = await send(db, event({ app_user_id: "missing-owner", id: "unknown-owner" }));

    expect(missing.statusCode).toBe(400);
    expect(unknown.statusCode).toBe(400);
    expect(db.data("revenuecat_events/unknown-owner")).toBeUndefined();
  });
});
