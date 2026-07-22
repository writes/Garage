import { timingSafeEqual } from "node:crypto";
import { getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { revenueCatWebhookAuth } from "../params";

type StandardRevenueCatEvent = {
  appUserId: string;
  entitlementIds: string[];
  eventTimestampMs: number;
  expirationAtMs?: number;
  id: string;
  kind: "standard";
  type: string;
};

type TransferRevenueCatEvent = {
  appUserId?: string;
  eventTimestampMs: number;
  expirationAtMs?: number;
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

/** RevenueCat TRANSFER fields identify Firebase/RevenueCat app users, not arbitrary payload values. */
function isAppUserIdArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every(isNonEmptyString);
}

function isTimestampMillis(value: unknown): value is number {
  return typeof value === "number"
    && Number.isFinite(value)
    && Number.isSafeInteger(value)
    && !Number.isNaN(new Date(value).getTime());
}

function parseRevenueCatEvent(body: unknown): RevenueCatEvent | undefined {
  if (!isRecord(body) || !isRecord(body.event)) {
    return undefined;
  }

  const event = body.event;

  if (
    !isNonEmptyString(event.id)
    || !isNonEmptyString(event.type)
    || !isTimestampMillis(event.event_timestamp_ms)
  ) {
    return undefined;
  }

  const rawExpirationAtMs = event.expiration_at_ms;

  if (event.type === "TRANSFER") {
    if (
      !isAppUserIdArray(event.transferred_from)
      || !isAppUserIdArray(event.transferred_to)
      || (rawExpirationAtMs != null && !isTimestampMillis(rawExpirationAtMs))
    ) {
      return undefined;
    }

    return {
      appUserId: isNonEmptyString(event.app_user_id) ? event.app_user_id : undefined,
      eventTimestampMs: event.event_timestamp_ms,
      ...(rawExpirationAtMs != null ? { expirationAtMs: rawExpirationAtMs } : {}),
      id: event.id,
      kind: "transfer",
      transferredFrom: event.transferred_from,
      transferredTo: event.transferred_to,
      type: "TRANSFER",
    };
  }

  const entitlementIds = event.entitlement_ids;
  if (
    !isNonEmptyString(event.app_user_id)
    || !isStringArray(entitlementIds)
    || (rawExpirationAtMs != null && !isTimestampMillis(rawExpirationAtMs))
  ) {
    return undefined;
  }

  return {
    appUserId: event.app_user_id,
    entitlementIds,
    eventTimestampMs: event.event_timestamp_ms,
    ...(rawExpirationAtMs != null ? { expirationAtMs: rawExpirationAtMs } : {}),
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

function isStaleSubscriptionEvent(
  userData: Record<string, unknown> | undefined,
  eventTimestampMs: number,
  nextIsActive: boolean | undefined,
): boolean {
  const priorUpdatedAt = storedSubscriptionUpdatedAt(userData);
  return priorUpdatedAt !== undefined
    && (
      eventTimestampMs < priorUpdatedAt
      || (eventTimestampMs === priorUpdatedAt && nextIsActive !== false)
    );
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

  if (event.kind === "transfer") {
    // A RevenueCat alias transfer may list a user more than once. A destination
    // membership wins if a UID occurs in both arrays, leaving that account active.
    const transferTargets = new Map<string, boolean>();
    for (const userId of event.transferredFrom) {
      transferTargets.set(userId, false);
    }
    for (const userId of event.transferredTo) {
      transferTargets.set(userId, true);
    }
    const users = Array.from(transferTargets, ([userId, isActive]) => ({
      isActive,
      ref: dependencies.db.collection("users").doc(userId),
    }));

    await dependencies.db.runTransaction(async (transaction) => {
      const existingEvent = await transaction.get(eventRef);

      if (existingEvent.exists) {
        return "duplicate";
      }

      // Firestore transactions require all reads to finish before the first
      // write. The event record and every affected user must be read up front.
      const userSnapshots = await Promise.all(users.map(async (user) => ({
        ...user,
        snapshot: await transaction.get(user.ref),
      })));

      transaction.set(eventRef, eventRecord(event, receivedAt, updatedAt));

      for (const user of userSnapshots) {
        const userData = user.snapshot.data();
        if (isStaleSubscriptionEvent(userData, event.eventTimestampMs, user.isActive)) {
          continue;
        }

        const priorSubscription = userData && isRecord(userData.subscription) ? userData.subscription : undefined;
        const priorExpiresAt = priorSubscription?.expiresAt;
        const expiresAt = user.isActive && event.expirationAtMs !== undefined
          ? new Date(event.expirationAtMs).toISOString()
          : priorExpiresAt;

        transaction.set(user.ref, {
          subscription: {
            entitlement: "pro",
            isActive: user.isActive,
            updatedAt,
            ...(expiresAt !== undefined ? { expiresAt } : {}),
          },
        }, { merge: true });
      }

      return "processed";
    });

    response.status(200).send("ok");
    return;
  }

  const userRef = dependencies.db.collection("users").doc(event.appUserId);

  await dependencies.db.runTransaction(async (transaction) => {
    // Firestore requires every transaction read to complete before its first
    // write. Read both documents up front so the idempotency record cannot
    // make the entitlement read fail in production.
    const existingEvent = await transaction.get(eventRef);
    const user = await transaction.get(userRef);

    if (existingEvent.exists) {
      return "duplicate";
    }

    transaction.set(eventRef, eventRecord(event, receivedAt, updatedAt));

    const userData = user.data();
    const isActive = entitlementActivityForEvent(event);

    if (isStaleSubscriptionEvent(userData, event.eventTimestampMs, isActive)) {
      return "stale";
    }

    if (isActive === undefined) {
      return "processed";
    }

    const priorSubscription = userData && isRecord(userData.subscription) ? userData.subscription : undefined;
    const priorExpiresAt = priorSubscription?.expiresAt;
    const expiresAt = isActive === true && event.expirationAtMs !== undefined
      ? new Date(event.expirationAtMs).toISOString()
      : priorExpiresAt;

    transaction.set(userRef, {
      subscription: {
        entitlement: "pro",
        isActive,
        updatedAt,
        ...(expiresAt !== undefined ? { expiresAt } : {}),
      },
    }, { merge: true });

    return "processed";
  });

  response.status(200).send("ok");
}

export const handleRevenueCatWebhook = onRequest(
  { region: "us-central1", secrets: [revenueCatWebhookAuth] },
  async (request, response) => {
    await handleRevenueCatWebhookRequest(
      request,
      response,
      {
        db: getFirestore() as unknown as RevenueCatFirestore,
        expectedAuthorization: revenueCatWebhookAuth.value(),
      },
    );
  },
);
