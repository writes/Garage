import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
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
/// reject them anyway, and a typo'd experiment must not become a silent phantom. An override
/// that re-weights an epoch already open is dropped for the same reason (see
/// `overrideRejection`): only a kill, or a fresh epoch, may change a running split.

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

/// Mirror of the client's compiled-in registry (`ExperimentRegistry.bundled`). The allocation
/// clamp below needs the CURRENT epoch and its frozen weights to judge an override; Swift's
/// ExperimentContractTests parses this file and diffs both against the Swift source, so the
/// two copies cannot drift apart silently.
const BUNDLED_REGISTRY: Record<string, { epoch: number; allocations: SanitizedAllocation[] }> = {
  design_megatest: {
    epoch: 1,
    allocations: [
      { arm: "control", weight: 1 },
      { arm: "variant_a", weight: 1 },
    ],
  },
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

/// Allocation clamp, mirrored client-side in `Garage/.../ExperimentPolicy.swift`. The
/// pre-registration freezes an epoch's split: accepting arbitrary weights under an OPEN epoch
/// changes assignment probabilities mid-flight and invalidates the SRM check for every user
/// already recorded under it. Comparison is order-sensitive — the assigner walks allocations as
/// cumulative ranges, so the same weights reordered reshuffle who lands where.
function overrideRejection(definition: SanitizedDefinition): string | undefined {
  const bundled = BUNDLED_REGISTRY[definition.id];
  if (!bundled) return "unknown_experiment";
  // The epoch-bump path stays open: a higher epoch is a new roster analyzed as fresh exposures,
  // and the binary renders only arms it actually implements.
  if (definition.epoch > bundled.epoch) return undefined;
  // A kill is always honoured — the one change that cannot wait for a build, and it only ever
  // moves users toward control.
  if (definition.isKilled) return undefined;
  if (definition.epoch < bundled.epoch) return "rolls_back_the_epoch";
  const sameWeights =
    definition.allocations.length === bundled.allocations.length &&
    definition.allocations.every((allocation, index) =>
      allocation.arm === bundled.allocations[index].arm &&
      allocation.weight === bundled.allocations[index].weight);
  return sameWeights ? undefined : "reweights_an_open_epoch";
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
    const definition: SanitizedDefinition = {
      id,
      epoch,
      allocations,
      isKilled: entry.isKilled === true,
    };
    const rejection = overrideRejection(definition);
    if (rejection) {
      logger.warn("experiment override rejected", { id, epoch, rejection });
      continue;
    }
    definitions.push(definition);
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
