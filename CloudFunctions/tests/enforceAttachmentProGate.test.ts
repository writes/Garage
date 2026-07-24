import "./testFirebaseConfigSetup";
import { describe, expect, it } from "vitest";
import {
  enforceAttachmentEntitlement,
  parseAttachmentUploadPath,
  type AttachmentGuardDeps,
} from "../src/functions/enforceAttachmentProGate";

describe("parseAttachmentUploadPath", () => {
  it("extracts the uid from a valid entry-attachment upload path", () => {
    expect(parseAttachmentUploadPath("users/uid123/entry-attachments/veh1/photo.jpg"))
      .toEqual({ uid: "uid123" });
  });

  it("accepts nested filenames under the vehicle segment", () => {
    expect(parseAttachmentUploadPath("users/uid123/entry-attachments/veh1/entry1/photo.jpg"))
      .toEqual({ uid: "uid123" });
  });

  it("ignores paths outside entry-attachments (e.g. gallery)", () => {
    expect(parseAttachmentUploadPath("users/uid123/gallery/veh1/photo.jpg")).toBeUndefined();
  });

  it("ignores paths that aren't rooted at users/", () => {
    expect(parseAttachmentUploadPath("public/veh1/photo.jpg")).toBeUndefined();
  });

  it("rejects malformed paths missing required segments", () => {
    expect(parseAttachmentUploadPath("users/uid123/entry-attachments")).toBeUndefined();
    expect(parseAttachmentUploadPath("users/uid123/entry-attachments/veh1")).toBeUndefined();
    expect(parseAttachmentUploadPath("users//entry-attachments/veh1/photo.jpg")).toBeUndefined();
  });

  it("rejects a uid segment that is a traversal attempt (. or ..)", () => {
    expect(parseAttachmentUploadPath("users/../entry-attachments/veh1/photo.jpg")).toBeUndefined();
    expect(parseAttachmentUploadPath("users/./entry-attachments/veh1/photo.jpg")).toBeUndefined();
  });

  it("cannot smuggle a path separator through the uid segment", () => {
    // The [^/]+ capture stops at the first "/", so this parses as a non-attachment path
    // (segment 2 is "uid123", segment 3 must literally be "entry-attachments" and isn't).
    expect(parseAttachmentUploadPath("users/uid123/../other-uid/entry-attachments/veh1/photo.jpg"))
      .toBeUndefined();
  });
});

function spyDeps(options: { isPro: boolean; failOn?: keyof AttachmentGuardDeps }) {
  const calls: string[] = [];
  const deps: AttachmentGuardDeps = {
    async isProUser(uid) {
      calls.push(`isPro:${uid}`);
      if (options.failOn === "isProUser") throw new Error("boom:isProUser");
      return options.isPro;
    },
    async deleteObject(objectName) {
      calls.push(`delete:${objectName}`);
      if (options.failOn === "deleteObject") throw new Error("boom:deleteObject");
    },
  };
  return { calls, deps };
}

describe("enforceAttachmentEntitlement", () => {
  it("keeps the file for a Pro user without deleting anything", async () => {
    const { calls, deps } = spyDeps({ isPro: true });
    const outcome = await enforceAttachmentEntitlement("uid123", "users/uid123/entry-attachments/v1/a.jpg", deps);
    expect(calls).toEqual(["isPro:uid123"]);
    expect(outcome).toEqual({ kind: "kept" });
  });

  it("deletes the file for a non-Pro user", async () => {
    const { calls, deps } = spyDeps({ isPro: false });
    const outcome = await enforceAttachmentEntitlement("uid123", "users/uid123/entry-attachments/v1/a.jpg", deps);
    expect(calls).toEqual(["isPro:uid123", "delete:users/uid123/entry-attachments/v1/a.jpg"]);
    expect(outcome).toEqual({ kind: "deleted" });
  });

  it("deletes when the user doc is missing (isProUser resolves false, fail-closed)", async () => {
    // isProUser's own contract is to resolve false — not throw — for a missing user doc (mirrors
    // userHasActiveProEntitlement(undefined, now) === false), so this is really the same path as
    // "deletes for a non-Pro user"; asserted separately to document the fail-closed default.
    const { calls, deps } = spyDeps({ isPro: false });
    const outcome = await enforceAttachmentEntitlement("ghost-uid", "users/ghost-uid/entry-attachments/v1/a.jpg", deps);
    expect(calls).toEqual(["isPro:ghost-uid", "delete:users/ghost-uid/entry-attachments/v1/a.jpg"]);
    expect(outcome).toEqual({ kind: "deleted" });
  });

  it("tolerates deleteObject already having removed the object (idempotent by contract)", async () => {
    // deleteObject's contract (see AttachmentGuardDeps) is to swallow "already gone" itself and
    // resolve normally — the concrete impl catches 404 internally. The orchestration just awaits
    // it, so a spy that resolves normally (simulating the tolerated 404) must not throw.
    const { calls, deps } = spyDeps({ isPro: false });
    await expect(
      enforceAttachmentEntitlement("uid123", "users/uid123/entry-attachments/v1/a.jpg", deps),
    ).resolves.toEqual({ kind: "deleted" });
    expect(calls).toEqual(["isPro:uid123", "delete:users/uid123/entry-attachments/v1/a.jpg"]);
  });

  it("propagates a genuine entitlement-read failure without deleting", async () => {
    const { calls, deps } = spyDeps({ isPro: false, failOn: "isProUser" });
    await expect(
      enforceAttachmentEntitlement("uid123", "users/uid123/entry-attachments/v1/a.jpg", deps),
    ).rejects.toThrow("boom:isProUser");
    expect(calls).toEqual(["isPro:uid123"]);
  });

  it("propagates a genuine (non-404) delete failure", async () => {
    const { calls, deps } = spyDeps({ isPro: false, failOn: "deleteObject" });
    await expect(
      enforceAttachmentEntitlement("uid123", "users/uid123/entry-attachments/v1/a.jpg", deps),
    ).rejects.toThrow("boom:deleteObject");
    expect(calls).toEqual(["isPro:uid123", "delete:users/uid123/entry-attachments/v1/a.jpg"]);
  });
});
