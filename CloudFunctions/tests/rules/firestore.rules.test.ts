import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  writeBatch,
  type Firestore,
} from "firebase/firestore";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";

let testEnvironment: RulesTestEnvironment | undefined;

async function seedUser(uid: string, extraFields: Record<string, unknown> = {}): Promise<void> {
  await testEnvironment?.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", uid), { displayName: uid, ...extraFields });
  });
}

/** The RULES-1 counted create: vehicle doc + users/{uid} counter transition in ONE batch. */
function countedVehicleCreate(
  db: Firestore,
  uid: string,
  vehicleId: string,
  newCount: number,
  vehicleData: Record<string, unknown> = {},
) {
  const batch = writeBatch(db);
  batch.set(doc(db, "vehicles", vehicleId), { userId: uid, nickname: vehicleId, ...vehicleData });
  batch.set(doc(db, "users", uid), {
    vehicleCount: newCount,
    lastVehicleOp: { id: vehicleId, op: "create" },
  }, { merge: true });
  return batch.commit();
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

  it("[RULES-ENFORCED] allows an owner-matched counted vehicle create and denies a spoofed owner", async () => {
    const ownerDb = testEnvironment.authenticatedContext("owner-1").firestore();
    await assertSucceeds(countedVehicleCreate(ownerDb, "owner-1", "v1", 1, { nickname: "Viper" }));

    // A spoofed owner fails even inside a correctly-counted batch.
    const batch = writeBatch(ownerDb);
    batch.set(doc(ownerDb, "vehicles", "v2"), { userId: "victim", nickname: "Spoof" });
    batch.set(doc(ownerDb, "users", "owner-1"), {
      vehicleCount: 2,
      lastVehicleOp: { id: "v2", op: "create" },
    }, { merge: true });
    await assertFails(batch.commit());
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

  // ---- RULES-1 / Mechanism A' — server-authoritative vehicle cap ----

  it("[RULES-1] denies a bare vehicle create without the counter batch", async () => {
    const ownerDb = testEnvironment.authenticatedContext("owner-1").firestore();
    await assertFails(setDoc(doc(ownerDb, "vehicles", "bare-1"), { userId: "owner-1", nickname: "Bare" }));
  });

  it("[RULES-1] allows a counted create when the user document does not exist yet (count becomes 1)", async () => {
    const ownerDb = testEnvironment.authenticatedContext("fresh-user").firestore();
    await assertSucceeds(countedVehicleCreate(ownerDb, "fresh-user", "fresh-v1", 1));
  });

  it("[RULES-1] denies a free-tier create at cap and a wrong-increment create", async () => {
    await seedUser("free-1", { vehicleCount: 1, lastVehicleOp: { id: "old", op: "create" } });
    const ownerDb = testEnvironment.authenticatedContext("free-1").firestore();
    // At cap: free tier allows 1 vehicle; count 1 -> 2 exceeds it.
    await assertFails(countedVehicleCreate(ownerDb, "free-1", "free-v2", 2));
    // Wrong increment: claiming count 1 -> 1 is not prior + 1.
    await assertFails(countedVehicleCreate(ownerDb, "free-1", "free-v2", 1));
  });

  it("[RULES-1] allows a pro create under cap and denies it at the pro cap", async () => {
    await seedUser("pro-1", {
      subscription: { entitlement: "pro", isActive: true },
      vehicleCount: 1,
    });
    const ownerDb = testEnvironment.authenticatedContext("pro-1").firestore();
    await assertSucceeds(countedVehicleCreate(ownerDb, "pro-1", "pro-v2", 2));

    await seedUser("pro-max", {
      subscription: { entitlement: "pro", isActive: true },
      vehicleCount: 5,
    });
    const maxDb = testEnvironment.authenticatedContext("pro-max").firestore();
    await assertFails(countedVehicleCreate(maxDb, "pro-max", "pro-v6", 6));
  });

  it("[RULES-1] denies a create over the free cap after a pro downgrade (isActive false)", async () => {
    await seedUser("lapsed-1", {
      subscription: { entitlement: "pro", isActive: false },
      vehicleCount: 3,
    });
    const ownerDb = testEnvironment.authenticatedContext("lapsed-1").firestore();
    await assertFails(countedVehicleCreate(ownerDb, "lapsed-1", "lapsed-v4", 4));
  });

  it("[RULES-1] denies two vehicle creates in one batch (single-create binding)", async () => {
    const ownerDb = testEnvironment.authenticatedContext("multi-1").firestore();
    const batch = writeBatch(ownerDb);
    batch.set(doc(ownerDb, "vehicles", "m-v1"), { userId: "multi-1", nickname: "First" });
    batch.set(doc(ownerDb, "vehicles", "m-v2"), { userId: "multi-1", nickname: "Second" });
    batch.set(doc(ownerDb, "users", "multi-1"), {
      vehicleCount: 2,
      lastVehicleOp: { id: "m-v2", op: "create" },
    }, { merge: true });
    await assertFails(batch.commit());
  });

  it("[RULES-1] denies standalone counter or binding writes with no vehicle create in the batch", async () => {
    await seedUser("solo-1", { vehicleCount: 1, lastVehicleOp: { id: "old", op: "create" } });
    const ownerDb = testEnvironment.authenticatedContext("solo-1").firestore();
    await assertFails(setDoc(doc(ownerDb, "users", "solo-1"), { vehicleCount: 2 }, { merge: true }));
    await assertFails(setDoc(doc(ownerDb, "users", "solo-1"), {
      lastVehicleOp: { id: "phantom", op: "create" },
    }, { merge: true }));
    await assertFails(setDoc(doc(ownerDb, "users", "solo-1"), {
      vehicleCount: 2,
      lastVehicleOp: { id: "phantom", op: "create" },
    }, { merge: true }));
  });

  it("[RULES-1] denies replaying the binding against an already-existing vehicle", async () => {
    await seedVehicle("replay-v1", "replay-1");
    await seedUser("replay-1", { vehicleCount: 1, lastVehicleOp: { id: "replay-v1", op: "create" } });
    const ownerDb = testEnvironment.authenticatedContext("replay-1").firestore();
    await assertFails(setDoc(doc(ownerDb, "users", "replay-1"), {
      vehicleCount: 2,
      lastVehicleOp: { id: "replay-v1", op: "create" },
    }, { merge: true }));
  });

  it("[RULES-1] denies a counted create over a corrupt stored counter", async () => {
    await seedUser("corrupt-1", { vehicleCount: "one" });
    const ownerDb = testEnvironment.authenticatedContext("corrupt-1").firestore();
    await assertFails(countedVehicleCreate(ownerDb, "corrupt-1", "corrupt-v1", 1));
    await assertFails(countedVehicleCreate(ownerDb, "corrupt-1", "corrupt-v1", 2));
  });

  it("[RULES-1] denies client hard-deletes but allows the owner's tombstone update", async () => {
    await seedVehicle("del-v1", "del-1");
    const ownerDb = testEnvironment.authenticatedContext("del-1").firestore();
    await assertFails(deleteDoc(doc(ownerDb, "vehicles", "del-v1")));
    await assertSucceeds(updateDoc(doc(ownerDb, "vehicles", "del-v1"), { deletedAt: new Date() }));
  });
});
