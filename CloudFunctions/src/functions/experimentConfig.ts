import { getFirestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";

/// Server override for the client's BUNDLED experiment registry. The one job that cannot wait
/// for a TestFlight build is the EMERGENCY KILL SWITCH (a crashing design arm must be
/// revertible to control remotely), so this callable deliberately requires App Check but NOT
/// auth: the design experiment starts at first paint, before sign-in exists.
///
/// The document is server-written only (`app_config/*` is covered by the Firestore rules
/// catch-all deny; the operator writes it via the console or a script). Response shape is the
/// client registry's Codable form:
///   { definitions: [{ id, epoch, allocations: [{arm, weight}], isKilled }] }
/// Unknown ids/arms are DROPPED here rather than forwarded — the client's closed enums would
/// reject them anyway, and a typo'd experiment must not become a silent phantom.

type ExperimentConfigDocument = Record<string, unknown>;

const KNOWN_EXPERIMENTS = new Set(["design_megatest"]);
const KNOWN_ARMS = new Set(["control", "variant_a", "variant_b", "variant_c"]);

type SanitizedAllocation = { arm: string; weight: number };
type SanitizedDefinition = {
  id: string;
  epoch: number;
  allocations: SanitizedAllocation[];
  isKilled: boolean;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function sanitizedAllocation(value: unknown): SanitizedAllocation | undefined {
  if (!isRecord(value)) return undefined;
  const arm = value.arm;
  const weight = value.weight;
  if (typeof arm !== "string" || !KNOWN_ARMS.has(arm)) return undefined;
  if (typeof weight !== "number" || !Number.isFinite(weight) || weight < 0) return undefined;
  return { arm, weight };
}

/** Exported for unit tests: document data in, wire-safe registry out. */
export function sanitizedExperimentConfig(data: ExperimentConfigDocument | undefined): {
  definitions: SanitizedDefinition[];
} {
  if (!data || !Array.isArray(data.definitions)) return { definitions: [] };

  const definitions: SanitizedDefinition[] = [];
  for (const entry of data.definitions) {
    if (!isRecord(entry)) continue;
    const id = entry.id;
    const epoch = entry.epoch;
    if (typeof id !== "string" || !KNOWN_EXPERIMENTS.has(id)) continue;
    if (typeof epoch !== "number" || !Number.isInteger(epoch) || epoch < 1) continue;
    const allocations = Array.isArray(entry.allocations)
      ? entry.allocations.map(sanitizedAllocation).filter((a): a is SanitizedAllocation => a !== undefined)
      : [];
    definitions.push({
      id,
      epoch,
      allocations,
      isKilled: entry.isKilled === true,
    });
  }
  return { definitions };
}

export const experimentConfig = onCall(
  { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 10 },
  async () => {
    const snapshot = await getFirestore().collection("app_config").doc("experiments").get();
    return sanitizedExperimentConfig(snapshot.exists ? snapshot.data() : undefined);
  },
);
