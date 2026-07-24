/**
 * RULES-1 / Mechanism A' migration — per-UID vehicleCount backfill (operator-run).
 *
 * MUST run BEFORE deploying the counted-create Firestore rules (rollout order:
 * backfill -> rules -> app binary; see docs/DEPLOY_RUNBOOK.md). Without it, a legacy
 * user's next counted create would start from a missing counter (treated as 0) and
 * undercount their existing vehicles.
 *
 * Dry-run by default — prints the per-user inventory and anomaly report without writing.
 * Pass --apply to write the counters.
 *
 * Usage (needs Admin credentials):
 *   GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> \
 *     npx tsx scripts/backfillVehicleCounts.ts [--apply]
 */
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const FREE_CAP = 1;
const PRO_CAP = 5;

async function main(): Promise<void> {
  const apply = process.argv.includes("--apply");
  initializeApp();
  const db = getFirestore();

  const vehicles = await db.collection("vehicles").get();
  const countsByUid = new Map<string, number>();
  const orphanVehicleIds: string[] = [];
  let tombstoned = 0;

  for (const vehicleDoc of vehicles.docs) {
    const data = vehicleDoc.data();
    const uid = data.userId;
    if (typeof uid !== "string" || uid.length === 0) {
      orphanVehicleIds.push(vehicleDoc.id);
      continue;
    }
    // Tombstoned vehicles are pending purge; the deleteVehicle CF decrements on purge,
    // so they are NOT counted here.
    if (data.deletedAt != null) {
      tombstoned += 1;
      continue;
    }
    countsByUid.set(uid, (countsByUid.get(uid) ?? 0) + 1);
  }

  const overCap: string[] = [];
  const missingUserDoc: string[] = [];
  let written = 0;

  for (const [uid, count] of countsByUid) {
    const userRef = db.collection("users").doc(uid);
    const userSnapshot = await userRef.get();
    if (!userSnapshot.exists) missingUserDoc.push(uid);
    const subscription = userSnapshot.data()?.subscription as Record<string, unknown> | undefined;
    const isPro = subscription?.entitlement === "pro" && subscription?.isActive === true;
    if (count > (isPro ? PRO_CAP : FREE_CAP)) overCap.push(`${uid} (${count}, ${isPro ? "pro" : "free"})`);

    console.log(`${apply ? "WRITE" : "DRY"} users/${uid}.vehicleCount = ${count}`);
    if (apply) {
      await userRef.set({ vehicleCount: count }, { merge: true });
      written += 1;
    }
  }

  console.log("\n--- Backfill report ---");
  console.log(`vehicles scanned: ${vehicles.size} (tombstoned/skipped: ${tombstoned})`);
  console.log(`users counted: ${countsByUid.size}, counters written: ${written}${apply ? "" : " (dry run)"}`);
  console.log(`ANOMALY orphan vehicles (missing/empty userId): ${orphanVehicleIds.length}`);
  for (const id of orphanVehicleIds) console.log(`  vehicles/${id}`);
  console.log(`ANOMALY user docs missing (counter written on merge-create): ${missingUserDoc.length}`);
  for (const uid of missingUserDoc) console.log(`  users/${uid}`);
  console.log(`ANOMALY users over their tier cap (existing vehicles are kept; new creates will be denied): ${overCap.length}`);
  for (const line of overCap) console.log(`  ${line}`);
  if (!apply) console.log("\nDry run only — re-run with --apply to write counters.");
}

main().catch((error) => {
  console.error("backfill failed:", error);
  process.exitCode = 1;
});
