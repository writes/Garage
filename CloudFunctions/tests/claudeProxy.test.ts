import { describe, expect, it } from "vitest";
import {
  DAILY_OIL_ANALYSIS_QUOTA,
  FREE_LIFETIME_OIL_ANALYSIS_QUOTA,
  MAX_PDF_BASE64_BYTES,
  parseOilAnalysisRequest,
  sanitizeOilAnalysisResponse,
} from "../src/functions/claudeProxy";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

const fixedNow = new Date("2026-07-10T20:00:00.000Z");
const validPdfBase64 = Buffer.from("%PDF-1.7\n", "utf8").toString("base64");

type DependencyOptions = {
  modelText?: string;
  now?: Date;
};

function dependencies(
  db: InMemoryFirestore,
  { modelText = '{"labName":"Blackstone","iron":12}', now = fixedNow }: DependencyOptions = {},
): {
  apiKey: string;
  db: InMemoryFirestore;
  fetchImpl: typeof fetch;
  now: () => Date;
} {
  return {
    apiKey: "test-api-key",
    db,
    fetchImpl: async (): Promise<Response> => new Response(JSON.stringify({ content: [{ text: modelText }] }), { status: 200 }),
    now: () => now,
  };
}

function request(uid = "owner-1", pdfBase64 = validPdfBase64): {
  auth: { uid: string };
  data: { pdfBase64: string };
} {
  return {
    auth: { uid },
    data: { pdfBase64 },
  };
}

function seedActivePro(db: InMemoryFirestore, uid = "owner-1", expiresAt: unknown = "2026-07-12T00:00:00.000Z"): void {
  db.seed(`users/${uid}`, {
    subscription: {
      entitlement: "pro",
      isActive: true,
      expiresAt,
    },
  });
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

    expect(db.data("usage_quotas/owner-1_lifetime")).toBeUndefined();
    expect(db.data("usage_quotas/owner-1_2026-07-10")).toBeUndefined();
  });

  it("rejects a bad PDF signature before quota reservation or upstream fetch", async () => {
    const db = new InMemoryFirestore();
    const requestDependencies = dependencies(db);
    let fetchCalls = 0;
    requestDependencies.fetchImpl = async (): Promise<Response> => {
      fetchCalls += 1;
      return new Response("unexpected", { status: 500 });
    };

    await expectHttpsError(
      parseOilAnalysisRequest(request("owner-1", Buffer.from("not a PDF", "utf8").toString("base64")), requestDependencies),
      "invalid-argument",
    );

    expect(fetchCalls).toBe(0);
    expect(db.data("usage_quotas/owner-1_lifetime")).toBeUndefined();
    expect(db.data("usage_quotas/owner-1_2026-07-10")).toBeUndefined();
  });

  it("uses a ten-unit free lifetime bucket across UTC days and reports typed exhaustion", async () => {
    const db = new InMemoryFirestore();
    const dates = Array.from(
      { length: FREE_LIFETIME_OIL_ANALYSIS_QUOTA },
      (_, index) => new Date(Date.UTC(2026, 6, 1 + index, 12, 0, 0)),
    );

    for (const now of dates) {
      await expect(parseOilAnalysisRequest(request(), dependencies(db, { now }))).resolves.toMatchObject({ labName: "Blackstone" });
      expect(db.data(`usage_quotas/owner-1_${now.toISOString().slice(0, 10)}`)).toBeUndefined();
    }

    expect(db.data("usage_quotas/owner-1_lifetime")).toMatchObject({
      uid: "owner-1",
      kind: "oil_analysis_lifetime",
      count: FREE_LIFETIME_OIL_ANALYSIS_QUOTA,
    });

    await expect(parseOilAnalysisRequest(request(), dependencies(db, {
      now: new Date("2026-07-20T12:00:00.000Z"),
    }))).rejects.toMatchObject({
      code: "resource-exhausted",
      details: {
        reason: "free_lifetime_exhausted",
        entitlementUsed: "free",
      },
    });
    expect(db.data("usage_quotas/owner-1_2026-07-20")).toBeUndefined();
  });

  it("uses the free bucket for inactive, wrong, and malformed subscriptions", async () => {
    const subscriptions: ReadonlyArray<[string, unknown]> = [
      ["inactive", { entitlement: "pro", isActive: false }],
      ["wrong entitlement", { entitlement: "other", isActive: true }],
      ["malformed", { entitlement: "pro", isActive: "true" }],
      ["malformed map", "not-a-subscription-map"],
    ];

    for (const [label, subscription] of subscriptions) {
      const uid = `owner-${label}`;
      const db = new InMemoryFirestore();
      db.seed(`users/${uid}`, { subscription });

      await expect(parseOilAnalysisRequest(request(uid), dependencies(db))).resolves.toMatchObject({ labName: "Blackstone" });
      expect(db.data(`usage_quotas/${uid}_lifetime`)).toMatchObject({ count: 1 });
      expect(db.data(`usage_quotas/${uid}_2026-07-10`)).toBeUndefined();
    }
  });

  it("selects the entitlement tier and reserves its bucket in one strict transaction", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);

    await expect(parseOilAnalysisRequest(request(), dependencies(db))).resolves.toMatchObject({ labName: "Blackstone" });

    expect(db.transactionTraces()).toEqual([
      {
        reads: ["users/owner-1", "usage_quotas/owner-1_2026-07-10"],
        writes: ["usage_quotas/owner-1_2026-07-10"],
      },
    ]);
  });

  it("enforces the pro daily quota with an exact next-UTC-midnight reset and resets the next day", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);

    for (let attempt = 0; attempt < DAILY_OIL_ANALYSIS_QUOTA; attempt += 1) {
      await expect(parseOilAnalysisRequest(request(), dependencies(db))).resolves.toMatchObject({ labName: "Blackstone" });
    }

    await expect(parseOilAnalysisRequest(request(), dependencies(db))).rejects.toMatchObject({
      code: "resource-exhausted",
      details: {
        reason: "pro_daily_exhausted",
        entitlementUsed: "pro",
        resetAt: "2026-07-11T00:00:00.000Z",
      },
    });
    expect(db.data("usage_quotas/owner-1_2026-07-10")).toMatchObject({
      uid: "owner-1",
      date: "2026-07-10",
      count: DAILY_OIL_ANALYSIS_QUOTA,
    });
    expect(db.data("usage_quotas/owner-1_lifetime")).toBeUndefined();

    await expect(parseOilAnalysisRequest(request(), dependencies(db, {
      now: new Date("2026-07-11T00:00:00.000Z"),
    }))).resolves.toMatchObject({ labName: "Blackstone" });
    expect(db.data("usage_quotas/owner-1_2026-07-11")).toMatchObject({ count: 1 });
  });

  it("treats an expired or malformed pro expiration as free", async () => {
    const expirationValues: ReadonlyArray<unknown> = [
      "2026-07-10T19:59:59.999Z",
      "not-a-timestamp",
    ];

    for (const [index, expiresAt] of expirationValues.entries()) {
      const uid = `expired-owner-${index}`;
      const db = new InMemoryFirestore();
      seedActivePro(db, uid, expiresAt);

      await expect(parseOilAnalysisRequest(request(uid), dependencies(db))).resolves.toMatchObject({ labName: "Blackstone" });
      expect(db.data(`usage_quotas/${uid}_lifetime`)).toMatchObject({ count: 1 });
      expect(db.data(`usage_quotas/${uid}_2026-07-10`)).toBeUndefined();
    }
  });

  it("preserves free lifetime usage through pro and back to free", async () => {
    const db = new InMemoryFirestore();

    for (let attempt = 0; attempt < 3; attempt += 1) {
      await expect(parseOilAnalysisRequest(request(), dependencies(db))).resolves.toMatchObject({ labName: "Blackstone" });
    }
    expect(db.data("usage_quotas/owner-1_lifetime")).toMatchObject({ count: 3 });

    seedActivePro(db);
    await expect(parseOilAnalysisRequest(request(), dependencies(db))).resolves.toMatchObject({ labName: "Blackstone" });
    expect(db.data("usage_quotas/owner-1_lifetime")).toMatchObject({ count: 3 });
    expect(db.data("usage_quotas/owner-1_2026-07-10")).toMatchObject({ count: 1 });

    db.seed("users/owner-1", {
      subscription: { entitlement: "pro", isActive: false },
    });
    for (let attempt = 0; attempt < 7; attempt += 1) {
      await expect(parseOilAnalysisRequest(request(), dependencies(db))).resolves.toMatchObject({ labName: "Blackstone" });
    }
    expect(db.data("usage_quotas/owner-1_lifetime")).toMatchObject({ count: FREE_LIFETIME_OIL_ANALYSIS_QUOTA });

    await expect(parseOilAnalysisRequest(request(), dependencies(db))).rejects.toMatchObject({
      code: "resource-exhausted",
      details: {
        reason: "free_lifetime_exhausted",
        entitlementUsed: "free",
      },
    });
  });

  it("refunds the consumed free lifetime bucket after an upstream network failure", async () => {
    const db = new InMemoryFirestore();
    const requestDependencies = dependencies(db);
    requestDependencies.fetchImpl = async (): Promise<Response> => {
      seedActivePro(db);
      throw new Error("network unavailable");
    };

    await expectHttpsError(parseOilAnalysisRequest(request(), requestDependencies), "internal");

    expect(db.data("usage_quotas/owner-1_lifetime")).toMatchObject({ count: 0 });
    expect(db.data("usage_quotas/owner-1_2026-07-10")).toBeUndefined();
  });

  it("refunds the consumed pro daily bucket after an upstream 5xx failure", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const requestDependencies = dependencies(db);
    requestDependencies.fetchImpl = async (): Promise<Response> => {
      db.seed("users/owner-1", {
        subscription: { entitlement: "pro", isActive: false },
      });
      return new Response("upstream unavailable", { status: 500 });
    };

    await expectHttpsError(parseOilAnalysisRequest(request(), requestDependencies), "internal");

    expect(db.data("usage_quotas/owner-1_2026-07-10")).toMatchObject({ count: 0 });
    expect(db.data("usage_quotas/owner-1_lifetime")).toBeUndefined();
  });

  it("does not refund billed HTTP-OK unrecognized output for either tier", async () => {
    for (const entitlementUsed of ["free", "pro"] as const) {
      for (const modelText of ["{}", "this is not JSON"]) {
        const db = new InMemoryFirestore();
        if (entitlementUsed === "pro") {
          seedActivePro(db);
        }

        await expect(parseOilAnalysisRequest(request(), dependencies(db, { modelText }))).rejects.toMatchObject({
          code: "internal",
        });

        const bucketId = entitlementUsed === "pro" ? "owner-1_2026-07-10" : "owner-1_lifetime";
        expect(db.data(`usage_quotas/${bucketId}`)).toMatchObject({ count: 1 });
        const otherBucketId = entitlementUsed === "pro" ? "owner-1_lifetime" : "owner-1_2026-07-10";
        expect(db.data(`usage_quotas/${otherBucketId}`)).toBeUndefined();
      }
    }
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

      await expect(parseOilAnalysisRequest(request(), dependencies(db, { modelText }))).rejects.toMatchObject({
        code: "internal",
        message: "unrecognized analysis response",
      });
      expect(db.data("usage_quotas/owner-1_lifetime")).toMatchObject({ count: 1 });
    }
  });

  it("returns null for an out-of-range model number when the report otherwise has a lab signal", async () => {
    const db = new InMemoryFirestore();

    const result = await parseOilAnalysisRequest(request(), dependencies(db, {
      modelText: '{"labName":"Lab","copper":-15}',
    }));

    expect(result).toEqual({ labName: "Lab", copper: null });
  });

  it("rejects unauthenticated callers", async () => {
    const db = new InMemoryFirestore();

    await expectHttpsError(parseOilAnalysisRequest({
      auth: null,
      data: { pdfBase64: validPdfBase64 },
    }, dependencies(db)), "unauthenticated");
  });

  it("returns only sanitized model fields", async () => {
    const db = new InMemoryFirestore();

    const result = await parseOilAnalysisRequest(request(), dependencies(db, {
      modelText: '{"labName":"Lab","iron":8,"untrusted":true}',
    }));

    expect(result).toEqual({ labName: "Lab", iron: 8 });
  });

  it("reads the text block when extended thinking puts a thinking block first", async () => {
    // Extended thinking is enabled on this call, so Anthropic returns [thinking, text].
    // Indexing content[0] yields the thinking block, which has no `text` — extraction would
    // return undefined, surface as an HTTP-OK model-output error, and (by the refund matrix)
    // consume the user's quota unit on every single request.
    const db = new InMemoryFirestore();
    const fetchImpl = async (): Promise<Response> =>
      new Response(
        JSON.stringify({
          content: [
            { type: "thinking", thinking: "Checking the iron row against the lab's units." },
            { type: "text", text: '{"labName":"Blackstone","iron":12}' },
          ],
        }),
        { status: 200 },
      );

    const result = await parseOilAnalysisRequest(request(), {
      ...dependencies(db),
      fetchImpl,
    });

    expect(result).toEqual({ labName: "Blackstone", iron: 12 });
    expect(db.data("usage_quotas/owner-1_lifetime")).toMatchObject({ count: 1 });
  });

  it("ignores a thinking block that has no text block alongside it", async () => {
    // A thinking-only response is a genuine model-output error and must NOT be mistaken for
    // a successful parse just because the scan skips non-text blocks.
    const db = new InMemoryFirestore();
    const fetchImpl = async (): Promise<Response> =>
      new Response(
        JSON.stringify({ content: [{ type: "thinking", thinking: "..." }] }),
        { status: 200 },
      );

    await expect(
      parseOilAnalysisRequest(request(), { ...dependencies(db), fetchImpl }),
    ).rejects.toMatchObject({ code: "internal" });
  });
});
