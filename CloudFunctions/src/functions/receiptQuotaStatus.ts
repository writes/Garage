import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { QuotaFirestore } from "./claudeProxy";
import { ReceiptQuotaSnapshot, receiptQuotaStatusForUser } from "./receiptQuota";

export type ReceiptQuotaStatusRequest = { auth?: { uid: string } | null };

export type ReceiptQuotaStatusDependencies = {
  db: QuotaFirestore;
  now?: () => Date;
};

export async function receiptQuotaStatusRequest(
  request: ReceiptQuotaStatusRequest,
  dependencies: ReceiptQuotaStatusDependencies,
): Promise<ReceiptQuotaSnapshot> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in.");
  return receiptQuotaStatusForUser(
    dependencies.db,
    request.auth.uid,
    (dependencies.now ?? (() => new Date()))(),
  );
}

export const receiptQuotaStatus = onCall(
  { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 30 },
  async (request): Promise<ReceiptQuotaSnapshot> => receiptQuotaStatusRequest(request, {
    db: getFirestore() as unknown as QuotaFirestore,
  }),
);
