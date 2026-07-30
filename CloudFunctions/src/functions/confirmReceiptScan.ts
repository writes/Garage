import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { QuotaFirestore, userHasActiveProEntitlement } from "./claudeProxy";
import {
  ReceiptQuotaSnapshot,
  compositeReceiptQuotaSnapshot,
  isReceiptCreditConfiguration,
  quotaBucketState,
  receiptCreditQuotaConfiguration,
  receiptQuotaConfiguration,
  receiptQuotaConfigurationForToken,
  receiptScanTokenFromData,
} from "./receiptQuota";

export type ConfirmReceiptScanRequest = { auth?: { uid: string } | null; data?: unknown };

export type ConfirmReceiptScanDependencies = {
  db: QuotaFirestore;
  now?: () => Date;
};

const uuidV4Pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const tokenNotFoundMessage = "Receipt scan token was not found.";

function tokenFromData(data: unknown): string {
  const token = typeof data === "object" && data !== null && !Array.isArray(data)
    ? (data as Record<string, unknown>).token
    : undefined;
  if (typeof token !== "string" || token.length !== 36 || !uuidV4Pattern.test(token)) {
    throw new HttpsError("invalid-argument", "token must be a UUID v4.");
  }
  return token;
}

type ReleaseReason = "expired" | "refund" | "revoked";

type ConfirmationResult =
  | { kind: "confirmed" | "idempotent"; snapshot: ReceiptQuotaSnapshot }
  | { kind: "not-found" }
  | { kind: "released"; releaseReason: ReleaseReason };

function releaseError(releaseReason: ReleaseReason): HttpsError {
  if (releaseReason === "revoked") {
    return new HttpsError(
      "failed-precondition",
      "Receipt credits were revoked before this scan could be confirmed.",
      { reason: "receipt_credits_revoked" },
    );
  }
  if (releaseReason === "refund") {
    return new HttpsError(
      "failed-precondition",
      "Receipt scan token was released after the request failed.",
      { reason: "receipt_token_refunded" },
    );
  }
  return new HttpsError("failed-precondition", "Receipt scan token expired.", { reason: "receipt_token_expired" });
}

export async function confirmReceiptScanRequest(
  request: ConfirmReceiptScanRequest,
  dependencies: ConfirmReceiptScanDependencies,
): Promise<ReceiptQuotaSnapshot> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in.");
  // Validation happens before the transaction so malformed input cannot probe or read Firestore.
  const tokenId = tokenFromData(request.data);
  const now = (dependencies.now ?? (() => new Date()))();

  const result = await dependencies.db.runTransaction<ConfirmationResult>(async (transaction) => {
    // Read order is intentional: token -> persisted route -> user/current base -> both credit docs.
    const tokenRef = dependencies.db.collection("receipt_scan_tokens").doc(tokenId);
    const tokenSnapshot = await transaction.get(tokenRef);
    const token = receiptScanTokenFromData(tokenSnapshot.data());
    if (!token || token.uid !== request.auth?.uid) return { kind: "not-found" };

    const route = receiptQuotaConfigurationForToken(
      token.uid,
      token.entitlementUsed,
      token.confirmedBucketId,
      token.resetAtMillis,
    );
    if (!route) return { kind: "not-found" };

    const userSnapshot = await transaction.get(dependencies.db.collection("users").doc(token.uid));
    const currentEntitlement = userHasActiveProEntitlement(userSnapshot.data(), now) ? "pro" : "free";
    const base = receiptQuotaConfiguration(token.uid, currentEntitlement, now);
    const creditsConfiguration = receiptCreditQuotaConfiguration(token.uid, currentEntitlement);
    const baseScanRef = dependencies.db.collection("usage_quotas").doc(base.scanBucketId);
    const baseConfirmedRef = dependencies.db.collection("usage_quotas").doc(base.confirmedBucketId);
    const creditsRef = dependencies.db.collection("usage_quotas").doc(creditsConfiguration.confirmedBucketId);
    const creditScansRef = dependencies.db.collection("usage_quotas").doc(creditsConfiguration.scanBucketId);
    const baseScan = quotaBucketState(baseScanRef, await transaction.get(baseScanRef));
    const baseConfirmed = quotaBucketState(baseConfirmedRef, await transaction.get(baseConfirmedRef));
    const routeConfirmedRef = dependencies.db.collection("usage_quotas").doc(route.confirmedBucketId);
    const routeConfirmed = route.confirmedBucketId === base.confirmedBucketId
      ? baseConfirmed
      : quotaBucketState(routeConfirmedRef, await transaction.get(routeConfirmedRef));
    const credits = quotaBucketState(creditsRef, await transaction.get(creditsRef));
    const creditScans = quotaBucketState(creditScansRef, await transaction.get(creditScansRef));

    const snapshot = (nextBaseConfirmed = baseConfirmed, nextCredits = credits): ReceiptQuotaSnapshot =>
      compositeReceiptQuotaSnapshot(base, baseScan, nextBaseConfirmed, nextCredits, creditScans);

    // A confirmed token wins over expiry. A released token is never an idempotent success; its
    // persisted reason turns every retry into the same post-commit response.
    if (token.consumed) {
      if (token.released) return { kind: "released", releaseReason: token.releaseReason ?? "expired" };
      return { kind: "idempotent", snapshot: snapshot() };
    }

    if (token.expiresAtMillis < now.getTime()) {
      const releasedRoute = { ...routeConfirmed, reserved: Math.max(0, routeConfirmed.reserved - 1) };
      transaction.set(routeConfirmedRef, { reserved: releasedRoute.reserved, updatedAt: now.toISOString() }, { merge: true });
      transaction.set(tokenRef, {
        consumed: true,
        consumedAtMillis: now.getTime(),
        released: true,
        releaseReason: "expired",
      }, { merge: true });
      return { kind: "released", releaseReason: "expired" };
    }

    if (isReceiptCreditConfiguration(route)) {
      const effectiveCredits = Math.max(0, credits.granted - credits.clawed);
      if (credits.count >= effectiveCredits) {
        // Return the typed result from the transaction and throw only afterwards: throwing in the
        // callback would roll back this reservation release and preserve the exploit.
        transaction.set(creditsRef, {
          reserved: Math.max(0, credits.reserved - 1),
          updatedAt: now.toISOString(),
        }, { merge: true });
        transaction.set(tokenRef, {
          consumed: true,
          consumedAtMillis: now.getTime(),
          released: true,
          releaseReason: "revoked",
        }, { merge: true });
        return { kind: "released", releaseReason: "revoked" };
      }

      const nextCredits = {
        ...credits,
        count: credits.count + 1,
        reserved: Math.max(0, credits.reserved - 1),
      };
      transaction.set(creditsRef, {
        uid: token.uid,
        kind: "receipt_credits",
        granted: nextCredits.granted,
        clawed: nextCredits.clawed,
        count: nextCredits.count,
        reserved: nextCredits.reserved,
        updatedAt: now.toISOString(),
      }, { merge: true });
      transaction.set(tokenRef, { consumed: true, consumedAtMillis: now.getTime() }, { merge: true });
      return { kind: "confirmed", snapshot: snapshot(baseConfirmed, nextCredits) };
    }

    const nextRouteConfirmed = {
      ...routeConfirmed,
      count: routeConfirmed.count + 1,
      reserved: Math.max(0, routeConfirmed.reserved - 1),
    };
    transaction.set(routeConfirmedRef, {
      uid: token.uid,
      kind: route.confirmedKind,
      ...(route.period ? { month: route.period } : {}),
      count: nextRouteConfirmed.count,
      reserved: nextRouteConfirmed.reserved,
      updatedAt: now.toISOString(),
    }, { merge: true });
    transaction.set(tokenRef, { consumed: true, consumedAtMillis: now.getTime() }, { merge: true });
    const nextBaseConfirmed = route.confirmedBucketId === base.confirmedBucketId
      ? nextRouteConfirmed
      : baseConfirmed;
    return { kind: "confirmed", snapshot: snapshot(nextBaseConfirmed) };
  });

  if (result.kind === "not-found") throw new HttpsError("not-found", tokenNotFoundMessage);
  if (result.kind === "released") throw releaseError(result.releaseReason);
  return result.snapshot;
}

export const confirmReceiptScan = onCall(
  { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 30 },
  async (request): Promise<ReceiptQuotaSnapshot> => confirmReceiptScanRequest(request, {
    db: getFirestore() as unknown as QuotaFirestore,
  }),
);
