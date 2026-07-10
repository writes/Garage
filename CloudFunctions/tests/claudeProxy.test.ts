import { describe, expect, it } from "vitest";
import {
  DAILY_OIL_ANALYSIS_QUOTA,
  MAX_PDF_BASE64_BYTES,
  consumeDailyOilAnalysisQuota,
  parseOilAnalysisRequest,
  refundDailyOilAnalysisQuota,
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

  it("does not refund quota-exceeded requests because no unit was consumed", async () => {
    const db = new InMemoryFirestore();

    for (let attempt = 0; attempt < DAILY_OIL_ANALYSIS_QUOTA; attempt += 1) {
      await consumeDailyOilAnalysisQuota(db, "owner-1", fixedNow);
    }

    await expectHttpsError(parseOilAnalysisRequest({
      auth: { uid: "owner-1" },
      data: { pdfBase64: "cGRm" },
    }, dependencies(db)), "resource-exhausted");

    expect(db.data("usage_quotas/owner-1_2026-07-10")).toMatchObject({
      count: DAILY_OIL_ANALYSIS_QUOTA,
    });
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

  it("floors a quota refund at zero", async () => {
    const db = new InMemoryFirestore();

    await refundDailyOilAnalysisQuota(db, "owner-1", fixedNow);

    expect(db.data("usage_quotas/owner-1_2026-07-10")).toMatchObject({ count: 0 });
  });

  it("refunds consumed quota when Anthropic returns a non-success response", async () => {
    const db = new InMemoryFirestore();
    const requestDependencies = dependencies(db);
    requestDependencies.fetchImpl = async (): Promise<Response> => new Response("upstream unavailable", { status: 500 });

    await expectHttpsError(parseOilAnalysisRequest({
      auth: { uid: "owner-1" },
      data: { pdfBase64: "cGRm" },
    }, requestDependencies), "internal");

    expect(db.data("usage_quotas/owner-1_2026-07-10")).toMatchObject({ count: 0 });
  });

  it("refunds consumed quota when the Anthropic request throws", async () => {
    const db = new InMemoryFirestore();
    const requestDependencies = dependencies(db);
    requestDependencies.fetchImpl = async (): Promise<Response> => {
      throw new Error("network unavailable");
    };

    await expectHttpsError(parseOilAnalysisRequest({
      auth: { uid: "owner-1" },
      data: { pdfBase64: "cGRm" },
    }, requestDependencies), "internal");

    expect(db.data("usage_quotas/owner-1_2026-07-10")).toMatchObject({ count: 0 });
  });

  it("keeps consumed quota when an HTTP-OK model response is malformed", async () => {
    const db = new InMemoryFirestore();

    await expectHttpsError(parseOilAnalysisRequest({
      auth: { uid: "owner-1" },
      data: { pdfBase64: "cGRm" },
    }, dependencies(db, "this is not JSON")), "internal");

    expect(db.data("usage_quotas/owner-1_2026-07-10")).toMatchObject({ count: 1 });
  });

  it("turns invalid present numeric output into null rather than fabricating a clamped value", () => {
    const sanitized = sanitizeOilAnalysisResponse({
      labName: "Lab",
      iron: Number.NaN,
      copper: -15,
      insolubles: 150,
      milesOnOil: 3_000_000,
      viscosity: { value: "bad" },
      labRecommendation: "x".repeat(4_001),
      unexpected: "must not cross the trust boundary",
    });

    expect(sanitized).toMatchObject({
      labName: "Lab",
      iron: null,
      copper: null,
      insolubles: null,
      milesOnOil: null,
    });
    expect(sanitized).not.toHaveProperty("viscosity");
    expect(sanitized).not.toHaveProperty("unexpected");
    expect(sanitized.labRecommendation).toHaveLength(4_000);
  });

  it("rejects empty, array, and unrelated model JSON instead of returning a hollow analysis", async () => {
    for (const modelText of ["{}", "[]", '{"unrelated":"payload"}']) {
      const db = new InMemoryFirestore();

      await expect(parseOilAnalysisRequest({
        auth: { uid: "owner-1" },
        data: { pdfBase64: "cGRm" },
      }, dependencies(db, modelText))).rejects.toMatchObject({
        code: "internal",
        message: "unrecognized analysis response",
      });
      expect(db.data("usage_quotas/owner-1_2026-07-10")).toMatchObject({ count: 1 });
    }
  });

  it("returns null for an out-of-range model number when the report otherwise has a lab signal", async () => {
    const db = new InMemoryFirestore();

    const result = await parseOilAnalysisRequest({
      auth: { uid: "owner-1" },
      data: { pdfBase64: "cGRm" },
    }, dependencies(db, '{"labName":"Lab","copper":-15}'));

    expect(result).toEqual({ labName: "Lab", copper: null });
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
