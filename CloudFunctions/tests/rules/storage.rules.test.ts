import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { getBytes, ref, uploadString } from "firebase/storage";
import { afterAll, beforeAll, describe, it } from "vitest";

let testEnvironment: RulesTestEnvironment | undefined;

describe("Storage authorization", () => {
  beforeAll(async () => {
    testEnvironment = await initializeTestEnvironment({
      projectId: "garage-rules-test",
      storage: {
        rules: readFileSync(resolve(process.cwd(), "..", "firebase.storage.rules"), "utf8"),
      },
    });
  });

  afterAll(async () => {
    await testEnvironment?.cleanup();
  });

  // The app only ever uploads photos (image/*) and receipts/reports (application/pdf); the rules
  // constrain writes to those types, so tests use a real content type.
  const pdfMeta = { contentType: "application/pdf" } as const;

  it("allows an owner to write and read image/PDF content within their own path", async () => {
    const ownerStorage = testEnvironment.authenticatedContext("owner-1").storage();
    const ownerFile = ref(ownerStorage, "users/owner-1/reports/report.pdf");

    await assertSucceeds(uploadString(ownerFile, "owner report", "raw", pdfMeta));
    await assertSucceeds(getBytes(ownerFile));
  });

  it("denies another user reading or writing an owner's path", async () => {
    const ownerStorage = testEnvironment.authenticatedContext("owner-1").storage();
    const otherStorage = testEnvironment.authenticatedContext("other-user").storage();
    const ownerFile = ref(ownerStorage, "users/owner-1/reports/private.pdf");
    const foreignFile = ref(otherStorage, "users/owner-1/reports/private.pdf");

    await assertSucceeds(uploadString(ownerFile, "private", "raw", pdfMeta));
    await assertFails(uploadString(foreignFile, "intrusion", "raw", pdfMeta));
    await assertFails(getBytes(foreignFile));
  });

  it("[RULES-ENFORCED] denies a disallowed content type even for the owner", async () => {
    const ownerStorage = testEnvironment.authenticatedContext("owner-1").storage();
    const file = ref(ownerStorage, "users/owner-1/reports/note.txt");

    await assertFails(uploadString(file, "plain text", "raw", { contentType: "text/plain" }));
  });
});
