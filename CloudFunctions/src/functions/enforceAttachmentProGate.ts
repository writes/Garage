import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as logger from "firebase-functions/logger";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { userHasActiveProEntitlement } from "./claudeProxy";

/**
 * Attachments are gated to Pro in the client UI, but Storage security rules can't read Firestore
 * (firebase.storage.rules only checks request.auth.uid against the path — see the owner-only
 * write rule), so a non-Pro user hitting the Storage REST/SDK API directly bypasses that client
 * gate entirely. Entitlements are server-authoritative (doctrine): this trigger is the actual
 * enforcement point. It's necessarily ASYNC — unlike a synchronous security rule, it can't block
 * the upload itself, only react after the object lands — but it stays FAIL-CLOSED on the
 * entitlement question: userHasActiveProEntitlement(undefined, now) is false, so an unreadable or
 * missing users/{uid} doc is treated as "not Pro" and the object is removed, never kept by
 * default. (A genuine Firestore/Storage infrastructure error below is a different failure mode —
 * it's logged and rethrown for retry, the same as every other trigger in this file set, rather
 * than being coerced into a delete.)
 */

export interface AttachmentUploadPath {
  uid: string;
}

const ATTACHMENT_PATH_PATTERN = /^users\/([^/]+)\/entry-attachments\/[^/]+\/.+$/;

/**
 * Cheap, pure gate: is this Storage object an entry attachment upload, and whose? Every other
 * object (gallery photos, PDF exports, or anything outside
 * users/{uid}/entry-attachments/{vehicleId}/...) returns undefined so the trigger can skip past
 * it without ever touching Firestore.
 */
export function parseAttachmentUploadPath(objectName: string): AttachmentUploadPath | undefined {
  const match = ATTACHMENT_PATH_PATTERN.exec(objectName);
  if (!match) return undefined;
  const uid = match[1];
  // The capture group already excludes "/" — no segment can smuggle a path separator and escape
  // into another uid's tree. This additionally refuses a uid of exactly "." or ".." (never a real
  // Firebase uid); treating those as unparseable is simpler and safer than deciding what they'd
  // even mean for a Firestore doc lookup.
  if (uid.length === 0 || uid === "." || uid === "..") return undefined;
  return { uid };
}

/// Each step is injected so the entitlement decision is unit-tested without touching real
/// Firestore/Storage.
export interface AttachmentGuardDeps {
  /** Whether `uid` currently holds an active Pro entitlement. A missing/unreadable user doc must
   * resolve to false (fail-closed), not throw — see userHasActiveProEntitlement's undefined case. */
  isProUser(uid: string): Promise<boolean>;
  /** Delete the object. Idempotent: must tolerate the object already being gone (a retried
   * delivery, or a race with deleteVehicle/deleteAccount's own purge of the same prefix). */
  deleteObject(objectName: string): Promise<void>;
}

export type AttachmentGuardOutcome = { kind: "kept" } | { kind: "deleted" };

export async function enforceAttachmentEntitlement(
  uid: string,
  objectName: string,
  deps: AttachmentGuardDeps,
): Promise<AttachmentGuardOutcome> {
  const isPro = await deps.isProUser(uid);
  if (isPro) {
    return { kind: "kept" };
  }
  await deps.deleteObject(objectName);
  return { kind: "deleted" };
}

/** How the Node Storage client (@google-cloud/storage / google-gax) surfaces "object not found". */
function isStorageNotFoundError(error: unknown): boolean {
  return typeof error === "object" && error !== null && (error as { code?: unknown }).code === 404;
}

export const enforceAttachmentProGate = onObjectFinalized(
  { region: "us-central1", memory: "256MiB" },
  async (event) => {
    const objectName = event.data.name;
    const parsed = parseAttachmentUploadPath(objectName);
    if (!parsed) return; // not an entry-attachment upload — cheap skip, no Firestore/Storage call

    const db = getFirestore();
    const bucket = getStorage().bucket();
    try {
      const outcome = await enforceAttachmentEntitlement(parsed.uid, objectName, {
        async isProUser(uid) {
          const doc = await db.collection("users").doc(uid).get();
          return userHasActiveProEntitlement(doc.exists ? doc.data() : undefined, new Date());
        },
        async deleteObject(name) {
          try {
            await bucket.file(name).delete();
          } catch (error) {
            if (!isStorageNotFoundError(error)) throw error;
          }
        },
      });

      if (outcome.kind === "deleted") {
        logger.warn("attachment upload without pro entitlement removed", {
          uid: parsed.uid,
          name: objectName,
          reason: "attachment-upload-without-pro",
        });
      }
    } catch (error) {
      logger.error("attachment pro-gate enforcement failed", {
        uid: parsed.uid,
        name: objectName,
        message: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  },
);
