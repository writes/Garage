import { describe, expect, it } from "vitest";
import { lookupRecallsRequest, normalizeVin, sanitizeRecalls } from "../src/functions/nhtsaRecalls";

describe("normalizeVin", () => {
  it("accepts a valid 17-char VIN, trimming and uppercasing", () => {
    expect(normalizeVin(" 1hgcm82633a004352 ")).toBe("1HGCM82633A004352");
  });

  it("rejects the wrong length", () => {
    expect(normalizeVin("1HGCM82633A00435")).toBeNull(); // 16
    expect(normalizeVin("1HGCM82633A0043521")).toBeNull(); // 18
  });

  it("rejects the forbidden VIN letters I, O, Q", () => {
    expect(normalizeVin("1HGCM82633A0043I2")).toBeNull();
    expect(normalizeVin("1HGCM82633A0043O2")).toBeNull();
    expect(normalizeVin("1HGCM82633A0043Q2")).toBeNull();
  });

  it("rejects non-string input", () => {
    expect(normalizeVin(undefined)).toBeNull();
    expect(normalizeVin(123)).toBeNull();
    expect(normalizeVin(null)).toBeNull();
  });
});

describe("lookupRecallsRequest", () => {
  const auth = { uid: "owner-1" };
  const decoded = (make: string | null, model: string | null, year: string | null) =>
    new Response(JSON.stringify({ Results: [{ Make: make, Model: model, ModelYear: year }] }), { status: 200 });
  const recalls = (items: unknown[]) =>
    new Response(JSON.stringify({ Count: items.length, results: items }), { status: 200 });

  function fetcher(responses: Response[]): { impl: typeof fetch; urls: string[] } {
    const urls: string[] = [];
    let index = 0;
    const impl = (async (url: string) => {
      urls.push(String(url));
      return responses[index++] ?? new Response("", { status: 500 });
    }) as unknown as typeof fetch;
    return { impl, urls };
  }

  it("decodes the VIN then queries by make/model/year, because VIN is not a supported parameter", async () => {
    // The bug this replaces: NHTSA answers recallsByVehicle?vin=... with HTTP 400 for EVERY VIN,
    // so the old implementation failed 100% of the time. Verified against the live API.
    const { impl, urls } = fetcher([
      decoded("FORD", "F-150", "2013"),
      recalls([{ NHTSACampaignNumber: "19V075000", Component: "POWER TRAIN", parkIt: false }]),
    ]);

    const result = await lookupRecallsRequest({ auth, data: { vin: "1FTFW1ET5DFC10312" } }, { fetchImpl: impl });

    expect(urls[0]).toContain("DecodeVinValues/1FTFW1ET5DFC10312");
    expect(urls[1]).toContain("make=FORD");
    expect(urls[1]).toContain("model=F-150");
    expect(urls[1]).toContain("modelYear=2013");
    expect(urls[1]).not.toContain("vin=");
    expect(result.recalls).toHaveLength(1);
    expect(result.recalls[0].campaignNumber).toBe("19V075000");
  });

  it("reports an undecodable VIN as not-found rather than an internal error", async () => {
    const { impl } = fetcher([decoded(null, null, null)]);
    await expect(
      lookupRecallsRequest({ auth, data: { vin: "1FTFW1ET5DFC10312" } }, { fetchImpl: impl }),
    ).rejects.toMatchObject({ code: "not-found" });
  });

  it("rejects a malformed VIN before making any request", async () => {
    const { impl, urls } = fetcher([]);
    await expect(
      lookupRecallsRequest({ auth, data: { vin: "NOT-A-VIN" } }, { fetchImpl: impl }),
    ).rejects.toMatchObject({ code: "invalid-argument" });
    expect(urls).toHaveLength(0);
  });

  it("requires authentication", async () => {
    const { impl } = fetcher([]);
    await expect(
      lookupRecallsRequest({ auth: null, data: { vin: "1FTFW1ET5DFC10312" } }, { fetchImpl: impl }),
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });
});

describe("sanitizeRecalls", () => {
  it("keeps only the typed contract and drops unknown upstream fields", () => {
    const out = sanitizeRecalls({
      results: [{
        NHTSACampaignNumber: "19V075000",
        Component: "BRAKES",
        Summary: "s", Remedy: "r", ReportReceivedDate: "11/02/2019",
        parkIt: true, parkOutSide: false,
        injectedByUpstream: "must not cross the trust boundary",
      }],
    });
    expect(out).toHaveLength(1);
    expect(out[0]).toEqual({
      campaignNumber: "19V075000", component: "BRAKES", summary: "s", remedy: "r",
      reportReceivedDate: "11/02/2019", parkIt: true, parkOutside: false,
    });
  });

  it("drops records with no campaign number, which cannot be acted on", () => {
    expect(sanitizeRecalls({ results: [{ Component: "BRAKES" }] })).toEqual([]);
  });

  it("survives shapes NHTSA never documents", () => {
    expect(sanitizeRecalls(null)).toEqual([]);
    expect(sanitizeRecalls({})).toEqual([]);
    expect(sanitizeRecalls({ results: "nope" })).toEqual([]);
    expect(sanitizeRecalls({ results: [null, 5, "x"] })).toEqual([]);
  });

  it("bounds an unbounded upstream list", () => {
    const many = Array.from({ length: 200 }, (_, i) => ({ NHTSACampaignNumber: `C${i}` }));
    expect(sanitizeRecalls({ results: many }).length).toBeLessThanOrEqual(25);
  });
});
