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

  it("drops unknown experiments, unknown arms, and malformed weights instead of forwarding them", () => {
    const result = sanitizedExperimentConfig({
      definitions: [
        { id: "phantom_experiment", epoch: 1, allocations: [], isKilled: false },
        {
          id: "design_megatest",
          epoch: 1,
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
