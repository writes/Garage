import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { QuotaFirestore, userHasActiveProEntitlement } from "./claudeProxy";
import {
  canonicalizeSource,
  receiptCreditTransactionDocId,
} from "./creditLedger";
import {
  ReceiptQuotaSnapshot,
  compositeReceiptQuotaSnapshot,
  quotaBucketState,
  receiptCreditQuotaConfiguration,
  receiptQuotaConfiguration,
  sweepExpiredReceiptReservations,
} from "./receiptQuota";
import {
  revenueCatAllowedEnvironments,
  revenueCatExpectedAppId,
  revenueCatExpectedStore,
} from "../params";

export type ReceiptQuotaStatusRequest = { auth?: { uid: string } | null; data?: unknown };

export type ReceiptQuotaStatusDependencies = {
  creditSourceConfig?: {
    allowedEnvironments?: string;
    expectedAppId?: string;
    expectedStore?: string;
  };
  db: QuotaFirestore;
  now?: () => Date;
};

export type ReceiptQuotaStatusResponse = ReceiptQuotaSnapshot & {
  creditsPurchasingEnabled: boolean;
  sweepIncomplete: boolean;
  transactionState?: "granted" | "refunded" | "unknown";
};

type CandidateSourceConfig = {
  allowedEnvironments: string[];
  expectedAppId: string;
  expectedStore: string;
};

function transactionIdFromData(data: unknown): string | undefined {
  if (data === undefined || data === null) return undefined;
  if (typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "transactionId must be a string.");
  }
  const transactionId = (data as Record<string, unknown>).transactionId;
  if (transactionId === undefined) return undefined;
  if (typeof transactionId !== "string" || transactionId.trim().length === 0 || transactionId.trim().length > 255) {
    throw new HttpsError("invalid-argument", "transactionId must be a non-empty string of at most 255 characters.");
  }
  return transactionId.trim();
}

function candidateSourceConfig(dependencies: ReceiptQuotaStatusDependencies): CandidateSourceConfig | undefined {
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
  const allowedEnvironments = [...new Set(configured.allowedEnvironments
    .split(",")
    .map((environment) => canonicalizeSource(environment, "environment"))
    .filter((environment) => environment.length > 0))];
  if (allowedEnvironments.length === 0) return undefined;
  return {
    allowedEnvironments,
    expectedAppId: canonicalizeSource(configured.expectedAppId, "appId"),
    expectedStore: canonicalizeSource(configured.expectedStore, "store"),
  };
}

function ledgerTransactionState(data: Record<string, unknown> | undefined): "granted" | "refunded" | "unknown" {
  const refundAtMillis = typeof data?.refundAtMillis === "number" ? data.refundAtMillis : undefined;
  const reversalAtMillis = typeof data?.reversalAtMillis === "number" ? data.reversalAtMillis : undefined;
  const refundEffective = refundAtMillis !== undefined
    && (reversalAtMillis === undefined || reversalAtMillis < refundAtMillis);
  if (refundEffective) return "refunded";
  return data?.grantApplied === true ? "granted" : "unknown";
}

function purchasingEnabled(data: Record<string, unknown> | undefined, now: Date): boolean {
  return data?.purchasingEnabled === true
    && typeof data.expiresAtMillis === "number"
    && Number.isFinite(data.expiresAtMillis)
    && data.expiresAtMillis > now.getTime();
}

export async function receiptQuotaStatusRequest(
  request: ReceiptQuotaStatusRequest,
  dependencies: ReceiptQuotaStatusDependencies,
): Promise<ReceiptQuotaStatusResponse> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in.");
  const uid = request.auth.uid;
  const now = (dependencies.now ?? (() => new Date()))();
  const requestedTransactionId = transactionIdFromData(request.data);

  // Status is the convergence owner. Each bounded sweep transaction consumes at most one ten-token
  // page. Its final snapshot is deliberately read-only: Sol-final-1 pins its explicit read order
  // through optional transaction candidates and nothing else.
  let sweepIncomplete = false;
  for (let round = 0; round < 10; round += 1) {
    sweepIncomplete = await sweepExpiredReceiptReservations(dependencies.db, uid, now);
    if (!sweepIncomplete) break;
  }

  return dependencies.db.runTransaction(async (transaction) => {
    // Required read order: user -> current base buckets -> both credits docs -> capability config
    // -> all possible transaction candidates. The expiry pages were drained before this final
    // snapshot, so there are no more reads or writes after this sequence.
    const user = await transaction.get(dependencies.db.collection("users").doc(uid));
    const entitlement = userHasActiveProEntitlement(user.data(), now) ? "pro" : "free";
    const base = receiptQuotaConfiguration(uid, entitlement, now);
    const creditsConfiguration = receiptCreditQuotaConfiguration(uid, entitlement);
    const baseScanRef = dependencies.db.collection("usage_quotas").doc(base.scanBucketId);
    const baseConfirmedRef = dependencies.db.collection("usage_quotas").doc(base.confirmedBucketId);
    const creditsRef = dependencies.db.collection("usage_quotas").doc(creditsConfiguration.confirmedBucketId);
    const creditScansRef = dependencies.db.collection("usage_quotas").doc(creditsConfiguration.scanBucketId);
    const baseScan = quotaBucketState(baseScanRef, await transaction.get(baseScanRef));
    const baseConfirmed = quotaBucketState(baseConfirmedRef, await transaction.get(baseConfirmedRef));
    const credits = quotaBucketState(creditsRef, await transaction.get(creditsRef));
    const creditScans = quotaBucketState(creditScansRef, await transaction.get(creditScansRef));
    const capability = await transaction.get(dependencies.db.collection("app_config").doc("receipt_credits"));

    let transactionState: "granted" | "refunded" | "unknown" | undefined;
    if (requestedTransactionId !== undefined) {
      const source = candidateSourceConfig(dependencies);
      const candidates = source
        ? await Promise.all(source.allowedEnvironments.map((environment) => transaction.get(
          dependencies.db.collection("receipt_credit_txns").doc(receiptCreditTransactionDocId({
            appId: source.expectedAppId,
            store: source.expectedStore,
            environment,
            transactionId: requestedTransactionId,
          })),
        )))
        : [];
      const owned = candidates.filter((candidate) => candidate.data()?.uid === uid);
      if (owned.length === 1) {
        transactionState = ledgerTransactionState(owned[0].data());
      } else {
        transactionState = "unknown";
        if (owned.length > 1) {
          logger.error("receipt-credit status found multiple caller transaction candidates", {
            candidateCount: candidates.length,
            ownedCount: owned.length,
          });
        }
      }
    }

    return {
      ...compositeReceiptQuotaSnapshot(
        base,
        baseScan,
        baseConfirmed,
        credits,
        creditScans,
      ),
      creditsPurchasingEnabled: purchasingEnabled(capability.data(), now),
      sweepIncomplete,
      ...(requestedTransactionId !== undefined ? { transactionState: transactionState ?? "unknown" } : {}),
    };
  });
}

export const receiptQuotaStatus = onCall(
  { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 30 },
  async (request): Promise<ReceiptQuotaStatusResponse> => receiptQuotaStatusRequest(request, {
    db: getFirestore() as unknown as QuotaFirestore,
  }),
);
