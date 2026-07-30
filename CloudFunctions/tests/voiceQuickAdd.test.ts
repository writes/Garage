import { describe, expect, it } from "vitest";
import {
  DAILY_VOICE_QUICKADD_QUOTA,
  MAX_TRANSCRIPT_CHARS,
  sanitizeVoiceProposal,
  voiceQuickAddRequest,
} from "../src/functions/voiceQuickAdd";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

const fixedNow = new Date("2026-07-21T20:00:00.000Z");
const goodModel: Record<string, unknown> = {
  entryType: "oil_change",
  odometerReading: 18120,
  cost: 165,
  isDiy: true,
  notes: "Mobil 1 0W-40",
};

function dependencies(db: InMemoryFirestore, modelInput: unknown = goodModel, now = fixedNow) {
  return {
    apiKey: "test-api-key",
    db,
    // Forced strict tool use: the API validates the input against the schema, so the fixture is an
    // object rather than a string of JSON the function has to fence-strip and parse.
    fetchImpl: async (): Promise<Response> =>
      new Response(
        JSON.stringify({ content: [{ type: "tool_use", name: "record_entry", input: modelInput }] }),
        { status: 200 },
      ),
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

  it("refunds the consumed voice bucket after an upstream network failure", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const requestDependencies = dependencies(db);
    requestDependencies.fetchImpl = async (): Promise<Response> => {
      throw new Error("network unavailable");
    };

    await expectHttpsError(voiceQuickAddRequest(request(), requestDependencies), "internal");

    expect(db.data("usage_quotas/owner-1_voice_2026-07-21")).toMatchObject({ count: 0 });
  });

  it("refunds the consumed voice bucket after an upstream 5xx failure", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const requestDependencies = dependencies(db);
    requestDependencies.fetchImpl = async (): Promise<Response> => new Response("upstream unavailable", { status: 500 });

    await expectHttpsError(voiceQuickAddRequest(request(), requestDependencies), "internal");

    expect(db.data("usage_quotas/owner-1_voice_2026-07-21")).toMatchObject({ count: 0 });
  });

  it("does not refund a billed 400 HTTP failure", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const requestDependencies = dependencies(db);
    requestDependencies.fetchImpl = async (): Promise<Response> => new Response("bad request", { status: 400 });

    await expectHttpsError(voiceQuickAddRequest(request(), requestDependencies), "internal");

    expect(db.data("usage_quotas/owner-1_voice_2026-07-21")).toMatchObject({ count: 1 });
  });

  it("refunds a 429 response because Anthropic did not bill it", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const requestDependencies = dependencies(db);
    requestDependencies.fetchImpl = async (): Promise<Response> => new Response("rate limited", { status: 429 });

    await expectHttpsError(voiceQuickAddRequest(request(), requestDependencies), "internal");

    expect(db.data("usage_quotas/owner-1_voice_2026-07-21")).toMatchObject({ count: 0 });
  });

  it("aborts a slow Claude call, refunds its quota, and exposes deadline-exceeded", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const requestDependencies = dependencies(db);
    requestDependencies.fetchImpl = async (_url: string | URL | Request, init?: RequestInit): Promise<Response> => {
      expect(init?.signal).toBeTruthy();
      throw new DOMException("timed out", "TimeoutError");
    };

    await expectHttpsError(voiceQuickAddRequest(request(), requestDependencies), "deadline-exceeded");

    expect(db.data("usage_quotas/owner-1_voice_2026-07-21")).toMatchObject({ count: 0 });
  });

  it("does not refund billed HTTP-OK unparseable model output", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);

    await expectHttpsError(voiceQuickAddRequest(request(), dependencies(db, "not json")), "internal");

    expect(db.data("usage_quotas/owner-1_voice_2026-07-21")).toMatchObject({ count: 1 });
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

  // Pins the accuracy-bearing request shape (golden eval: 77.4% -> 97.8%; see SYSTEM_PROMPT).
  // If the few-shot example, the anchored date line, or the message order regresses, this fails
  // before the golden eval ever has to be paid for.
  it("sends the few-shot example and an anchored date line computed from now", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const deps = dependencies(db);
    let captured: Record<string, unknown> | undefined;
    deps.fetchImpl = async (_url: unknown, init?: { body?: unknown }): Promise<Response> => {
      captured = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return new Response(
        JSON.stringify({ content: [{ type: "tool_use", name: "record_entry", input: goodModel }] }),
        { status: 200 },
      );
    };

    await voiceQuickAddRequest(request(), deps);

    expect(captured).toBeDefined();
    const system = String(captured?.system);
    // fixedNow (2026-07-21) is a Tuesday; the line must anchor weekdays, not just name today.
    expect(system).toContain("Today is Tuesday 2026-07-21");
    expect(system).toContain("Monday was 2026-07-20");
    const messages = captured?.messages as Array<Record<string, unknown>>;
    expect(messages).toHaveLength(4);
    expect(messages[0].role).toBe("user");
    expect(messages[1].role).toBe("assistant");
    const example = (messages[1].content as Array<Record<string, unknown>>)[0]
      .input as Record<string, unknown>;
    // The example's "last Wednesday" must track the injected clock, never a hardcoded date.
    expect(example.entryDate).toBe("2026-07-15");
    expect(example.cost).toBe(650);
    const final = (messages[3].content as Array<Record<string, unknown>>)[0];
    expect(String(final.text)).toContain("changed the oil on the viper");
  });
});
