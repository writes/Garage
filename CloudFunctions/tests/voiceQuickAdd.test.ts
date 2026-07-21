import { describe, expect, it } from "vitest";
import {
  DAILY_VOICE_QUICKADD_QUOTA,
  MAX_TRANSCRIPT_CHARS,
  sanitizeVoiceProposal,
  voiceQuickAddRequest,
} from "../src/functions/voiceQuickAdd";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

const fixedNow = new Date("2026-07-21T20:00:00.000Z");
const goodModel =
  '{"entryType":"oil_change","odometerReading":18120,"cost":165,"shopName":null,"isDiy":true,"entryDate":null,"notes":"Mobil 1 0W-40"}';

function dependencies(db: InMemoryFirestore, modelText = goodModel, now = fixedNow) {
  return {
    apiKey: "test-api-key",
    db,
    fetchImpl: async (): Promise<Response> =>
      new Response(JSON.stringify({ content: [{ text: modelText }] }), { status: 200 }),
    now: () => now,
  };
}

function request(uid = "owner-1", transcript = "changed the oil on the viper, mobil 1, at 18120 miles") {
  return { auth: { uid }, data: { transcript } };
}

function seedActivePro(db: InMemoryFirestore, uid = "owner-1"): void {
  db.seed(`users/${uid}`, {
    subscription: { entitlement: "pro", isActive: true, expiresAt: "2026-08-01T00:00:00.000Z" },
  });
}

async function expectHttpsError(promise: Promise<unknown>, code: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code });
}

describe("voiceQuickAddRequest", () => {
  it("rejects an unauthenticated caller", async () => {
    await expectHttpsError(
      voiceQuickAddRequest({ auth: null, data: { transcript: "x" } }, dependencies(new InMemoryFirestore())),
      "unauthenticated",
    );
  });

  it("rejects a missing or empty transcript before any charge", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    await expectHttpsError(voiceQuickAddRequest({ auth: { uid: "owner-1" }, data: {} }, dependencies(db)), "invalid-argument");
    await expectHttpsError(
      voiceQuickAddRequest({ auth: { uid: "owner-1" }, data: { transcript: "   " } }, dependencies(db)),
      "invalid-argument",
    );
  });

  it("fences a non-Pro user with a typed pro_required permission error", async () => {
    const db = new InMemoryFirestore(); // no subscription seeded
    await expect(voiceQuickAddRequest(request(), dependencies(db))).rejects.toMatchObject({
      code: "permission-denied",
      details: { reason: "pro_required" },
    });
  });

  it("returns a sanitized prefill proposal for a Pro user", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const proposal = await voiceQuickAddRequest(request(), dependencies(db));
    expect(proposal).toEqual({
      entryType: "oil_change",
      odometerReading: 18120,
      cost: 165,
      shopName: null,
      isDiy: true,
      entryDate: null,
      notes: "Mobil 1 0W-40",
    });
  });

  it("enforces the pro daily quota and resets the next UTC day", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    for (let i = 0; i < DAILY_VOICE_QUICKADD_QUOTA; i += 1) {
      await voiceQuickAddRequest(request(), dependencies(db));
    }
    await expect(voiceQuickAddRequest(request(), dependencies(db))).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { reason: "voice_daily_exhausted" },
    });
    const nextDay = new Date("2026-07-22T00:30:00.000Z");
    const proposal = await voiceQuickAddRequest(request(), dependencies(db, goodModel, nextDay));
    expect(proposal.entryType).toBe("oil_change");
  });

  it("surfaces malformed model output as an internal error (not a bad entry)", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    await expectHttpsError(voiceQuickAddRequest(request(), dependencies(db, "not json")), "internal");
  });
});

describe("sanitizeVoiceProposal", () => {
  it("clamps an unknown entryType to maintenance and drops out-of-range/future values", () => {
    const result = sanitizeVoiceProposal({
      entryType: "spaceship_service",
      odometerReading: -5,
      cost: 9_999_999,
      shopName: "  Willow Springs  ",
      isDiy: "yes",
      entryDate: "2099-01-01T00:00:00.000Z",
      notes: 123,
    }, fixedNow);
    expect(result.entryType).toBe("maintenance");
    expect(result.odometerReading).toBeNull();
    expect(result.cost).toBeNull();
    expect(result.shopName).toBe("Willow Springs");
    expect(result.isDiy).toBeNull();
    expect(result.entryDate).toBeNull();
    expect(result.notes).toBeNull();
  });

  it("keeps a valid entryType and a plausible past date", () => {
    const result = sanitizeVoiceProposal(
      { entryType: "track_day", entryDate: "2026-07-15T00:00:00.000Z", cost: 425 },
      fixedNow,
    );
    expect(result.entryType).toBe("track_day");
    expect(result.entryDate).toBe("2026-07-15T00:00:00.000Z");
    expect(result.cost).toBe(425);
  });

  it("has a positive transcript ceiling", () => {
    expect(MAX_TRANSCRIPT_CHARS).toBeGreaterThan(0);
  });
});
