import { describe, expect, it, vi } from "vitest";
import {
  RECALL_CACHE_TTL_MILLIS,
  RECALLS_DAILY_LOOKUP_QUOTA,
  lookupRecallsRequest,
  normalizeVin,
  sanitizeRecalls,
} from "../src/functions/nhtsaRecalls";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

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
  const fixedNow = new Date("2026-07-30T20:00:00.000Z");
  const primaryVin = "1FTFW1ET5DFC10312";
  const secondVin = "1FTFW1ET5DFC10313";
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

  function dependencies(db: InMemoryFirestore, fetchImpl: typeof fetch, now = fixedNow) {
    return { db, fetchImpl, now: () => now };
  }

  const cachedResult = {
    make: "HONDA",
    model: "ACCORD",
    modelYear: "2003",
    recalls: [{
      campaignNumber: "19V075000",
      component: "POWER TRAIN",
      summary: null,
      remedy: null,
      reportReceivedDate: null,
      parkIt: false,
      parkOutside: false,
    }],
  };

  it("decodes the VIN then queries by make/model/year, because VIN is not a supported parameter", async () => {
    // The bug this replaces: NHTSA answers recallsByVehicle?vin=... with HTTP 400 for EVERY VIN,
    // so the old implementation failed 100% of the time. Verified against the live API.
    const { impl, urls } = fetcher([
      decoded("FORD", "F-150", "2013"),
      recalls([{ NHTSACampaignNumber: "19V075000", Component: "POWER TRAIN", parkIt: false }]),
    ]);
    const db = new InMemoryFirestore();

    const result = await lookupRecallsRequest({ auth, data: { vin: primaryVin } }, dependencies(db, impl));

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
    const db = new InMemoryFirestore();
    await expect(
      lookupRecallsRequest({ auth, data: { vin: primaryVin } }, dependencies(db, impl)),
    ).rejects.toMatchObject({ code: "not-found" });
  });

  it("rejects a malformed VIN before making any request", async () => {
    const { impl, urls } = fetcher([]);
    const db = new InMemoryFirestore();
    await expect(
      lookupRecallsRequest({ auth, data: { vin: "NOT-A-VIN" } }, dependencies(db, impl)),
    ).rejects.toMatchObject({ code: "invalid-argument" });
    expect(urls).toHaveLength(0);
  });

  it("requires authentication", async () => {
    const { impl } = fetcher([]);
    const db = new InMemoryFirestore();
    await expect(
      lookupRecallsRequest({ auth: null, data: { vin: primaryVin } }, dependencies(db, impl)),
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  it("admits the 30th uncached lookup, denies the 31st, and resets at the UTC day boundary", async () => {
    const db = new InMemoryFirestore();
    db.seed("usage_quotas/owner-1_recalls_2026-07-30", { count: RECALLS_DAILY_LOOKUP_QUOTA - 1 });
    const firstFetch = fetcher([decoded("FORD", "F-150", "2013"), recalls([])]);

    await lookupRecallsRequest({ auth, data: { vin: primaryVin } }, dependencies(db, firstFetch.impl));
    expect(db.data("usage_quotas/owner-1_recalls_2026-07-30")).toMatchObject({
      uid: "owner-1",
      kind: "recalls_daily",
      date: "2026-07-30",
      count: RECALLS_DAILY_LOOKUP_QUOTA,
      updatedAt: fixedNow.toISOString(),
    });

    const deniedFetch = vi.fn<typeof fetch>();
    await expect(
      lookupRecallsRequest({ auth, data: { vin: secondVin } }, dependencies(db, deniedFetch)),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      details: {
        reason: "recalls_daily_exhausted",
        resetAt: "2026-07-31T00:00:00.000Z",
      },
    });
    expect(deniedFetch).not.toHaveBeenCalled();

    const nextDay = new Date("2026-07-31T00:00:00.000Z");
    const nextDayFetch = fetcher([decoded("FORD", "F-150", "2013"), recalls([])]);
    await lookupRecallsRequest({ auth, data: { vin: secondVin } }, dependencies(db, nextDayFetch.impl, nextDay));
    expect(db.data("usage_quotas/owner-1_recalls_2026-07-31")).toMatchObject({
      uid: "owner-1",
      kind: "recalls_daily",
      date: "2026-07-31",
      count: 1,
      updatedAt: nextDay.toISOString(),
    });
  });

  it("serves a fresh cache hit without calling NHTSA or consuming quota", async () => {
    const db = new InMemoryFirestore();
    db.seed(`recall_lookups/${primaryVin}`, {
      vin: primaryVin,
      result: cachedResult,
      fetchedAtMillis: fixedNow.getTime() - 60_000,
    });
    const fetchImpl = vi.fn<typeof fetch>();

    await expect(
      lookupRecallsRequest({ auth, data: { vin: primaryVin } }, dependencies(db, fetchImpl)),
    ).resolves.toEqual(cachedResult);
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(db.data("usage_quotas/owner-1_recalls_2026-07-30")).toBeUndefined();
  });

  it("populates the cache and consumes one quota unit on a cache miss", async () => {
    const db = new InMemoryFirestore();
    const upstream = fetcher([
      decoded("FORD", "F-150", "2013"),
      recalls([{ NHTSACampaignNumber: "19V075000", Component: "POWER TRAIN", parkIt: false }]),
    ]);

    const result = await lookupRecallsRequest({ auth, data: { vin: primaryVin } }, dependencies(db, upstream.impl));
    expect(upstream.urls).toHaveLength(2);
    expect(db.data(`recall_lookups/${primaryVin}`)).toEqual({
      vin: primaryVin,
      result,
      fetchedAtMillis: fixedNow.getTime(),
    });
    expect(db.data("usage_quotas/owner-1_recalls_2026-07-30")).toMatchObject({ count: 1 });
  });

  it("refetches a cache entry older than 24 hours and replaces it", async () => {
    const db = new InMemoryFirestore();
    db.seed(`recall_lookups/${primaryVin}`, {
      vin: primaryVin,
      result: cachedResult,
      fetchedAtMillis: fixedNow.getTime() - RECALL_CACHE_TTL_MILLIS - 1,
    });
    const upstream = fetcher([decoded("FORD", "F-150", "2013"), recalls([])]);

    const result = await lookupRecallsRequest({ auth, data: { vin: primaryVin } }, dependencies(db, upstream.impl));
    expect(upstream.urls).toHaveLength(2);
    expect(result).toEqual({ make: "FORD", model: "F-150", modelYear: "2013", recalls: [] });
    expect(db.data(`recall_lookups/${primaryVin}`)).toEqual({
      vin: primaryVin,
      result,
      fetchedAtMillis: fixedNow.getTime(),
    });
    expect(db.data("usage_quotas/owner-1_recalls_2026-07-30")).toMatchObject({ count: 1 });
  });

  it("uses the same uppercase cache document for a trimmed, lowercase VIN", async () => {
    const db = new InMemoryFirestore();
    const vin = "1HGCM82633A004352";
    db.seed(`recall_lookups/${vin}`, {
      vin,
      result: cachedResult,
      fetchedAtMillis: fixedNow.getTime() - 60_000,
    });
    const fetchImpl = vi.fn<typeof fetch>();

    await expect(
      lookupRecallsRequest({ auth, data: { vin: "  1hgcm82633a004352 " } }, dependencies(db, fetchImpl)),
    ).resolves.toEqual(cachedResult);
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(db.data("usage_quotas/owner-1_recalls_2026-07-30")).toBeUndefined();
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
