import { randomUUID } from "node:crypto";
import { Timestamp } from "firebase-admin/firestore";
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
export const RECEIPT_CREDIT_SCAN_KIND = "receipt_credit_scans";
export const RECEIPT_CREDITS_KIND = "receipt_credits";

const RECEIPT_TOKEN_TTL_MILLIS = 24 * 60 * 60 * 1000;
const EXPIRY_SWEEP_PAGE_SIZE = 10;

export type ReceiptEntitlement = "free" | "pro";

/**
 * The first six fields are the v1 receipt-quota wire contract. Credits are deliberately additive:
 * old clients remain able to read the base quota while new clients can evaluate both routes.
 */
export type ReceiptQuotaSnapshot = {
  entitlement: ReceiptEntitlement;
  scanRemaining: number;
  scanCeiling: number;
  confirmedRemaining: number;
  confirmedAllowance: number;
  resetAt: string | null;
  creditsRemaining: number;
  creditsScanRemaining: number;
  creditsGranted: number;
  creditsDeficit: number;
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

export type ReceiptScanToken = {
  uid: string;
  entitlementUsed: ReceiptEntitlement;
  confirmedBucketId: string;
  resetAtMillis: number | null;
  createdAtMillis: number;
  expiresAtMillis: number;
  consumed: boolean;
  consumedAtMillis?: number;
  released?: boolean;
  releaseReason?: "expired" | "refund" | "revoked";
};

export type QuotaBucketState = {
  ref: DocumentReferenceLike;
  exists: boolean;
  count: number;
  reserved: number;
  granted: number;
  clawed: number;
};

export type ExpirySweep = {
  expiredTokens: QueryDocumentSnapshotLike[];
  hasMore: boolean;
  releasedByBucket: Map<string, number>;
  statesByBucket: Map<string, QuotaBucketState>;
};

export function receiptQuotaConfiguration(
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

/** The credit route is entitlement-independent but records the admitting entitlement on its token. */
export function receiptCreditQuotaConfiguration(
  uid: string,
  entitlement: ReceiptEntitlement,
): ReceiptQuotaConfiguration {
  return {
    uid,
    entitlement,
    scanBucketId: `${uid}_receipt_credit_scans`,
    confirmedBucketId: `${uid}_receipt_credits`,
    // These values are never used to admit or confirm credits. They intentionally remain zero so
    // a caller cannot accidentally apply a base allowance to the lifetime credit bucket.
    scanCeiling: 0,
    confirmedAllowance: 0,
    resetAt: null,
    resetAtMillis: null,
    scanKind: RECEIPT_CREDIT_SCAN_KIND,
    confirmedKind: RECEIPT_CREDITS_KIND,
    period: null,
  };
}

export function isReceiptCreditConfiguration(configuration: ReceiptQuotaConfiguration): boolean {
  return configuration.confirmedBucketId === `${configuration.uid}_receipt_credits`
    && configuration.scanBucketId === `${configuration.uid}_receipt_credit_scans`;
}

/**
 * Reconstructs a quota route only from persisted token data. The credits match is intentionally
 * first and entitlement-agnostic: a free-to-Pro change can never reroute an in-flight credit scan.
 */
export function receiptQuotaConfigurationForToken(
  uid: string,
  entitlement: ReceiptEntitlement,
  confirmedBucketId: string,
  resetAtMillis: number | null,
): ReceiptQuotaConfiguration | undefined {
  const credits = receiptCreditQuotaConfiguration(uid, entitlement);
  if (confirmedBucketId === credits.confirmedBucketId) return credits;

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

export function quotaBucketState(ref: DocumentReferenceLike, snapshot: DocumentSnapshotLike): QuotaBucketState {
  const data = snapshot.data();
  return {
    ref,
    exists: snapshot.exists,
    count: snapshot.exists ? safeQuotaCount(data?.count) : 0,
    reserved: snapshot.exists ? safeQuotaCount(data?.reserved) : 0,
    granted: snapshot.exists ? safeQuotaCount(data?.granted) : 0,
    clawed: snapshot.exists ? safeQuotaCount(data?.clawed) : 0,
  };
}

function creditFields(credits: QuotaBucketState, creditScans: QuotaBucketState): Pick<
  ReceiptQuotaSnapshot,
  "creditsRemaining" | "creditsScanRemaining" | "creditsGranted" | "creditsDeficit"
> {
  const effective = Math.max(0, credits.granted - credits.clawed);
  const spentOrReserved = credits.count + credits.reserved;
  return {
    creditsRemaining: Math.max(0, effective - spentOrReserved),
    creditsScanRemaining: Math.max(0, 4 * credits.granted - creditScans.count),
    creditsGranted: credits.granted,
    creditsDeficit: Math.max(0, spentOrReserved - effective),
  };
}

export function receiptQuotaSnapshot(
  configuration: ReceiptQuotaConfiguration,
  scanCount: number,
  confirmedCount: number,
  reserved: number,
  credits: Pick<QuotaBucketState, "count" | "reserved" | "granted" | "clawed"> = {
    count: 0, reserved: 0, granted: 0, clawed: 0,
  },
  creditScans: Pick<QuotaBucketState, "count"> = { count: 0 },
): ReceiptQuotaSnapshot {
  return {
    entitlement: configuration.entitlement,
    scanRemaining: Math.max(0, configuration.scanCeiling - scanCount),
    scanCeiling: configuration.scanCeiling,
    confirmedRemaining: Math.max(0, configuration.confirmedAllowance - confirmedCount - reserved),
    confirmedAllowance: configuration.confirmedAllowance,
    resetAt: configuration.resetAt,
    ...creditFields(credits as QuotaBucketState, creditScans as QuotaBucketState),
  };
}

/** Legacy fields always come from the CURRENT base-entitlement buckets; credit fields are additive. */
export function compositeReceiptQuotaSnapshot(
  baseConfiguration: ReceiptQuotaConfiguration,
  baseScan: QuotaBucketState,
  baseConfirmed: QuotaBucketState,
  credits: QuotaBucketState,
  creditScans: QuotaBucketState,
): ReceiptQuotaSnapshot {
  return receiptQuotaSnapshot(
    baseConfiguration,
    baseScan.count,
    baseConfirmed.count,
    baseConfirmed.reserved,
    credits,
    creditScans,
  );
}

export function receiptScanTokenFromData(value: Record<string, unknown> | undefined): ReceiptScanToken | undefined {
  if (
    !value
    || typeof value.uid !== "string"
    || (value.entitlementUsed !== "free" && value.entitlementUsed !== "pro")
    || typeof value.confirmedBucketId !== "string"
    || (value.resetAtMillis !== null && (typeof value.resetAtMillis !== "number" || !Number.isFinite(value.resetAtMillis)))
    || typeof value.createdAtMillis !== "number"
    || !Number.isFinite(value.createdAtMillis)
    || typeof value.expiresAtMillis !== "number"
    || !Number.isFinite(value.expiresAtMillis)
    || typeof value.consumed !== "boolean"
    || (value.releaseReason !== undefined
      && value.releaseReason !== "expired"
      && value.releaseReason !== "refund"
      && value.releaseReason !== "revoked")
  ) {
    return undefined;
  }
  return value as ReceiptScanToken;
}

/**
 * Collects all sweep reads before callers issue their first write. It reads eleven token rows,
 * releases at most ten, and treats row eleven only as the server-side convergence probe. Credits
 * are force-included even when no token references them, preventing stale reserved values from
 * being used by a same-transaction fallback admission.
 */
export async function readExpirySweep(
  db: QuotaFirestore,
  transaction: TransactionLike,
  uid: string,
  now: Date,
  configuration: ReceiptQuotaConfiguration,
  existingStates: Map<string, QuotaBucketState> = new Map(),
): Promise<ExpirySweep> {
  const expiredQuery = db.collection("receipt_scan_tokens")
    .where("uid", "==", uid)
    .where("consumed", "==", false)
    .where("expiresAtMillis", "<", now.getTime())
    .limit(EXPIRY_SWEEP_PAGE_SIZE + 1);
  const expired = await transaction.get(expiredQuery);
  const hasMore = expired.docs.length > EXPIRY_SWEEP_PAGE_SIZE;
  const expiredTokens = expired.docs.slice(0, EXPIRY_SWEEP_PAGE_SIZE);
  const bucketIds = new Set<string>([
    configuration.confirmedBucketId,
    `${uid}_receipt_credits`,
  ]);
  for (const token of expiredTokens) {
    const bucketId = token.data().confirmedBucketId;
    if (typeof bucketId === "string") bucketIds.add(bucketId);
  }

  const statesByBucket = new Map(existingStates);
  for (const bucketId of bucketIds) {
    if (statesByBucket.has(bucketId)) continue;
    const ref = db.collection("usage_quotas").doc(bucketId);
    statesByBucket.set(bucketId, quotaBucketState(ref, await transaction.get(ref)));
  }

  const releasedByBucket = new Map<string, number>();
  for (const token of expiredTokens) {
    const bucketId = token.data().confirmedBucketId;
    if (typeof bucketId !== "string") continue;
    releasedByBucket.set(bucketId, (releasedByBucket.get(bucketId) ?? 0) + 1);
  }
  return { expiredTokens, hasMore, releasedByBucket, statesByBucket };
}

/** Applies an expiry page and returns post-release state for EVERY previously-read bucket. */
export function expirySweepWrites(
  transaction: TransactionLike,
  sweep: ExpirySweep,
  now: Date,
): Map<string, QuotaBucketState> {
  const updatedAt = now.toISOString();
  const nowMillis = now.getTime();
  for (const token of sweep.expiredTokens) {
    transaction.set(token.ref, {
      consumed: true,
      consumedAtMillis: nowMillis,
      released: true,
      releaseReason: "expired",
    }, { merge: true });
  }

  const statesByBucket = new Map(sweep.statesByBucket);
  for (const [bucketId, released] of sweep.releasedByBucket) {
    const state = statesByBucket.get(bucketId);
    if (!state || !state.exists) continue;
    const postRelease = { ...state, reserved: Math.max(0, state.reserved - released) };
    statesByBucket.set(bucketId, postRelease);
    transaction.set(postRelease.ref, { reserved: postRelease.reserved, updatedAt }, { merge: true });
  }
  return statesByBucket;
}

/** Bounded expiry transaction used by status before its one consistent final snapshot transaction. */
export async function sweepExpiredReceiptReservations(
  db: QuotaFirestore,
  uid: string,
  now: Date,
): Promise<boolean> {
  return db.runTransaction(async (transaction) => {
    const configuration = receiptQuotaConfiguration(uid, "free", now);
    const sweep = await readExpirySweep(db, transaction, uid, now, configuration);
    expirySweepWrites(transaction, sweep, now);
    return sweep.hasMore;
  });
}

type AdmissionResult =
  | { kind: "admitted"; reservation: ReceiptQuotaReservation }
  | {
    kind: "denied";
    reason: "receipt_scan_exhausted" | "receipt_confirmed_exhausted";
    configuration: ReceiptQuotaConfiguration;
  };

function currentEntitlementConfiguration(
  uid: string,
  user: DocumentSnapshotLike,
  now: Date,
): ReceiptQuotaConfiguration {
  const entitlement: ReceiptEntitlement = userHasActiveProEntitlement(user.data(), now) ? "pro" : "free";
  return receiptQuotaConfiguration(uid, entitlement, now);
}

export async function consumeReceiptQuota(
  db: QuotaFirestore,
  uid: string,
  now: Date,
): Promise<ReceiptQuotaReservation> {
  const result = await db.runTransaction<AdmissionResult>(async (transaction) => {
    const user = await transaction.get(db.collection("users").doc(uid));
    const configuration = currentEntitlementConfiguration(uid, user, now);
    const scanRef = db.collection("usage_quotas").doc(configuration.scanBucketId);
    const confirmedRef = db.collection("usage_quotas").doc(configuration.confirmedBucketId);
    const creditsConfiguration = receiptCreditQuotaConfiguration(uid, configuration.entitlement);
    const creditsRef = db.collection("usage_quotas").doc(creditsConfiguration.confirmedBucketId);
    const creditScansRef = db.collection("usage_quotas").doc(creditsConfiguration.scanBucketId);
    const scan = quotaBucketState(scanRef, await transaction.get(scanRef));
    const confirmed = quotaBucketState(confirmedRef, await transaction.get(confirmedRef));
    const credits = quotaBucketState(creditsRef, await transaction.get(creditsRef));
    const creditScans = quotaBucketState(creditScansRef, await transaction.get(creditScansRef));
    const sweep = await readExpirySweep(db, transaction, uid, now, configuration, new Map([
      [configuration.confirmedBucketId, confirmed],
      [creditsConfiguration.confirmedBucketId, credits],
    ]));

    // All reads complete before this point. A denial returns only after expired reservations have
    // committed, preserving the legacy self-healing behavior.
    const postRelease = expirySweepWrites(transaction, sweep, now);
    const postConfirmed = postRelease.get(configuration.confirmedBucketId) ?? confirmed;
    const postCredits = postRelease.get(creditsConfiguration.confirmedBucketId) ?? credits;
    const baseDenyReason = scan.count >= configuration.scanCeiling
      ? "receipt_scan_exhausted"
      : "receipt_confirmed_exhausted";
    const baseAdmissible = scan.count < configuration.scanCeiling
      && postConfirmed.count + postConfirmed.reserved < configuration.confirmedAllowance;

    const effectiveCredits = Math.max(0, postCredits.granted - postCredits.clawed);
    const creditAdmissible = creditScans.count < 4 * postCredits.granted
      && postCredits.count + postCredits.reserved < effectiveCredits;
    const tokenId = randomUUID();

    if (baseAdmissible) {
      const nextScanCount = scan.count + 1;
      const nextConfirmedReserved = postConfirmed.reserved + 1;
      const nextConfirmed = { ...postConfirmed, reserved: nextConfirmedReserved };
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
        ...(configuration.period ? { month: configuration.period } : {}),
        count: postConfirmed.count,
        reserved: nextConfirmedReserved,
        updatedAt: now.toISOString(),
      }, { merge: true });
      transaction.create(db.collection("receipt_scan_tokens").doc(tokenId), {
        uid,
        entitlementUsed: configuration.entitlement,
        confirmedBucketId: configuration.confirmedBucketId,
        resetAtMillis: configuration.resetAtMillis,
        createdAtMillis: now.getTime(),
        expiresAtMillis: now.getTime() + RECEIPT_TOKEN_TTL_MILLIS,
        // Duplicate of expiresAtMillis as a real Timestamp: Firestore TTL policies only attach
        // to Timestamp fields, so this is what lets prod garbage-collect expired tokens. All
        // reads/queries stay on expiresAtMillis; TTL deletion is best-effort cleanup on top.
        expiresAt: Timestamp.fromMillis(now.getTime() + RECEIPT_TOKEN_TTL_MILLIS),
        consumed: false,
      });
      return {
        kind: "admitted",
        reservation: {
          uid,
          entitlementUsed: configuration.entitlement,
          scanBucketId: configuration.scanBucketId,
          confirmedBucketId: configuration.confirmedBucketId,
          tokenId,
          quota: compositeReceiptQuotaSnapshot(configuration, { ...scan, count: nextScanCount }, nextConfirmed, postCredits, creditScans),
        },
      };
    }

    if (!creditAdmissible) return { kind: "denied", reason: baseDenyReason, configuration };

    const nextCreditScans = { ...creditScans, count: creditScans.count + 1 };
    const nextCredits = { ...postCredits, reserved: postCredits.reserved + 1 };
    transaction.set(creditScansRef, {
      uid,
      kind: RECEIPT_CREDIT_SCAN_KIND,
      count: nextCreditScans.count,
      updatedAt: now.toISOString(),
    }, { merge: true });
    transaction.set(creditsRef, {
      uid,
      kind: RECEIPT_CREDITS_KIND,
      granted: postCredits.granted,
      clawed: postCredits.clawed,
      count: postCredits.count,
      reserved: nextCredits.reserved,
      updatedAt: now.toISOString(),
    }, { merge: true });
    transaction.create(db.collection("receipt_scan_tokens").doc(tokenId), {
      uid,
      entitlementUsed: configuration.entitlement,
      confirmedBucketId: creditsConfiguration.confirmedBucketId,
      resetAtMillis: null,
      createdAtMillis: now.getTime(),
      expiresAtMillis: now.getTime() + RECEIPT_TOKEN_TTL_MILLIS,
      // Same TTL Timestamp duplicate as the base-route token above — see that comment.
      expiresAt: Timestamp.fromMillis(now.getTime() + RECEIPT_TOKEN_TTL_MILLIS),
      consumed: false,
    });
    return {
      kind: "admitted",
      reservation: {
        uid,
        entitlementUsed: configuration.entitlement,
        scanBucketId: creditsConfiguration.scanBucketId,
        confirmedBucketId: creditsConfiguration.confirmedBucketId,
        tokenId,
        quota: compositeReceiptQuotaSnapshot(configuration, scan, postConfirmed, nextCredits, nextCreditScans),
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

/** Releases a reservation; all upstream-failure release paths retain the token's scan charge rules. */
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
    const token = receiptScanTokenFromData(tokenSnapshot.data());
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
      releaseReason: "refund",
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

/** A single composite snapshot transaction for callers that do not expose status-only capability fields. */
export async function receiptQuotaSnapshotForUser(
  db: QuotaFirestore,
  uid: string,
  now: Date,
): Promise<ReceiptQuotaSnapshot> {
  return db.runTransaction(async (transaction) => {
    const user = await transaction.get(db.collection("users").doc(uid));
    const configuration = currentEntitlementConfiguration(uid, user, now);
    const creditConfiguration = receiptCreditQuotaConfiguration(uid, configuration.entitlement);
    const scanRef = db.collection("usage_quotas").doc(configuration.scanBucketId);
    const confirmedRef = db.collection("usage_quotas").doc(configuration.confirmedBucketId);
    const creditsRef = db.collection("usage_quotas").doc(creditConfiguration.confirmedBucketId);
    const creditScansRef = db.collection("usage_quotas").doc(creditConfiguration.scanBucketId);
    const scan = quotaBucketState(scanRef, await transaction.get(scanRef));
    const confirmed = quotaBucketState(confirmedRef, await transaction.get(confirmedRef));
    const credits = quotaBucketState(creditsRef, await transaction.get(creditsRef));
    const creditScans = quotaBucketState(creditScansRef, await transaction.get(creditScansRef));
    const sweep = await readExpirySweep(db, transaction, uid, now, configuration, new Map([
      [configuration.confirmedBucketId, confirmed],
      [creditConfiguration.confirmedBucketId, credits],
    ]));
    const postRelease = expirySweepWrites(transaction, sweep, now);
    return compositeReceiptQuotaSnapshot(
      configuration,
      scan,
      postRelease.get(configuration.confirmedBucketId) ?? confirmed,
      postRelease.get(creditConfiguration.confirmedBucketId) ?? credits,
      creditScans,
    );
  });
}

/** Backward-compatible internal name used by the original status callable. */
export const receiptQuotaStatusForUser = receiptQuotaSnapshotForUser;
