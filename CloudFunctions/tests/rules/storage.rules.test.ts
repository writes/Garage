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

  it("allows an owner to write and read within their own path", async () => {
    const ownerStorage = testEnvironment.authenticatedContext("owner-1").storage();
    const ownerFile = ref(ownerStorage, "users/owner-1/reports/report.txt");

    await assertSucceeds(uploadString(ownerFile, "owner report"));
    await assertSucceeds(getBytes(ownerFile));
  });

  it("denies another user reading or writing an owner's path", async () => {
    const ownerStorage = testEnvironment.authenticatedContext("owner-1").storage();
    const otherStorage = testEnvironment.authenticatedContext("other-user").storage();
    const ownerFile = ref(ownerStorage, "users/owner-1/reports/private.txt");
    const foreignFile = ref(otherStorage, "users/owner-1/reports/private.txt");

    await assertSucceeds(uploadString(ownerFile, "private"));
    await assertFails(uploadString(foreignFile, "intrusion"));
    await assertFails(getBytes(foreignFile));
  });
});
