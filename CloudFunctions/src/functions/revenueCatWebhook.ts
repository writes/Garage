import { timingSafeEqual } from "node:crypto";
import { getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";

type RevenueCatEvent = {
  appUserId: string;
  entitlementIds: string[];
  eventTimestampMs: number;
  id: string;
  type: string;
};

type DocumentReferenceLike = object;

type DocumentSnapshotLike = {
  exists: boolean;
  data(): Record<string, unknown> | undefined;
};

type TransactionLike = {
  get(reference: DocumentReferenceLike): Promise<DocumentSnapshotLike>;
  set(reference: DocumentReferenceLike, data: Record<string, unknown>, options?: { merge?: boolean }): TransactionLike;
};

/** Minimal Firestore transaction seam used by the request handler and unit tests. */
export type RevenueCatFirestore = {
  collection(path: string): {
    doc(id: string): DocumentReferenceLike;
  };
  runTransaction<T>(updateFunction: (transaction: TransactionLike) => Promise<T>): Promise<T>;
};

export type RevenueCatWebhookRequest = {
  body?: unknown;
  header(name: string): string | undefined;
};

export type RevenueCatWebhookResponse = {
  status(code: number): RevenueCatWebhookResponse;
  send(body: string): unknown;
};

export type RevenueCatWebhookDependencies = {
  db: RevenueCatFirestore;
  expectedAuthorization?: string;
  now?: () => Date;
};

type TransactionResult = "duplicate" | "processed" | "stale" | "unknown-user";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function parseRevenueCatEvent(body: unknown): RevenueCatEvent | undefined {
  if (!isRecord(body) || !isRecord(body.event)) {
    return undefined;
  }

  const event = body.event;
  const entitlementIds = event.entitlement_ids;

  if (
    !isNonEmptyString(event.app_user_id)
    || !isNonEmptyString(event.id)
    || !isNonEmptyString(event.type)
    || !Array.isArray(entitlementIds)
    || !entitlementIds.every((id) => typeof id === "string")
    || typeof event.event_timestamp_ms !== "number"
    || !Number.isFinite(event.event_timestamp_ms)
    || !Number.isSafeInteger(event.event_timestamp_ms)
    || Number.isNaN(new Date(event.event_timestamp_ms).getTime())
  ) {
    return undefined;
  }

  return {
    appUserId: event.app_user_id,
    entitlementIds,
    eventTimestampMs: event.event_timestamp_ms,
    id: event.id,
    type: event.type,
  };
}

function timingSafeEquals(actual: string, expected: string): boolean {
  const actualBuffer = Buffer.from(actual, "utf8");
  const expectedBuffer = Buffer.from(expected, "utf8");

  return actualBuffer.length === expectedBuffer.length && timingSafeEqual(actualBuffer, expectedBuffer);
}

export function isAuthorizedRequest(authorizationHeader: string | undefined, expectedValue: string | undefined): boolean {
  if (!authorizationHeader || !expectedValue || expectedValue.trim().length === 0) {
    return false;
  }

  return timingSafeEquals(authorizationHeader, expectedValue)
    || timingSafeEquals(authorizationHeader, `Bearer ${expectedValue}`);
}

function timestampMillis(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? undefined : parsed;
  }

  if (value instanceof Date) {
    const parsed = value.getTime();
    return Number.isNaN(parsed) ? undefined : parsed;
  }

  if (isRecord(value) && typeof value.toMillis === "function") {
    const parsed = value.toMillis();
    return typeof parsed === "number" && Number.isFinite(parsed) ? parsed : undefined;
  }

  return undefined;
}

function storedSubscriptionUpdatedAt(userData: Record<string, unknown> | undefined): number | undefined {
  if (!userData || !isRecord(userData.subscription)) {
    return undefined;
  }

  return timestampMillis(userData.subscription.updatedAt);
}

export async function handleRevenueCatWebhookRequest(
  request: RevenueCatWebhookRequest,
  response: RevenueCatWebhookResponse,
  dependencies: RevenueCatWebhookDependencies,
): Promise<void> {
  const expectedAuthorization = dependencies.expectedAuthorization;

  if (!expectedAuthorization || expectedAuthorization.trim().length === 0) {
    response.status(503).send("RevenueCat webhook authorization is not configured.");
    return;
  }

  const authorizationHeader = request.header("Authorization");

  if (!isAuthorizedRequest(authorizationHeader, expectedAuthorization)) {
    response.status(401).send("Unauthorized.");
    return;
  }

  const event = parseRevenueCatEvent(request.body);
  if (!event) {
    response.status(400).send("Invalid RevenueCat event.");
    return;
  }

  const eventRef = dependencies.db.collection("revenuecat_events").doc(event.id);
  const userRef = dependencies.db.collection("users").doc(event.appUserId);
  const isActive = event.entitlementIds.includes("pro");
  const updatedAt = new Date(event.eventTimestampMs).toISOString();
  const receivedAt = (dependencies.now ?? (() => new Date()))().toISOString();

  const result = await dependencies.db.runTransaction(async (transaction): Promise<TransactionResult> => {
    const existingEvent = await transaction.get(eventRef);

    if (existingEvent.exists) {
      return "duplicate";
    }

    const user = await transaction.get(userRef);
    if (!user.exists) {
      return "unknown-user";
    }

    transaction.set(eventRef, {
      appUserId: event.appUserId,
      entitlementIds: event.entitlementIds,
      eventTimestampMs: event.eventTimestampMs,
      receivedAt,
      type: event.type,
      updatedAt,
    });

    const priorUpdatedAt = storedSubscriptionUpdatedAt(user.data());
    if (priorUpdatedAt !== undefined && event.eventTimestampMs <= priorUpdatedAt) {
      return "stale";
    }

    transaction.set(userRef, {
      subscription: {
        entitlement: "pro",
        isActive,
        updatedAt,
      },
    }, { merge: true });

    return "processed";
  });

  if (result === "unknown-user") {
    response.status(400).send("Unknown RevenueCat app user id.");
    return;
  }

  response.status(200).send("ok");
}

export const handleRevenueCatWebhook = onRequest({ region: "us-central1" }, async (request, response) => {
  await handleRevenueCatWebhookRequest(
    request,
    response,
    {
      db: getFirestore() as unknown as RevenueCatFirestore,
      expectedAuthorization: process.env.REVENUECAT_WEBHOOK_AUTH,
    },
  );
});
