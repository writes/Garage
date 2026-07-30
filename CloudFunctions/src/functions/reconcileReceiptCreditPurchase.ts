import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  revenueCatAllowedEnvironments,
  revenueCatExpectedAppId,
  revenueCatExpectedStore,
  revenueCatProjectId,
  revenueCatSecretApiKey,
} from "../params";
import { QuotaFirestore, safeQuotaCount } from "./claudeProxy";
import {
  CREDITS_PRODUCT_IDS,
  canonicalizeSource,
  foldReceiptCreditFact,
  isTimestampMillis,
  receiptCreditTransactionDocId,
  receiptCreditUidHash,
  type ReceiptCreditSource,
} from "./creditLedger";
import { ReceiptQuotaSnapshot, receiptQuotaSnapshotForUser } from "./receiptQuota";

const RECONCILE_DAILY_LIMIT = 10;
const REVENUECAT_API_ROOT = "https://api.revenuecat.com/v2";

export type ReconcileReceiptCreditPurchaseRequest = { auth?: { uid: string } | null; data?: unknown };

export type ReconcileReceiptCreditPurchaseDependencies = {
  creditSourceConfig?: {
    allowedEnvironments?: string;
    expectedAppId?: string;
    expectedStore?: string;
  };
  db: QuotaFirestore;
  fetchImpl?: typeof fetch;
  now?: () => Date;
  projectId?: string;
  revenueCatSecretApiKey?: string;
};

export type ReconcileReceiptCreditPurchaseResponse = {
  transactionState: "granted" | "refunded" | "unknown";
  quota: ReceiptQuotaSnapshot;
};

type CreditSourceConfig = {
  allowedEnvironments: Set<string>;
  expectedAppId: string;
  expectedStore: string;
};

type ResolvedPurchase = {
  source: ReceiptCreditSource;
  purchasedAtMillis: number;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function transactionIdFromData(data: unknown): string {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "transactionId must be a string.");
  }
  const transactionId = data.transactionId;
  if (typeof transactionId !== "string" || transactionId.trim().length === 0 || transactionId.trim().length > 255) {
    throw new HttpsError("invalid-argument", "transactionId must be a non-empty string of at most 255 characters.");
  }
  return transactionId.trim();
}

function sourceConfig(dependencies: ReconcileReceiptCreditPurchaseDependencies): CreditSourceConfig | undefined {
  const configured = dependencies.creditSourceConfig ?? {
    allowedEnvironments: revenueCatAllowedEnvironments(),
    expectedAppId: revenueCatExpectedAppId(),
    expectedStore: revenueCatExpectedStore(),
  };
  if (
    typeof configured.allowedEnvironments !== "string"
    || typeof configured.expectedAppId !== "string"
    || typeof configured.expectedStore !== "string"
    || configured.expectedAppId.trim().length === 0
    || configured.expectedStore.trim().length === 0
  ) return undefined;
  const allowedEnvironments = new Set(configured.allowedEnvironments
    .split(",")
    .map((value) => canonicalizeSource(value, "environment"))
    .filter((value) => value.length > 0));
  if (allowedEnvironments.size === 0) return undefined;
  return {
    allowedEnvironments,
    expectedAppId: canonicalizeSource(configured.expectedAppId, "appId"),
    expectedStore: canonicalizeSource(configured.expectedStore, "store"),
  };
}

function retryAfterSeconds(response: Response, now: Date): number | undefined {
  const value = response.headers.get("Retry-After");
  if (!value) return undefined;
  const seconds = Number(value);
  if (Number.isFinite(seconds) && seconds >= 0) return Math.ceil(seconds);
  const dateMillis = Date.parse(value);
  return Number.isNaN(dateMillis) ? undefined : Math.max(0, Math.ceil((dateMillis - now.getTime()) / 1_000));
}

function unavailable(message: string, response?: Response, now = new Date()): HttpsError {
  const retryAfter = response ? retryAfterSeconds(response, now) : undefined;
  return new HttpsError("unavailable", message, retryAfter === undefined ? undefined : { retryAfterSeconds: retryAfter });
}

function notFound(): HttpsError {
  // The uniform message deliberately avoids turning the callable into a transaction-existence oracle.
  return new HttpsError("not-found", "Receipt-credit purchase was not found.");
}

async function responseJson(response: Response, now: Date): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    throw unavailable("RevenueCat purchase lookup returned malformed data.", response, now);
  }
}

async function requireSuccess(response: Response, now: Date): Promise<void> {
  if (response.ok) return;
  if (response.status === 404) throw notFound();
  // A 429, 5xx, timeout, and malformed response are retryable `unavailable`. Other HTTP failures
  // are also not provenance evidence; fail closed rather than classifying a remote outage as miss.
  throw unavailable("RevenueCat purchase lookup is unavailable.", response, now);
}

/**
 * RC v2 supports a transaction-addressed purchase search. The result only exposes the RC product
 * id, so we resolve it through the v2 product endpoint before granting a store identifier.
 */
async function resolveRevenueCatPurchase(
  transactionId: string,
  uid: string,
  config: CreditSourceConfig,
  projectId: string,
  secret: string,
  fetchImpl: typeof fetch,
  now: Date,
): Promise<ResolvedPurchase> {
  let lookupResponse: Response;
  try {
    lookupResponse = await fetchImpl(
      `${REVENUECAT_API_ROOT}/projects/${encodeURIComponent(projectId)}/purchases?store_purchase_identifier=${encodeURIComponent(transactionId)}`,
      {
        headers: { Authorization: `Bearer ${secret}` },
        signal: AbortSignal.timeout(15_000),
      },
    );
  } catch {
    throw unavailable("RevenueCat purchase lookup is unavailable.");
  }
  await requireSuccess(lookupResponse, now);
  const payload = await responseJson(lookupResponse, now);
  const items = isRecord(payload) && Array.isArray(payload.items) ? payload.items : undefined;
  if (!items) throw unavailable("RevenueCat purchase lookup returned malformed data.");
  if (items.length === 0 || items.length > 1) throw notFound();
  if (!isRecord(items[0])) throw unavailable("RevenueCat purchase lookup returned malformed data.");
  const purchase = items[0];

  if (
    typeof purchase.customer_id !== "string"
    || typeof purchase.original_customer_id !== "string"
    || typeof purchase.product_id !== "string"
    || typeof purchase.store_purchase_identifier !== "string"
    || typeof purchase.store !== "string"
    || typeof purchase.environment !== "string"
    || typeof purchase.status !== "string"
    || !isTimestampMillis(purchase.purchased_at)
  ) {
    throw unavailable("RevenueCat purchase lookup returned malformed data.");
  }
  if (
    purchase.store_purchase_identifier !== transactionId
    || purchase.customer_id !== uid
    || purchase.original_customer_id !== uid
    || purchase.status !== "owned"
    || (purchase.quantity !== undefined && purchase.quantity !== 1)
  ) {
    throw notFound();
  }

  let productResponse: Response;
  try {
    productResponse = await fetchImpl(
      `${REVENUECAT_API_ROOT}/projects/${encodeURIComponent(projectId)}/products/${encodeURIComponent(purchase.product_id)}`,
      {
        headers: { Authorization: `Bearer ${secret}` },
        signal: AbortSignal.timeout(15_000),
      },
    );
  } catch {
    throw unavailable("RevenueCat product lookup is unavailable.");
  }
  await requireSuccess(productResponse, now);
  const product = await responseJson(productResponse, now);
  if (!isRecord(product) || typeof product.store_identifier !== "string" || typeof product.app_id !== "string") {
    throw unavailable("RevenueCat product lookup returned malformed data.");
  }
  if (
    !CREDITS_PRODUCT_IDS.has(product.store_identifier)
    || canonicalizeSource(product.app_id, "appId") !== config.expectedAppId
    || canonicalizeSource(purchase.store, "store") !== config.expectedStore
    || !config.allowedEnvironments.has(canonicalizeSource(purchase.environment, "environment"))
  ) {
    throw notFound();
  }
  return {
    source: {
      appId: product.app_id,
      store: purchase.store,
      environment: purchase.environment,
      transactionId,
    },
    purchasedAtMillis: purchase.purchased_at,
  };
}

function dailyBucketId(uid: string, now: Date): string {
  return `${uid}_receipt_credit_reconcile_${now.toISOString().slice(0, 10)}`;
}

async function consumeReconcileRateLimit(
  db: QuotaFirestore,
  uid: string,
  now: Date,
): Promise<"admitted" | "tombstoned" | "limited"> {
  const tombstoneRef = db.collection("deleted_users").doc(receiptCreditUidHash(uid));
  const quotaRef = db.collection("usage_quotas").doc(dailyBucketId(uid, now));
  return db.runTransaction(async (transaction) => {
    const tombstone = await transaction.get(tombstoneRef);
    const quota = await transaction.get(quotaRef);
    if (tombstone.exists) return "tombstoned";
    const count = quota.exists ? safeQuotaCount(quota.data()?.count) : 0;
    if (count >= RECONCILE_DAILY_LIMIT) return "limited";
    transaction.set(quotaRef, {
      uid,
      kind: "receipt_credit_reconcile_daily",
      count: count + 1,
      updatedAt: now.toISOString(),
    }, { merge: true });
    return "admitted";
  });
}

function ledgerTransactionState(ledger: Record<string, unknown>): "granted" | "refunded" | "unknown" {
  const refundAtMillis = typeof ledger.refundAtMillis === "number" ? ledger.refundAtMillis : undefined;
  const reversalAtMillis = typeof ledger.reversalAtMillis === "number" ? ledger.reversalAtMillis : undefined;
  if (refundAtMillis !== undefined && (reversalAtMillis === undefined || reversalAtMillis < refundAtMillis)) return "refunded";
  return ledger.grantApplied === true ? "granted" : "unknown";
}

async function foldReconciledPurchase(
  db: QuotaFirestore,
  uid: string,
  resolved: ResolvedPurchase,
  transactionId: string,
): Promise<"granted" | "refunded" | "unknown"> {
  const transactionRef = db.collection("receipt_credit_txns").doc(receiptCreditTransactionDocId(resolved.source));
  const callerTombstoneRef = db.collection("deleted_users").doc(receiptCreditUidHash(uid));
  return db.runTransaction(async (transaction) => {
    // The ledger read precedes both tombstone reads so an existing beneficiary is included in the
    // deletion check. Every document read completes before the fold writes.
    const existingTransaction = await transaction.get(transactionRef);
    const existingLedger = existingTransaction.data();
    const pinnedBeneficiary = typeof existingLedger?.uid === "string" ? existingLedger.uid : undefined;
    const callerTombstone = await transaction.get(callerTombstoneRef);
    const beneficiaryTombstone = pinnedBeneficiary && pinnedBeneficiary !== uid
      ? await transaction.get(db.collection("deleted_users").doc(receiptCreditUidHash(pinnedBeneficiary)))
      : undefined;
    if (
      callerTombstone.exists
      || beneficiaryTombstone?.exists
      || pinnedBeneficiary === "__deleted__"
      || (pinnedBeneficiary !== undefined && pinnedBeneficiary !== uid)
    ) {
      throw notFound();
    }
    const creditsRef = db.collection("usage_quotas").doc(`${uid}_receipt_credits`);
    const existingCredits = await transaction.get(creditsRef);
    const folded = foldReceiptCreditFact(existingLedger, existingCredits.data(), {
      appUserId: uid,
      eventId: `reconcile:${transactionId}`,
      kind: "purchase",
      source: resolved.source,
      timestampMillis: resolved.purchasedAtMillis,
    });
    if (folded.kind === "invalid") {
      throw new HttpsError("failed-precondition", "Receipt-credit ledger could not accept this purchase.");
    }
    transaction.set(transactionRef, folded.ledger);
    if (folded.kind === "applied") transaction.set(creditsRef, folded.quota, { merge: true });
    return ledgerTransactionState(folded.ledger);
  });
}

export async function reconcileReceiptCreditPurchaseRequest(
  request: ReconcileReceiptCreditPurchaseRequest,
  dependencies: ReconcileReceiptCreditPurchaseDependencies,
): Promise<ReconcileReceiptCreditPurchaseResponse> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in.");
  const transactionId = transactionIdFromData(request.data);
  const secret = (dependencies.revenueCatSecretApiKey ?? "").trim();
  const projectId = (dependencies.projectId ?? "").trim();
  const config = sourceConfig(dependencies);
  if (!secret || !projectId || !config) {
    throw new HttpsError("unavailable", "Receipt-credit reconciliation is not configured.");
  }
  const now = (dependencies.now ?? (() => new Date()))();
  const rate = await consumeReconcileRateLimit(dependencies.db, request.auth.uid, now);
  if (rate === "tombstoned") throw notFound();
  if (rate === "limited") {
    throw new HttpsError("resource-exhausted", "Receipt-credit reconciliation rate limit exceeded.");
  }
  const resolved = await resolveRevenueCatPurchase(
    transactionId,
    request.auth.uid,
    config,
    projectId,
    secret,
    dependencies.fetchImpl ?? fetch,
    now,
  );
  const transactionState = await foldReconciledPurchase(dependencies.db, request.auth.uid, resolved, transactionId);
  const quota = await receiptQuotaSnapshotForUser(dependencies.db, request.auth.uid, now);
  return { transactionState, quota };
}

export const reconcileReceiptCreditPurchase = onCall(
  { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 30, secrets: [revenueCatSecretApiKey] },
  async (request): Promise<ReconcileReceiptCreditPurchaseResponse> => reconcileReceiptCreditPurchaseRequest(request, {
    db: getFirestore() as unknown as QuotaFirestore,
    fetchImpl: fetch,
    projectId: revenueCatProjectId(),
    revenueCatSecretApiKey: revenueCatSecretApiKey.value() || process.env.REVENUECAT_SECRET_API_KEY,
  }),
);
