import { randomUUID } from "node:crypto";
import { HttpsError } from "firebase-functions/v2/https";
import {
  DocumentReferenceLike,
  DocumentSnapshotLike,
  QueryDocumentSnapshotLike,
  QuotaFirestore,
  TransactionLike,
  nextUtcMonthStart,
  safeQuotaCount,
  userHasActiveProEntitlement,
} from "./claudeProxy";

export const FREE_LIFETIME_CONFIRMED_QUOTA = 5;
export const FREE_LIFETIME_SCAN_CEILING = 20;
export const PRO_MONTHLY_CONFIRMED_QUOTA = 20;
export const PRO_MONTHLY_SCAN_CEILING = 80;

const RECEIPT_TOKEN_TTL_MILLIS = 24 * 60 * 60 * 1000;

export type ReceiptEntitlement = "free" | "pro";

export type ReceiptQuotaSnapshot = {
  entitlement: ReceiptEntitlement;
  scanRemaining: number;
  scanCeiling: number;
  confirmedRemaining: number;
  confirmedAllowance: number;
  resetAt: string | null;
};

export type ReceiptQuotaReservation = {
  uid: string;
  entitlementUsed: ReceiptEntitlement;
  scanBucketId: string;
  confirmedBucketId: string;
  tokenId: string;
  quota: ReceiptQuotaSnapshot;
};

export type ReceiptQuotaConfiguration = {
  uid: string;
  entitlement: ReceiptEntitlement;
  scanBucketId: string;
  confirmedBucketId: string;
  scanCeiling: number;
  confirmedAllowance: number;
  resetAt: string | null;
  resetAtMillis: number | null;
  scanKind: string;
  confirmedKind: string;
  period: string | null;
};

type ReceiptTokenData = {
  uid: string;
  entitlementUsed: ReceiptEntitlement;
  confirmedBucketId: string;
  resetAtMillis: number | null;
  createdAtMillis: number;
  expiresAtMillis: number;
  consumed: boolean;
  consumedAtMillis?: number;
  released?: boolean;
};

type QuotaBucketState = {
  ref: DocumentReferenceLike;
  exists: boolean;
  count: number;
  reserved: number;
};

type ExpirySweep = {
  currentConfirmed: QuotaBucketState;
  expiredTokens: QueryDocumentSnapshotLike[];
  releasedByBucket: Map<string, number>;
  statesByBucket: Map<string, QuotaBucketState>;
};

function receiptQuotaConfiguration(
  uid: string,
  entitlement: ReceiptEntitlement,
  now: Date,
): ReceiptQuotaConfiguration {
  if (entitlement === "free") {
    return {
      uid,
      entitlement,
      scanBucketId: `${uid}_receipt_lifetime`,
      confirmedBucketId: `${uid}_receipt_confirmed_lifetime`,
      scanCeiling: FREE_LIFETIME_SCAN_CEILING,
      confirmedAllowance: FREE_LIFETIME_CONFIRMED_QUOTA,
      resetAt: null,
      resetAtMillis: null,
      scanKind: "receipt_quickadd_lifetime",
      confirmedKind: "receipt_confirmed_lifetime",
      period: null,
    };
  }

  const period = now.toISOString().slice(0, 7);
  const resetAt = nextUtcMonthStart(now);
  return {
    uid,
    entitlement,
    scanBucketId: `${uid}_receipt_scan_${period}`,
    confirmedBucketId: `${uid}_receipt_confirmed_${period}`,
    scanCeiling: PRO_MONTHLY_SCAN_CEILING,
    confirmedAllowance: PRO_MONTHLY_CONFIRMED_QUOTA,
    resetAt,
    resetAtMillis: Date.parse(resetAt),
    scanKind: "receipt_quickadd_monthly",
    confirmedKind: "receipt_confirmed_monthly",
    period,
  };
}

/**
 * Reconstructs a quota bucket only from the token's persisted admission data. Confirmation must
 * never select a bucket from the caller's current entitlement or the current calendar month.
 */
export function receiptQuotaConfigurationForToken(
  uid: string,
  entitlement: ReceiptEntitlement,
  confirmedBucketId: string,
  resetAtMillis: number | null,
): ReceiptQuotaConfiguration | undefined {
  if (entitlement === "free") {
    return confirmedBucketId === `${uid}_receipt_confirmed_lifetime`
      ? receiptQuotaConfiguration(uid, "free", new Date(0))
      : undefined;
  }

  const prefix = `${uid}_receipt_confirmed_`;
  if (!confirmedBucketId.startsWith(prefix)) return undefined;
  const period = confirmedBucketId.slice(prefix.length);
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(period)) return undefined;

  const [year, month] = period.split("-").map(Number);
  const calculatedResetAtMillis = Date.UTC(year, month, 1);
  const resetMillis = typeof resetAtMillis === "number" && Number.isFinite(resetAtMillis)
    ? resetAtMillis
    : calculatedResetAtMillis;

  return {
    uid,
    entitlement,
    scanBucketId: `${uid}_receipt_scan_${period}`,
    confirmedBucketId,
    scanCeiling: PRO_MONTHLY_SCAN_CEILING,
    confirmedAllowance: PRO_MONTHLY_CONFIRMED_QUOTA,
    resetAt: new Date(resetMillis).toISOString(),
    resetAtMillis: resetMillis,
    scanKind: "receipt_quickadd_monthly",
    confirmedKind: "receipt_confirmed_monthly",
    period,
  };
}

export function receiptQuotaSnapshot(
  configuration: ReceiptQuotaConfiguration,
  scanCount: number,
  confirmedCount: number,
  reserved: number,
): ReceiptQuotaSnapshot {
  return {
    entitlement: configuration.entitlement,
    scanRemaining: Math.max(0, configuration.scanCeiling - scanCount),
    scanCeiling: configuration.scanCeiling,
    confirmedRemaining: Math.max(0, configuration.confirmedAllowance - confirmedCount - reserved),
    confirmedAllowance: configuration.confirmedAllowance,
    resetAt: configuration.resetAt,
  };
}

function quotaBucketState(ref: DocumentReferenceLike, snapshot: DocumentSnapshotLike): QuotaBucketState {
  return {
    ref,
    exists: snapshot.exists,
    count: snapshot.exists ? safeQuotaCount(snapshot.data()?.count) : 0,
    reserved: snapshot.exists ? safeQuotaCount(snapshot.data()?.reserved) : 0,
  };
}

function tokenData(value: Record<string, unknown> | undefined): ReceiptTokenData | undefined {
  if (!value
    || typeof value.uid !== "string"
    || (value.entitlementUsed !== "free" && value.entitlementUsed !== "pro")
    || typeof value.confirmedBucketId !== "string"
    || (value.resetAtMillis !== null && (typeof value.resetAtMillis !== "number" || !Number.isFinite(value.resetAtMillis)))
    || typeof value.createdAtMillis !== "number"
    || !Number.isFinite(value.createdAtMillis)
    || typeof value.expiresAtMillis !== "number"
    || !Number.isFinite(value.expiresAtMillis)
    || typeof value.consumed !== "boolean") {
    return undefined;
  }

  return value as ReceiptTokenData;
}

/**
 * Collects all reads needed for the bounded lazy-expiry sweep. The test double intentionally
 * rejects reads after writes, matching Firestore's transaction rule, so callers write only after
 * this function resolves.
 */
async function readExpirySweep(
  db: QuotaFirestore,
  transaction: TransactionLike,
  uid: string,
  now: Date,
  configuration: ReceiptQuotaConfiguration,
  currentConfirmed: QuotaBucketState,
): Promise<ExpirySweep> {
  const expiredQuery = db.collection("receipt_scan_tokens")
    .where("uid", "==", uid)
    .where("consumed", "==", false)
    .where("expiresAtMillis", "<", now.getTime())
    .limit(10);
  const expired = await transaction.get(expiredQuery);
  const expiredTokens = expired.docs;
  const bucketIds = new Set<string>([configuration.confirmedBucketId]);

  for (const token of expiredTokens) {
    const bucketId = token.data().confirmedBucketId;
    if (typeof bucketId === "string") bucketIds.add(bucketId);
  }

  const statesByBucket = new Map<string, QuotaBucketState>([
    [configuration.confirmedBucketId, currentConfirmed],
  ]);
  for (const bucketId of bucketIds) {
    if (bucketId === configuration.confirmedBucketId) continue;
    const ref = db.collection("usage_quotas").doc(bucketId);
    const snapshot = await transaction.get(ref);
    statesByBucket.set(bucketId, quotaBucketState(ref, snapshot));
  }

  const releasedByBucket = new Map<string, number>();
  for (const token of expiredTokens) {
    const bucketId = token.data().confirmedBucketId;
    if (typeof bucketId !== "string") continue;
    releasedByBucket.set(bucketId, (releasedByBucket.get(bucketId) ?? 0) + 1);
  }

  return { currentConfirmed, expiredTokens, releasedByBucket, statesByBucket };
}

function expirySweepWrites(
  transaction: TransactionLike,
  sweep: ExpirySweep,
  now: Date,
  currentConfirmedBucketId: string,
): QuotaBucketState {
  const updatedAt = now.toISOString();
  const nowMillis = now.getTime();
  for (const token of sweep.expiredTokens) {
    transaction.set(token.ref, { consumed: true, consumedAtMillis: nowMillis, released: true }, { merge: true });
  }
  for (const [bucketId, released] of sweep.releasedByBucket) {
    const state = sweep.statesByBucket.get(bucketId);
    if (!state || !state.exists) continue;
    transaction.set(state.ref, { reserved: Math.max(0, state.reserved - released), updatedAt }, { merge: true });
  }
  return {
    ...sweep.currentConfirmed,
    reserved: Math.max(0, sweep.currentConfirmed.reserved - (sweep.releasedByBucket.get(currentConfirmedBucketId) ?? 0)),
  };
}

type AdmissionResult =
  | { kind: "admitted"; reservation: ReceiptQuotaReservation }
  | {
    kind: "denied";
    reason: "receipt_scan_exhausted" | "receipt_confirmed_exhausted";
    configuration: ReceiptQuotaConfiguration;
  };

export async function consumeReceiptQuota(
  db: QuotaFirestore,
  uid: string,
  now: Date,
): Promise<ReceiptQuotaReservation> {
  const result = await db.runTransaction<AdmissionResult>(async (transaction) => {
    const user = await transaction.get(db.collection("users").doc(uid));
    const entitlement: ReceiptEntitlement = userHasActiveProEntitlement(user.data(), now) ? "pro" : "free";
    const configuration = receiptQuotaConfiguration(uid, entitlement, now);
    const scanRef = db.collection("usage_quotas").doc(configuration.scanBucketId);
    const confirmedRef = db.collection("usage_quotas").doc(configuration.confirmedBucketId);
    const scanSnapshot = await transaction.get(scanRef);
    const confirmedSnapshot = await transaction.get(confirmedRef);
    const scan = quotaBucketState(scanRef, scanSnapshot);
    const confirmed = quotaBucketState(confirmedRef, confirmedSnapshot);
    const sweep = await readExpirySweep(db, transaction, uid, now, configuration, confirmed);

    // Every transaction read is now complete. The sweep must commit even when the next admission
    // is denied, so denial is returned and raised only after the transaction has committed.
    const releasedConfirmed = expirySweepWrites(transaction, sweep, now, configuration.confirmedBucketId);
    if (scan.count >= configuration.scanCeiling) {
      return { kind: "denied", reason: "receipt_scan_exhausted", configuration };
    }
    if (releasedConfirmed.count + releasedConfirmed.reserved >= configuration.confirmedAllowance) {
      return { kind: "denied", reason: "receipt_confirmed_exhausted", configuration };
    }

    const tokenId = randomUUID();
    const nextScanCount = scan.count + 1;
    const nextReserved = releasedConfirmed.reserved + 1;
    transaction.set(scanRef, {
      uid,
      kind: configuration.scanKind,
      ...(configuration.period ? { month: configuration.period } : {}),
      count: nextScanCount,
      updatedAt: now.toISOString(),
    }, { merge: true });
    transaction.set(confirmedRef, {
      uid,
      kind: configuration.confirmedKind,
      count: releasedConfirmed.count,
      reserved: nextReserved,
      updatedAt: now.toISOString(),
    }, { merge: true });
    transaction.create(db.collection("receipt_scan_tokens").doc(tokenId), {
      uid,
      entitlementUsed: entitlement,
      confirmedBucketId: configuration.confirmedBucketId,
      resetAtMillis: configuration.resetAtMillis,
      createdAtMillis: now.getTime(),
      expiresAtMillis: now.getTime() + RECEIPT_TOKEN_TTL_MILLIS,
      consumed: false,
    });

    return {
      kind: "admitted",
      reservation: {
        uid,
        entitlementUsed: entitlement,
        scanBucketId: configuration.scanBucketId,
        confirmedBucketId: configuration.confirmedBucketId,
        tokenId,
        quota: receiptQuotaSnapshot(configuration, nextScanCount, releasedConfirmed.count, nextReserved),
      },
    };
  });

  if (result.kind === "admitted") return result.reservation;
  const scope = result.configuration.entitlement === "pro" ? "pro_month" : "free_lifetime";
  const details = {
    reason: result.reason,
    scope,
    ...(result.configuration.resetAt ? { resetAt: result.configuration.resetAt } : {}),
  };
  throw new HttpsError(
    "resource-exhausted",
    result.reason === "receipt_scan_exhausted"
      ? "Receipt scan quota exhausted."
      : "Receipt confirmed quota exhausted.",
    details,
  );
}

/** Releases a token reservation and, for unbilled upstream failures, restores the scan unit too. */
async function releaseReceiptReservation(
  db: QuotaFirestore,
  reservation: ReceiptQuotaReservation,
  now: Date,
  refundScan: boolean,
): Promise<void> {
  const scanRef = db.collection("usage_quotas").doc(reservation.scanBucketId);
  const confirmedRef = db.collection("usage_quotas").doc(reservation.confirmedBucketId);
  const tokenRef = db.collection("receipt_scan_tokens").doc(reservation.tokenId);
  await db.runTransaction(async (transaction) => {
    const scanSnapshot = await transaction.get(scanRef);
    const confirmedSnapshot = await transaction.get(confirmedRef);
    const tokenSnapshot = await transaction.get(tokenRef);
    const token = tokenData(tokenSnapshot.data());
    if (!token || token.consumed) return;

    const scan = quotaBucketState(scanRef, scanSnapshot);
    const confirmed = quotaBucketState(confirmedRef, confirmedSnapshot);
    const updatedAt = now.toISOString();
    if (refundScan) {
      transaction.set(scanRef, { count: Math.max(0, scan.count - 1), updatedAt }, { merge: true });
    }
    transaction.set(confirmedRef, { reserved: Math.max(0, confirmed.reserved - 1), updatedAt }, { merge: true });
    transaction.set(tokenRef, {
      consumed: true,
      consumedAtMillis: now.getTime(),
      released: true,
    }, { merge: true });
  });
}

export async function refundReceiptQuota(
  db: QuotaFirestore,
  reservation: ReceiptQuotaReservation,
  now: Date,
): Promise<void> {
  await releaseReceiptReservation(db, reservation, now, true);
}

export async function voidReceiptReservation(
  db: QuotaFirestore,
  reservation: ReceiptQuotaReservation,
  now: Date,
): Promise<void> {
  await releaseReceiptReservation(db, reservation, now, false);
}

/** Current-entitlement snapshot with the same bounded lazy-expiry release as scan admission. */
export async function receiptQuotaStatusForUser(
  db: QuotaFirestore,
  uid: string,
  now: Date,
): Promise<ReceiptQuotaSnapshot> {
  return db.runTransaction(async (transaction) => {
    const user = await transaction.get(db.collection("users").doc(uid));
    const entitlement: ReceiptEntitlement = userHasActiveProEntitlement(user.data(), now) ? "pro" : "free";
    const configuration = receiptQuotaConfiguration(uid, entitlement, now);
    const scanRef = db.collection("usage_quotas").doc(configuration.scanBucketId);
    const confirmedRef = db.collection("usage_quotas").doc(configuration.confirmedBucketId);
    const scanSnapshot = await transaction.get(scanRef);
    const confirmedSnapshot = await transaction.get(confirmedRef);
    const scan = quotaBucketState(scanRef, scanSnapshot);
    const confirmed = quotaBucketState(confirmedRef, confirmedSnapshot);
    const sweep = await readExpirySweep(db, transaction, uid, now, configuration, confirmed);
    const releasedConfirmed = expirySweepWrites(transaction, sweep, now, configuration.confirmedBucketId);
    return receiptQuotaSnapshot(configuration, scan.count, releasedConfirmed.count, releasedConfirmed.reserved);
  });
}
