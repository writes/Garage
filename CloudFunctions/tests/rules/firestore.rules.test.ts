import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { collection, doc, getDoc, getDocs, setDoc, updateDoc } from "firebase/firestore";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";

let testEnvironment: RulesTestEnvironment | undefined;

async function seedUser(uid: string): Promise<void> {
  await testEnvironment?.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", uid), { displayName: uid });
  });
}

describe("Firestore authorization", () => {
  beforeAll(async () => {
    testEnvironment = await initializeTestEnvironment({
      projectId: "garage-rules-test",
      firestore: {
        rules: readFileSync(resolve(process.cwd(), "..", "firebase.firestore.rules"), "utf8"),
      },
    });
  });

  afterEach(async () => {
    await testEnvironment?.clearFirestore();
  });

  afterAll(async () => {
    await testEnvironment?.cleanup();
  });

  it("allows an owner to read and merge-write their own user document", async () => {
    await seedUser("owner-1");
    const ownerDb = testEnvironment.authenticatedContext("owner-1").firestore();

    await assertSucceeds(getDoc(doc(ownerDb, "users", "owner-1")));
    await assertSucceeds(setDoc(doc(ownerDb, "users", "owner-1"), { profile: { displayName: "Updated" } }, { merge: true }));
  });

  it("denies another user read, write, and list access", async () => {
    await seedUser("owner-1");
    const otherDb = testEnvironment.authenticatedContext("other-user").firestore();

    await assertFails(getDoc(doc(otherDb, "users", "owner-1")));
    await assertFails(setDoc(doc(otherDb, "users", "owner-1"), { profile: { displayName: "Intruder" } }, { merge: true }));
    await assertFails(getDocs(collection(otherDb, "users")));
  });

  it("denies unauthenticated user reads, writes, and lists", async () => {
    await seedUser("owner-1");
    const anonymousDb = testEnvironment.unauthenticatedContext().firestore();

    await assertFails(getDoc(doc(anonymousDb, "users", "owner-1")));
    await assertFails(setDoc(doc(anonymousDb, "users", "owner-1"), { profile: { displayName: "Anonymous" } }, { merge: true }));
    await assertFails(getDocs(collection(anonymousDb, "users")));
  });

  it("[RULES-ENFORCED] denies an owner client write to subscription while allowing other profile fields", async () => {
    await seedUser("owner-1");
    const ownerDb = testEnvironment.authenticatedContext("owner-1").firestore();

    await assertFails(setDoc(doc(ownerDb, "users", "owner-1"), {
      subscription: { entitlement: "pro", isActive: true },
    }, { merge: true }));

    await assertSucceeds(setDoc(doc(ownerDb, "users", "owner-1"), {
      profile: { displayName: "Owner update remains allowed" },
    }, { merge: true }));
  });

  it("[RULES-ENFORCED] denies an owner client self-grant when creating their user document", async () => {
    const ownerDb = testEnvironment.authenticatedContext("owner-1").firestore();

    await assertFails(setDoc(doc(ownerDb, "users", "owner-1"), {
      profile: { displayName: "Owner" },
      subscription: { entitlement: "pro", isActive: true },
    }));

    await assertSucceeds(setDoc(doc(ownerDb, "users", "owner-1"), {
      profile: { displayName: "Owner" },
    }));
  });

  it("[RULES-ENFORCED] leaves Admin SDK subscription writes unaffected", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users", "owner-1"), {
        subscription: { entitlement: "pro", isActive: true },
      });

      const snapshot = await getDoc(doc(context.firestore(), "users", "owner-1"));
      expect(snapshot.data()?.subscription).toEqual({ entitlement: "pro", isActive: true });
    });
  });

  async function seedVehicle(vehicleId: string, ownerUid: string): Promise<void> {
    await testEnvironment?.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "vehicles", vehicleId), { userId: ownerUid, nickname: vehicleId });
    });
  }

  it("[RULES-ENFORCED] allows an owner-matched vehicle create and denies a spoofed owner", async () => {
    const ownerDb = testEnvironment.authenticatedContext("owner-1").firestore();
    await assertSucceeds(setDoc(doc(ownerDb, "vehicles", "v1"), { userId: "owner-1", nickname: "Viper" }));
    await assertFails(setDoc(doc(ownerDb, "vehicles", "v2"), { userId: "victim", nickname: "Spoof" }));
  });

  it("[RULES-ENFORCED] denies an unauthenticated null-owner vehicle create (orphan spam)", async () => {
    const anonymousDb = testEnvironment.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(anonymousDb, "vehicles", "v3"), { userId: null, nickname: "Orphan" }));
  });

  it("[RULES-ENFORCED] forbids reassigning a vehicle userId to another account (cross-account injection)", async () => {
    await seedVehicle("v4", "owner-1");
    const ownerDb = testEnvironment.authenticatedContext("owner-1").firestore();
    await assertSucceeds(updateDoc(doc(ownerDb, "vehicles", "v4"), { nickname: "Renamed" }));
    await assertFails(updateDoc(doc(ownerDb, "vehicles", "v4"), { userId: "victim" }));
  });

  it("[RULES-ENFORCED] denies a non-owner read or write of a vehicle", async () => {
    await seedVehicle("v5", "owner-1");
    const otherDb = testEnvironment.authenticatedContext("intruder").firestore();
    await assertFails(getDoc(doc(otherDb, "vehicles", "v5")));
    await assertFails(updateDoc(doc(otherDb, "vehicles", "v5"), { nickname: "Hacked" }));
  });
});
