import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  QuotaFirestore,
  safeQuotaCount,
} from "./claudeProxy";
import {
  ReceiptQuotaSnapshot,
  receiptQuotaConfigurationForToken,
  receiptQuotaSnapshot,
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

type ConfirmationResult =
  | { kind: "confirmed" | "idempotent"; snapshot: ReceiptQuotaSnapshot }
  | { kind: "not-found" }
  | { kind: "expired" };

export async function confirmReceiptScanRequest(
  request: ConfirmReceiptScanRequest,
  dependencies: ConfirmReceiptScanDependencies,
): Promise<ReceiptQuotaSnapshot> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in.");
  // Validation happens before the transaction so malformed input cannot probe or read Firestore.
  const tokenId = tokenFromData(request.data);
  const now = (dependencies.now ?? (() => new Date()))();

  const result = await dependencies.db.runTransaction<ConfirmationResult>(async (transaction) => {
    const tokenRef = dependencies.db.collection("receipt_scan_tokens").doc(tokenId);
    const tokenSnapshot = await transaction.get(tokenRef);
    const token = receiptScanTokenFromData(tokenSnapshot.data());
    if (!token || token.uid !== request.auth?.uid) return { kind: "not-found" };

    const configuration = receiptQuotaConfigurationForToken(
      token.uid,
      token.entitlementUsed,
      token.confirmedBucketId,
      token.resetAtMillis,
    );
    if (!configuration) return { kind: "not-found" };

    const scanRef = dependencies.db.collection("usage_quotas").doc(configuration.scanBucketId);
    const confirmedRef = dependencies.db.collection("usage_quotas").doc(configuration.confirmedBucketId);
    const scanSnapshot = await transaction.get(scanRef);
    const confirmedSnapshot = await transaction.get(confirmedRef);
    const scanCount = scanSnapshot.exists ? safeQuotaCount(scanSnapshot.data()?.count) : 0;
    const confirmedCount = confirmedSnapshot.exists ? safeQuotaCount(confirmedSnapshot.data()?.count) : 0;
    const reserved = confirmedSnapshot.exists ? safeQuotaCount(confirmedSnapshot.data()?.reserved) : 0;

    // A consumed token wins over expiry so a retry remains a successful idempotent confirmation,
    // including when the client retries after the 24-hour timestamp has passed. But only a token
    // consumed by a real confirmation is idempotent-success: `released` marks tokens voided by the
    // expiry sweep or a refund path, whose reservation was returned without any confirmed unit —
    // reporting success for those would tell the client a confirmation happened that never did.
    if (token.consumed) {
      if (token.released) return { kind: "expired" };
      return { kind: "idempotent", snapshot: receiptQuotaSnapshot(configuration, scanCount, confirmedCount, reserved) };
    }

    if (token.expiresAtMillis < now.getTime()) {
      transaction.set(confirmedRef, {
        reserved: Math.max(0, reserved - 1),
        updatedAt: now.toISOString(),
      }, { merge: true });
      transaction.set(tokenRef, {
        consumed: true,
        consumedAtMillis: now.getTime(),
        released: true,
      }, { merge: true });
      return { kind: "expired" };
    }

    const nextCount = confirmedCount + 1;
    const nextReserved = Math.max(0, reserved - 1);
    transaction.set(confirmedRef, {
      uid: token.uid,
      kind: configuration.confirmedKind,
      count: nextCount,
      reserved: nextReserved,
      updatedAt: now.toISOString(),
    }, { merge: true });
    transaction.set(tokenRef, { consumed: true, consumedAtMillis: now.getTime() }, { merge: true });
    return {
      kind: "confirmed",
      snapshot: receiptQuotaSnapshot(configuration, scanCount, nextCount, nextReserved),
    };
  });

  if (result.kind === "not-found") throw new HttpsError("not-found", tokenNotFoundMessage);
  if (result.kind === "expired") {
    throw new HttpsError("failed-precondition", "Receipt scan token expired.", { reason: "receipt_token_expired" });
  }
  return result.snapshot;
}

export const confirmReceiptScan = onCall(
  { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 30 },
  async (request): Promise<ReceiptQuotaSnapshot> => confirmReceiptScanRequest(request, {
    db: getFirestore() as unknown as QuotaFirestore,
  }),
);
