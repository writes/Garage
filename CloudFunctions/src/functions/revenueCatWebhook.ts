import { timingSafeEqual } from "node:crypto";
import { getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  revenueCatAllowedEnvironments,
  revenueCatExpectedAppId,
  revenueCatExpectedStore,
  revenueCatWebhookAuth,
} from "../params";
import {
  CREDITS_PRODUCT_IDS,
  canonicalizeSource,
  foldReceiptCreditFact,
  isTimestampMillis,
  RECEIPT_CREDITS_PACK_DELTA,
  receiptCreditTransactionDocId,
  receiptCreditUidHash,
  type ReceiptCreditFact,
  type ReceiptCreditSource,
} from "./creditLedger";

type StandardRevenueCatEvent = {
  appUserId: string;
  appId?: string;
  cancelReason?: string;
  environment?: string;
  entitlementIds: string[];
  eventTimestampMs: number;
  expirationAtMs?: number;
  id: string;
  kind: "standard";
  productId?: string;
  quantity?: unknown;
  store?: string;
  transactionId?: string;
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
  creditSourceConfig?: {
    allowedEnvironments?: string;
    expectedAppId?: string;
    expectedStore?: string;
  };
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
  // A refund was reversed by the store — the entitlement is paid for again.
  "REFUND_REVERSED",
  // The store extended the current period; carries the new expiration.
  "SUBSCRIPTION_EXTENDED",
]);

/** No subscription SKU is lifetime; an empty allowlist prevents accidental perpetual Pro. */
const lifetimeGrantEventTypes = new Set<StandardRevenueCatEvent["type"]>();

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

  // RevenueCat's standard-event test payloads use null and some event variants omit this
  // field. Neither means the payload is malformed: they carry an empty entitlement set.
  const entitlementIds = event.entitlement_ids == null ? [] : event.entitlement_ids;
  if (
    !isNonEmptyString(event.app_user_id)
    || !isStringArray(entitlementIds)
    || (rawExpirationAtMs != null && !isTimestampMillis(rawExpirationAtMs))
  ) {
    return undefined;
  }

  return {
    appUserId: event.app_user_id,
    ...(typeof event.app_id === "string" ? { appId: event.app_id } : {}),
    ...(isNonEmptyString(event.cancel_reason) ? { cancelReason: event.cancel_reason } : {}),
    ...(typeof event.environment === "string" ? { environment: event.environment } : {}),
    entitlementIds,
    eventTimestampMs: event.event_timestamp_ms,
    ...(rawExpirationAtMs != null ? { expirationAtMs: rawExpirationAtMs } : {}),
    id: event.id,
    kind: "standard",
    ...(typeof event.product_id === "string" ? { productId: event.product_id } : {}),
    ...(event.quantity !== undefined ? { quantity: event.quantity } : {}),
    ...(typeof event.store === "string" ? { store: event.store } : {}),
    ...(typeof event.transaction_id === "string" ? { transactionId: event.transaction_id } : {}),
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
 * A voluntary cancellation only disables auto-renewal; the existing entitlement remains valid
 * until RevenueCat sends an EXPIRATION. A refund, however, arrives as CANCELLATION with
 * cancel_reason CUSTOMER_SUPPORT (RevenueCat has no REFUND event type) and revokes immediately —
 * the money was clawed back. BILLING_ISSUE and SUBSCRIPTION_PAUSED intentionally do not change
 * access (RevenueCat: keep access through the grace period / until the follow-up EXPIRATION).
 * Unknown events are recorded but do not change access.
 */
function entitlementActivityForEvent(event: StandardRevenueCatEvent): boolean | undefined {
  if (grantEventTypes.has(event.type)) {
    return event.entitlementIds.includes("pro") ? true : undefined;
  }

  if (event.type === "EXPIRATION") {
    return event.entitlementIds.includes("pro") ? false : undefined;
  }

  if (event.type === "CANCELLATION" && event.cancelReason === "CUSTOMER_SUPPORT") {
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

type CreditSourceConfig = {
  allowedEnvironments: Set<string>;
  expectedAppId: string;
  expectedStore: string;
};

type CreditSourceRejection = "environment_not_allowed" | "missing_source_fields" | "source_mismatch";

type CreditWebhookOutcome =
  | "applied"
  | "duplicate"
  | "invalid_ledger"
  | "rejected_quantity"
  | "rejected_source_config"
  | "tombstoned"
  | "unsupported_credits_event";

function isCreditsEvent(event: StandardRevenueCatEvent): boolean {
  return event.productId !== undefined && CREDITS_PRODUCT_IDS.has(event.productId);
}

function creditSourceFromEvent(event: StandardRevenueCatEvent): ReceiptCreditSource | undefined {
  if (
    !isNonEmptyString(event.appId)
    || !isNonEmptyString(event.store)
    || !isNonEmptyString(event.environment)
    || !isNonEmptyString(event.transactionId)
  ) {
    return undefined;
  }

  return {
    appId: event.appId,
    environment: event.environment,
    store: event.store,
    transactionId: event.transactionId,
  };
}

function configuredCreditSource(dependencies: RevenueCatWebhookDependencies): CreditSourceConfig | undefined {
  const configured = dependencies.creditSourceConfig ?? {
    allowedEnvironments: revenueCatAllowedEnvironments(),
    expectedAppId: revenueCatExpectedAppId(),
    expectedStore: revenueCatExpectedStore(),
  };
  if (
    !isNonEmptyString(configured.expectedAppId)
    || !isNonEmptyString(configured.expectedStore)
    || !isNonEmptyString(configured.allowedEnvironments)
  ) {
    return undefined;
  }

  const allowedEnvironments = new Set(
    configured.allowedEnvironments
      .split(",")
      .map((environment) => canonicalizeSource(environment, "environment"))
      .filter((environment) => environment.length > 0),
  );
  if (allowedEnvironments.size === 0) return undefined;

  return {
    allowedEnvironments,
    expectedAppId: canonicalizeSource(configured.expectedAppId, "appId"),
    expectedStore: canonicalizeSource(configured.expectedStore, "store"),
  };
}

function creditSourceRejection(
  source: ReceiptCreditSource | undefined,
  config: CreditSourceConfig,
): CreditSourceRejection | undefined {
  if (!source) return "missing_source_fields";
  if (!config.allowedEnvironments.has(canonicalizeSource(source.environment, "environment"))) {
    return "environment_not_allowed";
  }
  if (
    canonicalizeSource(source.appId, "appId") !== config.expectedAppId
    || canonicalizeSource(source.store, "store") !== config.expectedStore
  ) {
    return "source_mismatch";
  }
  return undefined;
}

function creditFactForEvent(event: StandardRevenueCatEvent, source: ReceiptCreditSource): ReceiptCreditFact | undefined {
  if (event.type === "NON_RENEWING_PURCHASE") {
    return { appUserId: event.appUserId, eventId: event.id, kind: "purchase", source, timestampMillis: event.eventTimestampMs };
  }
  if (event.type === "CANCELLATION") {
    return { appUserId: event.appUserId, eventId: event.id, kind: "refund", source, timestampMillis: event.eventTimestampMs };
  }
  if (event.type === "REFUND_REVERSED") {
    return { appUserId: event.appUserId, eventId: event.id, kind: "reversal", source, timestampMillis: event.eventTimestampMs };
  }
  return undefined;
}

function knownCreditBeneficiary(event: StandardRevenueCatEvent, pinnedBeneficiary: string | undefined): string | undefined {
  // A source/quantity-rejected purchase still identifies its prospective beneficiary. A refund or
  // reversal never does: using its alias here would defeat the beneficiary-hash deletion purge.
  return pinnedBeneficiary ?? (event.type === "NON_RENEWING_PURCHASE" ? event.appUserId : undefined);
}

function creditEventRecord(
  event: StandardRevenueCatEvent,
  receivedAt: string,
  updatedAt: string,
  options: {
    beneficiaryUid?: string;
    creditTxnDocId?: string;
    disposition: string;
  },
): Record<string, unknown> {
  return {
    ...eventRecord(event, receivedAt, updatedAt),
    ...(options.beneficiaryUid ? { beneficiaryUidHash: receiptCreditUidHash(options.beneficiaryUid) } : {}),
    ...(options.creditTxnDocId ? { creditTxnDocId: options.creditTxnDocId } : {}),
    disposition: options.disposition,
    ...(event.environment !== undefined ? { environment: event.environment } : {}),
    packDelta: RECEIPT_CREDITS_PACK_DELTA,
    productId: event.productId,
    ...(event.store !== undefined ? { store: event.store } : {}),
  };
}

async function recordRejectedCreditSource(
  event: StandardRevenueCatEvent,
  source: ReceiptCreditSource | undefined,
  eventRef: DocumentReferenceLike,
  dependencies: RevenueCatWebhookDependencies,
  receivedAt: string,
  updatedAt: string,
): Promise<"duplicate" | "rejected_source_config" | "tombstoned"> {
  const creditTxnDocId = source ? receiptCreditTransactionDocId(source) : undefined;
  return dependencies.db.runTransaction(async (transaction) => {
    const existingEvent = await transaction.get(eventRef);
    if (existingEvent.exists && existingEvent.data()?.disposition !== "rejected_source_config") {
      return "duplicate";
    }

    // Even a source-config rejection must not recreate an event record after account deletion.
    // When addressing material exists, read its ledger before tombstones so an alias refund also
    // checks the purchase-pinned beneficiary; a malformed/missing source can only check incoming.
    const existingTxn = creditTxnDocId
      ? await transaction.get(dependencies.db.collection("receipt_credit_txns").doc(creditTxnDocId))
      : undefined;
    const storedBeneficiary = existingTxn?.data()?.uid;
    const pinnedBeneficiary = isNonEmptyString(storedBeneficiary) ? storedBeneficiary : undefined;
    const tombstoneUserIds = Array.from(new Set([event.appUserId, pinnedBeneficiary].filter(isNonEmptyString)));
    const tombstones = await Promise.all(tombstoneUserIds.map(async (uid) => transaction.get(
      dependencies.db.collection("deleted_users").doc(receiptCreditUidHash(uid)),
    )));
    if (
      event.appUserId === "__deleted__"
      || pinnedBeneficiary === "__deleted__"
      || tombstones.some((snapshot) => snapshot.exists)
    ) {
      return "tombstoned";
    }

    transaction.set(eventRef, creditEventRecord(event, receivedAt, updatedAt, {
      beneficiaryUid: knownCreditBeneficiary(event, pinnedBeneficiary),
      creditTxnDocId,
      disposition: "rejected_source_config",
    }));
    return "rejected_source_config";
  });
}

/**
 * Processes the consumable ledger in a transaction deliberately isolated from subscription state.
 * This keeps credit refunds alias-safe and guarantees a credits+pro payload cannot write Pro.
 */
async function handleReceiptCreditsEvent(
  event: StandardRevenueCatEvent,
  eventRef: DocumentReferenceLike,
  dependencies: RevenueCatWebhookDependencies,
  receivedAt: string,
  updatedAt: string,
): Promise<CreditWebhookOutcome | "webhook_config_unset"> {
  const config = configuredCreditSource(dependencies);
  if (!config) return "webhook_config_unset";

  const source = creditSourceFromEvent(event);
  const rejection = creditSourceRejection(source, config);
  if (rejection) {
    const outcome = await recordRejectedCreditSource(
      event,
      source,
      eventRef,
      dependencies,
      receivedAt,
      updatedAt,
    );
    if (outcome === "rejected_source_config") {
      const log = rejection === "environment_not_allowed" ? logger.warn : logger.error;
      log("revenuecat receipt-credit source rejected", { eventId: event.id, eventType: event.type, rejection });
    } else if (outcome === "tombstoned") {
      logger.warn("revenuecat receipt-credit ignored for deleted user", { eventId: event.id, eventType: event.type });
    }
    return outcome;
  }

  // `creditSourceRejection` only accepts a source after all four components are present.
  const acceptedSource = source as ReceiptCreditSource;
  if (canonicalizeSource(acceptedSource.environment, "environment") === "SANDBOX") {
    // Production deliberately accepts App Review/TestFlight sandbox transactions; retain an
    // explicit operational signal because this is bounded but not the normal revenue path.
    logger.warn("revenuecat receipt-credit sandbox transaction accepted", {
      eventId: event.id,
      eventType: event.type,
    });
  }
  const creditTxnDocId = receiptCreditTransactionDocId(acceptedSource);
  const txnRef = dependencies.db.collection("receipt_credit_txns").doc(creditTxnDocId);
  const fact = creditFactForEvent(event, acceptedSource);
  const quantityAccepted = event.quantity === undefined || event.quantity === 1;

  const outcome = await dependencies.db.runTransaction(async (transaction) => {
    // Every possible read happens before the first write. In particular the ledger precedes
    // tombstones so a refund alias cannot conceal the purchase-pinned beneficiary.
    const existingEvent = await transaction.get(eventRef);
    if (existingEvent.exists && existingEvent.data()?.disposition !== "rejected_source_config") {
      return "duplicate" as const;
    }

    const existingTxn = await transaction.get(txnRef);
    const existingLedger = existingTxn.data();
    const pinnedBeneficiary = isNonEmptyString(existingLedger?.uid) ? existingLedger.uid : undefined;
    const tombstoneUserIds = Array.from(new Set([event.appUserId, pinnedBeneficiary].filter(isNonEmptyString)));
    const tombstones = await Promise.all(tombstoneUserIds.map(async (uid) => ({
      snapshot: await transaction.get(dependencies.db.collection("deleted_users").doc(receiptCreditUidHash(uid))),
      uid,
    })));

    if (
      event.appUserId === "__deleted__"
      || pinnedBeneficiary === "__deleted__"
      || tombstones.some(({ snapshot }) => snapshot.exists)
    ) {
      return "tombstoned" as const;
    }

    if (!quantityAccepted) {
      transaction.set(eventRef, creditEventRecord(event, receivedAt, updatedAt, {
        beneficiaryUid: knownCreditBeneficiary(event, pinnedBeneficiary),
        creditTxnDocId,
        disposition: "rejected_quantity",
      }));
      return "rejected_quantity" as const;
    }

    if (!fact) {
      transaction.set(eventRef, creditEventRecord(event, receivedAt, updatedAt, {
        beneficiaryUid: pinnedBeneficiary,
        creditTxnDocId,
        disposition: "unsupported_credits_event",
      }));
      return "unsupported_credits_event" as const;
    }

    // A purchase is the only fact allowed to establish the beneficiary. Refund/reversal facts
    // use the ledger's existing pin, never their incoming alias.
    const beneficiaryForQuota = fact.kind === "purchase"
      ? pinnedBeneficiary ?? event.appUserId
      : pinnedBeneficiary;
    const quotaSnapshot = beneficiaryForQuota
      ? await transaction.get(dependencies.db.collection("usage_quotas").doc(`${beneficiaryForQuota}_receipt_credits`))
      : undefined;
    const folded = foldReceiptCreditFact(existingLedger, quotaSnapshot?.data(), fact);
    if (folded.kind === "invalid") return { kind: "invalid_ledger" as const, reason: folded.reason };

    const beneficiaryUid = folded.ledger.uid;
    transaction.set(eventRef, creditEventRecord(event, receivedAt, updatedAt, {
      beneficiaryUid,
      creditTxnDocId,
      disposition: "applied",
    }));
    transaction.set(txnRef, folded.ledger);
    if (folded.kind === "applied") {
      transaction.set(
        dependencies.db.collection("usage_quotas").doc(`${folded.quota.uid}_receipt_credits`),
        folded.quota,
        { merge: true },
      );
    }
    return { kind: "applied" as const };
  });

  if (outcome === "tombstoned") {
    // Deliberately metadata-only: writing an event record after account purge recreates user data.
    logger.warn("revenuecat receipt-credit ignored for deleted user", { eventId: event.id, eventType: event.type });
    return outcome;
  }
  if (outcome === "rejected_quantity") {
    logger.error("revenuecat receipt-credit quantity rejected", { eventId: event.id, eventType: event.type });
    return outcome;
  }
  if (outcome === "unsupported_credits_event") {
    logger.error("revenuecat receipt-credit event type unsupported", { eventId: event.id, eventType: event.type });
    return outcome;
  }
  if (typeof outcome === "object") {
    if (outcome.kind === "invalid_ledger") {
      logger.error("revenuecat receipt-credit ledger rejected", {
        eventId: event.id,
        eventType: event.type,
        reason: outcome.reason,
      });
    }
    return outcome.kind;
  }
  return outcome;
}

export async function handleRevenueCatWebhookRequest(
  request: RevenueCatWebhookRequest,
  response: RevenueCatWebhookResponse,
  dependencies: RevenueCatWebhookDependencies,
): Promise<void> {
  const expectedAuthorization = dependencies.expectedAuthorization;

  if (!expectedAuthorization || expectedAuthorization.trim().length === 0) {
    logger.error("revenuecat webhook rejected: authorization secret not configured");
    response.status(503).send("RevenueCat webhook authorization is not configured.");
    return;
  }

  const authorizationHeader = request.header("Authorization");

  if (!isAuthorizedRequest(authorizationHeader, expectedAuthorization)) {
    // Config drift or a probe. Never log the header value itself.
    logger.warn("revenuecat webhook rejected: bad authorization", {
      hasAuthorizationHeader: authorizationHeader !== undefined,
    });
    response.status(401).send("Unauthorized.");
    return;
  }

  // RevenueCat's "Send test event" button posts type: "TEST" with entitlement_ids: null, which
  // the parser below rightly rejects (every non-TRANSFER event needs a string array there).
  // Answering 400 makes the dashboard's connectivity test permanently red and makes RevenueCat
  // treat each ping as a failed delivery worth retrying. A TEST event carries no entitlement to
  // act on, so acknowledge it and do nothing. This runs AFTER the authorization check, so it is
  // not an unauthenticated bypass.
  const requestBody = request.body;
  const testEventType = isRecord(requestBody) && isRecord(requestBody.event)
    ? requestBody.event.type
    : undefined;
  if (testEventType === "TEST") {
    logger.info("revenuecat webhook: test event acknowledged, nothing to apply");
    response.status(200).send("ok");
    return;
  }

  const event = parseRevenueCatEvent(request.body);
  if (!event) {
    const body = request.body;
    const rawEvent = isRecord(body) && isRecord(body.event) ? body.event : undefined;
    logger.warn("revenuecat webhook rejected: unparseable event", {
      eventId: rawEvent && isNonEmptyString(rawEvent.id) ? rawEvent.id : undefined,
      eventType: rawEvent && isNonEmptyString(rawEvent.type) ? rawEvent.type : undefined,
    });
    response.status(400).send("Invalid RevenueCat event.");
    return;
  }

  const eventRef = dependencies.db.collection("revenuecat_events").doc(event.id);
  const updatedAt = new Date(event.eventTimestampMs).toISOString();
  const receivedAt = (dependencies.now ?? (() => new Date()))().toISOString();

  // Exact product membership routes a consumable before the subscription path. A RevenueCat
  // payload may include the Pro entitlement alongside a credit purchase; it is never authority
  // to write subscription state from this branch.
  if (event.kind === "standard" && isCreditsEvent(event)) {
    if (event.entitlementIds.includes("pro")) {
      logger.error("revenuecat receipt-credit event carried pro entitlement; subscription write skipped", {
        eventId: event.id,
        eventType: event.type,
      });
    }

    const outcome = await handleReceiptCreditsEvent(event, eventRef, dependencies, receivedAt, updatedAt);
    if (outcome === "webhook_config_unset") {
      logger.error("revenuecat receipt-credit webhook unavailable: source config unset", {
        eventId: event.id,
        eventType: event.type,
      });
      response.status(503).send("Receipt-credit webhook source configuration is not configured.");
      return;
    }
    if (outcome === "invalid_ledger") {
      // Checked arithmetic/invariant failures must remain retryable and create no forensic event
      // record, because any write could falsely make a later repaired delivery look duplicate.
      response.status(503).send("Receipt-credit ledger could not be safely applied.");
      return;
    }
    logger.info("revenuecat receipt-credit webhook handled", {
      eventId: event.id,
      eventType: event.type,
      outcome,
    });
    response.status(200).send("ok");
    return;
  }

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
      userId,
    }));

    const transferResult = await dependencies.db.runTransaction(async (transaction) => {
      const existingEvent = await transaction.get(eventRef);

      // A recorded event whose destination grant was SKIPPED (no expiration available) stays
      // retryable: a RevenueCat-dashboard re-send can repair the grant once the destination has
      // an expiry source (e.g. a support-granted entitlement), instead of dead-ending on
      // "duplicate" while a paying subscriber has no server-side Pro.
      const priorSkips = existingEvent.exists ? existingEvent.data()?.grantSkippedUserIds : undefined;
      const retryableSkip = Array.isArray(priorSkips) && priorSkips.length > 0;
      if (existingEvent.exists && !retryableSkip) {
        return { outcome: "duplicate", skippedUserIds: [] as string[] };
      }

      // Firestore transactions require all reads to finish before the first
      // write. The event record and every affected user must be read up front.
      const userSnapshots = await Promise.all(users.map(async (user) => ({
        ...user,
        snapshot: await transaction.get(user.ref),
      })));

      const skippedUserIds: string[] = [];
      const userWrites: Array<{ ref: DocumentReferenceLike; data: Record<string, unknown> }> = [];
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

        // TRANSFER events document no expiration. Granting a destination open-ended access would
        // be perpetual server-side Pro; fail closed instead. The skip marker above keeps the
        // event retryable, and the operator follow-up (RevenueCat REST lookup with the secret
        // key) is the durable heal; until then the next expiry-bearing event restores the grant.
        if (user.isActive && expiresAt === undefined) {
          skippedUserIds.push(user.userId);
          continue;
        }

        userWrites.push({
          ref: user.ref,
          data: {
            subscription: {
              entitlement: "pro",
              isActive: user.isActive,
              updatedAt,
              ...(expiresAt !== undefined ? { expiresAt } : {}),
            },
          },
        });
      }

      transaction.set(eventRef, {
        ...eventRecord(event, receivedAt, updatedAt),
        ...(skippedUserIds.length > 0 ? { grantSkippedUserIds: skippedUserIds } : {}),
      });
      for (const write of userWrites) {
        transaction.set(write.ref, write.data, { merge: true });
      }

      return { outcome: retryableSkip ? "reprocessed_after_skip" : "processed", skippedUserIds };
    });

    if (transferResult.skippedUserIds.length > 0) {
      // error (not warn): a paying subscriber just lost server-side Pro until an expiry-bearing
      // event arrives — this should page whoever watches the logs.
      logger.error("revenuecat transfer grant skipped: no expiration available", {
        eventId: event.id,
        skippedUserIds: transferResult.skippedUserIds,
      });
    }
    logger.info("revenuecat webhook handled", {
      eventId: event.id,
      eventType: event.type,
      outcome: transferResult.outcome,
    });
    response.status(200).send("ok");
    return;
  }

  const userRef = dependencies.db.collection("users").doc(event.appUserId);

  const outcome = await dependencies.db.runTransaction(async (transaction) => {
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

    // A subscription grant with no expiration anywhere would become perpetual server-side Pro
    // (userHasActiveProEntitlement treats a missing expiresAt as lifetime). No lifetime
    // subscription SKU exists, so every no-expiration grant fails closed.
    if (isActive === true && expiresAt === undefined && !lifetimeGrantEventTypes.has(event.type)) {
      return "skipped_no_expiration";
    }

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

  if (outcome === "skipped_no_expiration") {
    logger.error("revenuecat grant skipped: subscription grant carried no expiration", {
      appUserId: event.appUserId,
      eventId: event.id,
      eventType: event.type,
    });
  }
  logger.info("revenuecat webhook handled", {
    appUserId: event.appUserId,
    eventId: event.id,
    eventType: event.type,
    outcome,
  });
  response.status(200).send("ok");
}

export const handleRevenueCatWebhook = onRequest(
  {
    region: "us-central1",
    secrets: [revenueCatWebhookAuth],
    // Explicit rather than relying on the onRequest default. The first deploy to each project
    // failed at its IAM step ("We failed to modify the IAM policy for the project"), so the
    // public invoker binding was never applied and Cloud Run rejected every RevenueCat POST at
    // the edge with 401 "Authorization header lacked OIDC mandated 'Bearer' prefix" — the
    // request never reached this function at all. Declaring it here makes each deploy reconcile
    // the binding instead of depending on a step that already silently failed once.
    //
    // "public" is correct, not a weakening: RevenueCat (like any third-party webhook sender)
    // cannot mint Google OIDC tokens. Authentication is this function's own timing-safe
    // comparison against REVENUECAT_WEBHOOK_AUTH below, which fails CLOSED with a 503 when the
    // secret is unset rather than accepting unauthenticated events.
    invoker: "public",
  },
  async (request, response) => {
    await handleRevenueCatWebhookRequest(
      request,
      response,
      {
        db: getFirestore() as unknown as RevenueCatFirestore,
        creditSourceConfig: {
          allowedEnvironments: revenueCatAllowedEnvironments(),
          expectedAppId: revenueCatExpectedAppId(),
          expectedStore: revenueCatExpectedStore(),
        },
        expectedAuthorization: revenueCatWebhookAuth.value(),
      },
    );
  },
);
