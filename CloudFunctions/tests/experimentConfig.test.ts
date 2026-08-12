import { describe, expect, it } from "vitest";
import { sanitizedExperimentConfig } from "../src/functions/experimentConfig";

describe("sanitizedExperimentConfig", () => {
  it("returns an empty registry for a missing or shapeless document", () => {
    expect(sanitizedExperimentConfig(undefined)).toEqual({ definitions: [] });
    expect(sanitizedExperimentConfig({})).toEqual({ definitions: [] });
    expect(sanitizedExperimentConfig({ definitions: "nope" })).toEqual({ definitions: [] });
  });

  it("passes a well-formed definition through, including the kill switch", () => {
    const result = sanitizedExperimentConfig({
      definitions: [{
        id: "design_megatest",
        epoch: 2,
        allocations: [
          { arm: "control", weight: 1 },
          { arm: "variant_a", weight: 1 },
        ],
        isKilled: true,
      }],
    });
    expect(result.definitions).toHaveLength(1);
    expect(result.definitions[0]).toEqual({
      id: "design_megatest",
      epoch: 2,
      allocations: [
        { arm: "control", weight: 1 },
        { arm: "variant_a", weight: 1 },
      ],
      isKilled: true,
    });
  });

  // Epoch 2 (above the bundled epoch) so the allocation clamp lets the sanitized roster
  // through — this case is about arm/weight sanitization, not the clamp.
  it("drops unknown experiments, unknown arms, and malformed weights instead of forwarding them", () => {
    const result = sanitizedExperimentConfig({
      definitions: [
        { id: "phantom_experiment", epoch: 1, allocations: [], isKilled: false },
        {
          id: "design_megatest",
          epoch: 2,
          allocations: [
            { arm: "variant_z", weight: 1 },
            { arm: "control", weight: -3 },
            { arm: "control", weight: Number.NaN },
            { arm: "variant_a", weight: 2 },
          ],
          isKilled: false,
        },
      ],
    });
    expect(result.definitions).toHaveLength(1);
    expect(result.definitions[0].allocations).toEqual([{ arm: "variant_a", weight: 2 }]);
  });

  it("rejects non-integer or sub-1 epochs and non-boolean kill flags fail closed to false", () => {
    const result = sanitizedExperimentConfig({
      definitions: [
        { id: "design_megatest", epoch: 0, allocations: [], isKilled: false },
        { id: "design_megatest", epoch: 1.5, allocations: [], isKilled: false },
        { id: "design_megatest", epoch: 3, allocations: [], isKilled: "yes" },
      ],
    });
    expect(result.definitions).toHaveLength(1);
    expect(result.definitions[0].epoch).toBe(3);
    expect(result.definitions[0].isKilled).toBe(false);
  });
});

/// Allocation clamp: the bundled registry mirror pins design_megatest to epoch 1 at
/// control/variant_a 1:1. Re-weighting that OPEN epoch invalidates the SRM check and every
/// assignment probability already recorded under it.
describe("sanitizedExperimentConfig allocation clamp", () => {
  const bundledAllocations = [
    { arm: "control", weight: 1 },
    { arm: "variant_a", weight: 1 },
  ];

  const definition = (overrides: Record<string, unknown>) =>
    sanitizedExperimentConfig({
      definitions: [{
        id: "design_megatest",
        epoch: 1,
        allocations: bundledAllocations,
        isKilled: false,
        ...overrides,
      }],
    }).definitions;

  it("rejects a same-epoch reweight", () => {
    expect(definition({ allocations: [{ arm: "control", weight: 1 }, { arm: "variant_a", weight: 9 }] }))
      .toEqual([]);
  });

  it("rejects a same-epoch roster change even when the weights are unchanged", () => {
    expect(definition({ allocations: [{ arm: "control", weight: 1 }] })).toEqual([]);
    expect(definition({ allocations: [] })).toEqual([]);
  });

  it("rejects a same-epoch reorder — allocation order decides who lands where", () => {
    expect(definition({
      allocations: [{ arm: "variant_a", weight: 1 }, { arm: "control", weight: 1 }],
    })).toEqual([]);
  });

  it("rejects rescaled weights that describe the same split", () => {
    expect(definition({
      allocations: [{ arm: "control", weight: 50 }, { arm: "variant_a", weight: 50 }],
    })).toEqual([]);
  });

  it("accepts a same-epoch override that exactly restates the bundled allocation", () => {
    expect(definition({})).toHaveLength(1);
  });

  it("accepts a kill at the open epoch, whatever weights it carries", () => {
    const killed = definition({
      isKilled: true,
      allocations: [{ arm: "variant_a", weight: 7 }],
    });
    expect(killed).toHaveLength(1);
    expect(killed[0].isKilled).toBe(true);
  });

  it("accepts a higher-epoch reweight — the epoch-bump path stays open", () => {
    const bumped = definition({
      epoch: 2,
      allocations: [{ arm: "control", weight: 3 }, { arm: "variant_a", weight: 1 }],
    });
    expect(bumped).toHaveLength(1);
    expect(bumped[0].epoch).toBe(2);
    expect(bumped[0].allocations).toEqual([{ arm: "control", weight: 3 }, { arm: "variant_a", weight: 1 }]);
  });

  // The epoch sanitizer runs BEFORE the kill fast-path, so a malformed epoch voids a kill too:
  // an operator reaching for the emergency stop must still write a well-formed document.
  // (`rolls_back_the_epoch` — an override BELOW the bundled epoch — is unreachable while the
  // bundled epoch is 1; ExperimentPolicyTests covers that rule on the Swift side, where the
  // bundled definition is injectable.)
  it("refuses a kill carrying a malformed epoch", () => {
    expect(sanitizedExperimentConfig({
      definitions: [{ id: "design_megatest", epoch: 0, allocations: bundledAllocations, isKilled: true }],
    }).definitions).toEqual([]);
  });
});
