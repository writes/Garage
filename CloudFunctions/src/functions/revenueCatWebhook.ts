import { timingSafeEqual } from "node:crypto";
import { getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";

type StandardRevenueCatEvent = {
  appUserId: string;
  entitlementIds: string[];
  eventTimestampMs: number;
  id: string;
  kind: "standard";
  type: string;
};

type TransferRevenueCatEvent = {
  appUserId?: string;
  eventTimestampMs: number;
  id: string;
  kind: "transfer";
  transferredFrom: string[];
  transferredTo: string[];
  type: "TRANSFER";
};

type RevenueCatEvent = StandardRevenueCatEvent | TransferRevenueCatEvent;

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

const grantEventTypes = new Set<StandardRevenueCatEvent["type"]>([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
  "NON_RENEWING_PURCHASE",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}

function parseRevenueCatEvent(body: unknown): RevenueCatEvent | undefined {
  if (!isRecord(body) || !isRecord(body.event)) {
    return undefined;
  }

  const event = body.event;

  if (
    !isNonEmptyString(event.id)
    || !isNonEmptyString(event.type)
    || typeof event.event_timestamp_ms !== "number"
    || !Number.isFinite(event.event_timestamp_ms)
    || !Number.isSafeInteger(event.event_timestamp_ms)
    || Number.isNaN(new Date(event.event_timestamp_ms).getTime())
  ) {
    return undefined;
  }

  if (event.type === "TRANSFER") {
    if (!isStringArray(event.transferred_from) || !isStringArray(event.transferred_to)) {
      return undefined;
    }

    return {
      appUserId: isNonEmptyString(event.app_user_id) ? event.app_user_id : undefined,
      eventTimestampMs: event.event_timestamp_ms,
      id: event.id,
      kind: "transfer",
      transferredFrom: event.transferred_from,
      transferredTo: event.transferred_to,
      type: "TRANSFER",
    };
  }

  const entitlementIds = event.entitlement_ids;
  if (!isNonEmptyString(event.app_user_id) || !isStringArray(entitlementIds)) {
    return undefined;
  }

  return {
    appUserId: event.app_user_id,
    entitlementIds,
    eventTimestampMs: event.event_timestamp_ms,
    id: event.id,
    kind: "standard",
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

/**
 * A cancellation only disables auto-renewal; the existing entitlement remains
 * valid until RevenueCat sends an EXPIRATION. Unknown events are recorded but
 * intentionally do not change access.
 */
function entitlementActivityForEvent(event: StandardRevenueCatEvent): boolean | undefined {
  if (grantEventTypes.has(event.type)) {
    return event.entitlementIds.includes("pro") ? true : undefined;
  }

  if (event.type === "EXPIRATION") {
    return event.entitlementIds.includes("pro") ? false : undefined;
  }

  return undefined;
}

function eventRecord(event: RevenueCatEvent, receivedAt: string, updatedAt: string): Record<string, unknown> {
  const common = {
    eventTimestampMs: event.eventTimestampMs,
    receivedAt,
    type: event.type,
    updatedAt,
  };

  if (event.kind === "transfer") {
    return {
      ...common,
      ...(event.appUserId ? { appUserId: event.appUserId } : {}),
      transferredFrom: event.transferredFrom,
      transferredTo: event.transferredTo,
    };
  }

  return {
    ...common,
    appUserId: event.appUserId,
    entitlementIds: event.entitlementIds,
  };
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
  const updatedAt = new Date(event.eventTimestampMs).toISOString();
  const receivedAt = (dependencies.now ?? (() => new Date()))().toISOString();

  await dependencies.db.runTransaction(async (transaction) => {
    const existingEvent = await transaction.get(eventRef);

    if (existingEvent.exists) {
      return "duplicate";
    }

    transaction.set(eventRef, eventRecord(event, receivedAt, updatedAt));

    // A transfer is a relationship change between multiple identities, not a
    // single-user entitlement verdict. RevenueCat follows with per-user events.
    if (event.kind === "transfer") {
      return "processed";
    }

    const userRef = dependencies.db.collection("users").doc(event.appUserId);
    const user = await transaction.get(userRef);
    const isActive = entitlementActivityForEvent(event);

    const priorUpdatedAt = storedSubscriptionUpdatedAt(user.data());
    if (
      priorUpdatedAt !== undefined
      && (
        event.eventTimestampMs < priorUpdatedAt
        || (event.eventTimestampMs === priorUpdatedAt && isActive !== false)
      )
    ) {
      return "stale";
    }

    if (isActive === undefined) {
      return "processed";
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
