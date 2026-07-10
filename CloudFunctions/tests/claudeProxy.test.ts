import { describe, expect, it } from "vitest";
import {
  DAILY_OIL_ANALYSIS_QUOTA,
  MAX_PDF_BASE64_BYTES,
  consumeDailyOilAnalysisQuota,
  parseOilAnalysisRequest,
  sanitizeOilAnalysisResponse,
} from "../src/functions/claudeProxy";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

const fixedNow = new Date("2026-07-10T20:00:00.000Z");

function dependencies(db: InMemoryFirestore, modelText = '{"labName":"Blackstone","iron":12}'): {
  apiKey: string;
  db: InMemoryFirestore;
  fetchImpl: typeof fetch;
  now: () => Date;
} {
  return {
    apiKey: "test-api-key",
    db,
    fetchImpl: async (): Promise<Response> => new Response(JSON.stringify({ content: [{ text: modelText }] }), { status: 200 }),
    now: () => fixedNow,
  };
}

async function expectHttpsError(promise: Promise<unknown>, code: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code });
}

describe("parseOilAnalysisRequest", () => {
  it("rejects base64 data larger than 10 MB before consuming quota", async () => {
    const db = new InMemoryFirestore();

    await expectHttpsError(parseOilAnalysisRequest({
      auth: { uid: "owner-1" },
      data: { pdfBase64: "a".repeat(MAX_PDF_BASE64_BYTES + 1) },
    }, dependencies(db)), "invalid-argument");

    expect(db.data("usage_quotas/owner-1_2026-07-10")).toBeUndefined();
  });

  it("enforces an atomic daily quota and uses a per-uid UTC reset key", async () => {
    const db = new InMemoryFirestore();

    for (let attempt = 0; attempt < DAILY_OIL_ANALYSIS_QUOTA; attempt += 1) {
      await expect(consumeDailyOilAnalysisQuota(db, "owner-1", fixedNow)).resolves.toBe("owner-1_2026-07-10");
    }

    await expectHttpsError(consumeDailyOilAnalysisQuota(db, "owner-1", fixedNow), "resource-exhausted");
    expect(db.data("usage_quotas/owner-1_2026-07-10")).toMatchObject({
      uid: "owner-1",
      date: "2026-07-10",
      count: DAILY_OIL_ANALYSIS_QUOTA,
    });
    await expect(consumeDailyOilAnalysisQuota(db, "owner-1", new Date("2026-07-11T00:00:00.000Z")))
      .resolves.toBe("owner-1_2026-07-11");
  });

  it("turns malformed model JSON into an internal error", async () => {
    const db = new InMemoryFirestore();

    await expectHttpsError(parseOilAnalysisRequest({
      auth: { uid: "owner-1" },
      data: { pdfBase64: "cGRm" },
    }, dependencies(db, "this is not JSON")), "internal");
  });

  it("drops unknown and incorrectly typed values while clamping finite numeric output", () => {
    const sanitized = sanitizeOilAnalysisResponse({
      labName: 123,
      iron: Number.POSITIVE_INFINITY,
      copper: -15,
      insolubles: 150,
      milesOnOil: 3_000_000,
      viscosity: { value: "bad" },
      labRecommendation: "x".repeat(4_001),
      unexpected: "must not cross the trust boundary",
    });

    expect(sanitized).toMatchObject({
      labName: "Unknown lab",
      copper: 0,
      insolubles: 100,
      milesOnOil: 2_000_000,
    });
    expect(sanitized).not.toHaveProperty("iron");
    expect(sanitized).not.toHaveProperty("viscosity");
    expect(sanitized).not.toHaveProperty("unexpected");
    expect(sanitized.labRecommendation).toHaveLength(4_000);
  });

  it("rejects unauthenticated callers", async () => {
    const db = new InMemoryFirestore();

    await expectHttpsError(parseOilAnalysisRequest({
      auth: null,
      data: { pdfBase64: "cGRm" },
    }, dependencies(db)), "unauthenticated");
  });

  it("returns only sanitized model fields", async () => {
    const db = new InMemoryFirestore();

    const result = await parseOilAnalysisRequest({
      auth: { uid: "owner-1" },
      data: { pdfBase64: "cGRm" },
    }, dependencies(db, '{"labName":"Lab","iron":8,"untrusted":true}'));

    expect(result).toEqual({ labName: "Lab", iron: 8 });
  });
});
