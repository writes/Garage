import { describe, expect, it } from "vitest";
import {
  TYPED_FIELD_NAMES,
  VALID_ENTRY_TYPES,
  buildTypedDetailTool,
  optionalParameterCount,
  sanitizeTypedDetails,
  typedFieldCount,
} from "../src/functions/typedExtraction";
import {
  VOICE_ENTRY_TOOL,
  schemaVersionFromData,
  voiceQuickAddRequest,
} from "../src/functions/voiceQuickAdd";
import { RECEIPT_ENTRY_TOOL } from "../src/functions/receiptQuickAdd";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

/**
 * Split-call wire shape: the v1 tools are byte-stable (merging typed fields into them
 * measurably destroyed common-field extraction AND strict schemas 400 above ~25 optional
 * params — typedExtraction.ts header), and every per-type detail tool stays tiny.
 */
describe("split-call tool shapes", () => {
  it("leaves the v1 tools byte-stable: 7 and 9 properties", () => {
    expect(Object.keys(VOICE_ENTRY_TOOL.input_schema.properties)).toHaveLength(7);
    expect(Object.keys(RECEIPT_ENTRY_TOOL.input_schema.properties)).toHaveLength(9);
  });

  it("caps every per-type detail tool at 5 optional parameters (tire is the widest)", () => {
    for (const entryType of VALID_ENTRY_TYPES) {
      const tool = buildTypedDetailTool(entryType);
      if (tool) expect(optionalParameterCount(tool)).toBeLessThanOrEqual(5);
    }
    expect(optionalParameterCount(buildTypedDetailTool("tire")!)).toBe(5);
  });

  it("returns no tool for types with no typed fields — the second call is skipped", () => {
    for (const entryType of ["fuel", "track_day", "dme_report", "alignment", "oil_analysis"] as const) {
      expect(buildTypedDetailTool(entryType)).toBeNull();
    }
  });

  it("every typed field appears in at least one per-type tool", () => {
    const covered = new Set<string>();
    for (const entryType of VALID_ENTRY_TYPES) {
      const tool = buildTypedDetailTool(entryType);
      for (const name of Object.keys(tool?.input_schema.properties ?? {})) covered.add(name);
    }
    expect([...covered].sort()).toEqual([...TYPED_FIELD_NAMES].sort());
  });
});

describe("schemaVersionFromData", () => {
  it("returns 2 only for an exact numeric 2", () => {
    expect(schemaVersionFromData({ schemaVersion: 2 })).toBe(2);
    expect(schemaVersionFromData({ schemaVersion: "2" })).toBe(1);
    expect(schemaVersionFromData({ schemaVersion: 3 })).toBe(1);
    expect(schemaVersionFromData({})).toBe(1);
    expect(schemaVersionFromData(undefined)).toBe(1);
  });
});

describe("sanitizeTypedDetails", () => {
  const fullTireInput = {
    brand: "Michelin",
    productModel: "Pilot Sport 4S",
    serviceAction: "new_install",
    tireSizeFront: "245/40R18",
    tireSizeRear: "275/35R18",
  };

  it("passes a full valid tire payload through untouched", () => {
    const details = sanitizeTypedDetails(fullTireInput, "tire");
    expect(details.brand).toBe("Michelin");
    expect(details.productModel).toBe("Pilot Sport 4S");
    expect(details.serviceAction).toBe("new_install");
    expect(details.tireSizeFront).toBe("245/40R18");
    expect(details.tireSizeRear).toBe("275/35R18");
    expect(typedFieldCount(details)).toBe(5);
  });

  it("nulls every field foreign to the proposal's entry type (cross-type leakage dies here)", () => {
    const details = sanitizeTypedDetails(
      { ...fullTireInput, quantityQuarts: 5, workItem: "spark plugs" },
      "brake",
    );
    // brake keeps brand, but a TIRE action on a brake entry is nulled (per-type verbs)…
    expect(details.brand).toBe("Michelin");
    expect(details.serviceAction).toBeNull();
    // …but tire-only, fuel-only and maintenance-only fields are nulled regardless of validity.
    expect(details.productModel).toBeNull();
    expect(details.tireSizeFront).toBeNull();
    expect(details.quantityQuarts).toBeNull();
    expect(details.workItem).toBeNull();
  });

  it("nulls out-of-range numbers instead of clamping them", () => {
    const details = sanitizeTypedDetails(
      { quantityQuarts: 41, nextDueOdometer: -2 },
      "oil_change",
    );
    expect(details.quantityQuarts).toBeNull();
    expect(details.nextDueOdometer).toBeNull();
  });

  it("nulls oversize strings instead of truncating them (a chopped brand is corrupted data)", () => {
    const details = sanitizeTypedDetails({ brand: "B".repeat(81), oilGrade: "0W-40" }, "oil_change");
    expect(details.brand).toBeNull();
    expect(details.oilGrade).toBe("0W-40");
  });

  it("requires safe integers for nextDueOdometer — a fractional value is nulled, not floored", () => {
    expect(sanitizeTypedDetails({ nextDueOdometer: 65000.5 }, "maintenance").nextDueOdometer).toBeNull();
    expect(sanitizeTypedDetails({ nextDueOdometer: 65000 }, "maintenance").nextDueOdometer).toBe(65000);
  });

  it("nulls off-enum values (belt-and-braces under strict mode)", () => {
    const details = sanitizeTypedDetails(
      { serviceAction: "caliper_paint", upgradeCategory: "stance" },
      "brake",
    );
    expect(details.serviceAction).toBeNull();
    expect(details.upgradeCategory).toBeNull();
  });

  it("tolerates a non-record input", () => {
    const details = sanitizeTypedDetails("not a record", "tire");
    for (const field of TYPED_FIELD_NAMES) expect(details[field]).toBeNull();
  });
});

/** The v1/v2 response split, end to end through the request path with a fake two-call model. */
describe("voiceQuickAddRequest schema versioning", () => {
  const fixedNow = new Date("2026-07-21T20:00:00.000Z");
  const commonInput: Record<string, unknown> = { entryType: "tire", cost: 800, shopName: "Discount Tire" };
  const typedInput: Record<string, unknown> = { brand: "Michelin", serviceAction: "new_install" };

  /** Serves call 1 (record_entry) then call 2 (record_entry_details), recording each body. */
  function dependencies(db: InMemoryFirestore, calls: unknown[] = [], typedStatus = 200) {
    return {
      // Short deliberately: tri_review's secret screen flags quoted credential-shaped
      // values ≥12 chars, even fakes.
      apiKey: "test-key",
      db,
      fetchImpl: (async (_url: unknown, init?: { body?: unknown }) => {
        calls.push(JSON.parse(String(init?.body ?? "{}")));
        if (calls.length === 1) {
          return new Response(
            JSON.stringify({ content: [{ type: "tool_use", name: "record_entry", input: commonInput }] }),
            { status: 200 },
          );
        }
        return new Response(
          JSON.stringify({ content: [{ type: "tool_use", name: "record_entry_details", input: typedInput }] }),
          { status: typedStatus },
        );
      }) as unknown as typeof fetch,
      now: () => fixedNow,
    };
  }

  function seedActivePro(db: InMemoryFirestore, uid = "owner-1"): void {
    db.seed(`users/${uid}`, {
      subscription: { entitlement: "pro", isActive: true, expiresAt: "2026-08-01T00:00:00.000Z" },
    });
  }

  it("a v1 request makes ONE call and gets the legacy shape with no typed keys", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const calls: unknown[] = [];
    const proposal = await voiceQuickAddRequest(
      { auth: { uid: "owner-1" }, data: { transcript: "four new michelins" } },
      dependencies(db, calls),
    );
    expect(calls).toHaveLength(1);
    expect(proposal.entryType).toBe("tire");
    expect("brand" in proposal).toBe(false);
    expect("proposalSchemaVersion" in proposal).toBe(false);
  });

  it("a v2 request makes a second narrow call and returns typed fields flat + version marker", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const calls: Array<Record<string, unknown>> = [];
    const proposal = await voiceQuickAddRequest(
      { auth: { uid: "owner-1" }, data: { transcript: "four new michelins", schemaVersion: 2 } },
      dependencies(db, calls),
    );
    expect(calls).toHaveLength(2);
    // Call 1 must be BYTE-IDENTICAL to v1 config: the 7-field tool, never a widened one.
    const call1Tools = calls[0].tools as Array<{ input_schema: { properties: Record<string, unknown> } }>;
    expect(Object.keys(call1Tools[0].input_schema.properties)).toHaveLength(7);
    // Call 2 carries only fuel's fields.
    const call2Tools = calls[1].tools as Array<{ name: string; input_schema: { properties: Record<string, unknown> } }>;
    expect(call2Tools[0].name).toBe("record_entry_details");
    expect(Object.keys(call2Tools[0].input_schema.properties).sort()).toEqual([
      "brand", "productModel", "serviceAction", "tireSizeFront", "tireSizeRear",
    ]);
    expect(proposal).toMatchObject({
      entryType: "tire", cost: 800, shopName: "Discount Tire",
      brand: "Michelin", serviceAction: "new_install",
      proposalSchemaVersion: 2,
    });
    // Foreign-type typed fields come back explicitly null, not absent — the client contract
    // is "flat object, every typed key present" on v2.
    expect((proposal as Record<string, unknown>).workItem).toBeNull();
  });

  it("a failed second call degrades to all-null typed fields, never sinking the proposal", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const proposal = await voiceQuickAddRequest(
      { auth: { uid: "owner-1" }, data: { transcript: "four new michelins", schemaVersion: 2 } },
      dependencies(db, [], 500),
    );
    expect(proposal).toMatchObject({ entryType: "tire", cost: 800, proposalSchemaVersion: 2 });
    expect((proposal as Record<string, unknown>).brand).toBeNull();
  });
});
