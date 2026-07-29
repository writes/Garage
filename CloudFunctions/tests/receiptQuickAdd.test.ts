import { beforeEach, describe, expect, it, vi } from "vitest";
import * as logger from "firebase-functions/logger";
import {
  DAILY_RECEIPT_QUOTA,
  FREE_LIFETIME_RECEIPT_QUOTA,
  MAX_IMAGE_BASE64_BYTES,
  MAX_RECEIPT_PDF_BASE64_BYTES,
  MAX_TOTAL_BASE64_BYTES,
  receiptQuickAddRequest,
  sanitizeReceiptProposal,
} from "../src/functions/receiptQuickAdd";
import { InMemoryFirestore } from "./helpers/inMemoryFirestore";

vi.mock("firebase-functions/logger", () => ({
  error: vi.fn(),
  info: vi.fn(),
  warn: vi.fn(),
}));

// Tuesday, matching the golden eval's pinned NOW.
const fixedNow = new Date("2026-07-28T17:00:00.000Z");

// Content markers deliberately unique so the PII spy can prove they never reach a logger.
const SECRET_SHOP = "Piixleak Automotive";
const goodModel: Record<string, unknown> = {
  documentLooksLikeReceipt: true,
  entryType: "brake",
  shopName: SECRET_SHOP,
  entryDate: "2026-07-25",
  cost: 462.78,
  odometerReading: 87412,
  isDiy: false,
  lineItems: ["Front brake pads & rotors — $286.00", "Labor 1.5 hr — $142.50"],
};

const jpegBase64 = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49]).toString("base64");
const pngBase64 = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00]).toString("base64");
const pdfBase64 = Buffer.from("%PDF-1.4\nsynthetic receipt invoice body").toString("base64");

function dependencies(db: InMemoryFirestore, modelInput: unknown = goodModel, now = fixedNow) {
  return {
    apiKey: "test-api-key",
    db,
    fetchImpl: async (): Promise<Response> =>
      new Response(
        JSON.stringify({ content: [{ type: "tool_use", name: "record_receipt_entry", input: modelInput }] }),
        { status: 200 },
      ),
    now: () => now,
  };
}

function imageRequest(uid = "owner-1", images: string[] = [jpegBase64]) {
  return { auth: { uid }, data: { images } };
}

function pdfRequest(uid = "owner-1", pdf = pdfBase64) {
  return { auth: { uid }, data: { pdfBase64: pdf } };
}

function seedActivePro(db: InMemoryFirestore, uid = "owner-1"): void {
  db.seed(`users/${uid}`, {
    subscription: { entitlement: "pro", isActive: true, expiresAt: "2026-09-01T00:00:00.000Z" },
  });
}

async function expectHttpsError(promise: Promise<unknown>, code: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code });
}

/** Valid-length base64 filler whose size check fires before the pattern/magic checks would. */
function base64OfBytes(bytes: number): string {
  return "A".repeat(Math.ceil(bytes / 4) * 4);
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("receiptQuickAddRequest validation", () => {
  it("rejects an unauthenticated caller", async () => {
    await expectHttpsError(
      receiptQuickAddRequest({ auth: null, data: { images: [jpegBase64] } }, dependencies(new InMemoryFirestore())),
      "unauthenticated",
    );
  });

  it("rejects a payload with neither images nor pdfBase64, or with both", async () => {
    const db = new InMemoryFirestore();
    await expectHttpsError(
      receiptQuickAddRequest({ auth: { uid: "owner-1" }, data: {} }, dependencies(db)),
      "invalid-argument",
    );
    await expectHttpsError(
      receiptQuickAddRequest(
        { auth: { uid: "owner-1" }, data: { images: [jpegBase64], pdfBase64 } },
        dependencies(db),
      ),
      "invalid-argument",
    );
  });

  it("rejects an empty images array and more than two images", async () => {
    const db = new InMemoryFirestore();
    await expectHttpsError(receiptQuickAddRequest(imageRequest("owner-1", []), dependencies(db)), "invalid-argument");
    await expectHttpsError(
      receiptQuickAddRequest(imageRequest("owner-1", [jpegBase64, jpegBase64, jpegBase64]), dependencies(db)),
      "invalid-argument",
    );
  });

  it("rejects non-base64 image content", async () => {
    await expectHttpsError(
      receiptQuickAddRequest(imageRequest("owner-1", ["not base64!!"]), dependencies(new InMemoryFirestore())),
      "invalid-argument",
    );
  });

  it("rejects a non-JPEG image by magic bytes (PNG is not accepted)", async () => {
    await expectHttpsError(
      receiptQuickAddRequest(imageRequest("owner-1", [pngBase64]), dependencies(new InMemoryFirestore())),
      "invalid-argument",
    );
  });

  it("rejects pdfBase64 without a PDF signature", async () => {
    const notPdf = Buffer.from("hello this is not a pdf").toString("base64");
    await expectHttpsError(
      receiptQuickAddRequest(pdfRequest("owner-1", notPdf), dependencies(new InMemoryFirestore())),
      "invalid-argument",
    );
  });

  it("rejects an oversized single image, an oversized pdf, and an oversized total", async () => {
    const db = new InMemoryFirestore();
    await expectHttpsError(
      receiptQuickAddRequest(
        imageRequest("owner-1", [base64OfBytes(MAX_IMAGE_BASE64_BYTES + 4)]),
        dependencies(db),
      ),
      "invalid-argument",
    );
    await expectHttpsError(
      receiptQuickAddRequest(pdfRequest("owner-1", base64OfBytes(MAX_RECEIPT_PDF_BASE64_BYTES + 4)), dependencies(db)),
      "invalid-argument",
    );
    // Two images each within the per-image cap boundary check order: total fires first.
    const half = base64OfBytes(MAX_TOTAL_BASE64_BYTES / 2 + 4);
    await expectHttpsError(
      receiptQuickAddRequest(imageRequest("owner-1", [half, half]), dependencies(db)),
      "invalid-argument",
    );
  });

  it("charges no quota for any rejected payload", async () => {
    const db = new InMemoryFirestore();
    await expectHttpsError(
      receiptQuickAddRequest(imageRequest("owner-1", [pngBase64]), dependencies(db)),
      "invalid-argument",
    );
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toBeUndefined();
    expect(db.data("usage_quotas/owner-1_receipt_2026-07-28")).toBeUndefined();
  });

  it("requires a configured API key before charging quota", async () => {
    const db = new InMemoryFirestore();
    const deps = { ...dependencies(db), apiKey: undefined };
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), deps), "failed-precondition");
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toBeUndefined();
  });
});

describe("receiptQuickAddRequest quota", () => {
  it("admits a free user and returns a sanitized proposal from the lifetime bucket", async () => {
    const db = new InMemoryFirestore(); // no subscription seeded
    const proposal = await receiptQuickAddRequest(imageRequest(), dependencies(db));
    expect(proposal).toEqual({
      entryType: "brake",
      odometerReading: 87412,
      cost: 462.78,
      shopName: SECRET_SHOP,
      isDiy: false,
      entryDate: "2026-07-25T00:00:00.000Z",
      notes: null,
      lineItems: ["Front brake pads & rotors — $286.00", "Labor 1.5 hr — $142.50"],
    });
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({
      count: 1,
      kind: "receipt_quickadd_lifetime",
    });
  });

  it("gives a free user exactly the lifetime quota, then receipt_free_exhausted forever", async () => {
    const db = new InMemoryFirestore();
    for (let i = 0; i < FREE_LIFETIME_RECEIPT_QUOTA; i += 1) {
      await receiptQuickAddRequest(imageRequest(), dependencies(db));
    }
    await expect(receiptQuickAddRequest(imageRequest(), dependencies(db))).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { reason: "receipt_free_exhausted" },
    });
    // Lifetime means lifetime: the next UTC day changes nothing.
    const nextDay = new Date("2026-07-29T01:00:00.000Z");
    await expect(receiptQuickAddRequest(imageRequest(), dependencies(db, goodModel, nextDay)))
      .rejects.toMatchObject({ code: "resource-exhausted", details: { reason: "receipt_free_exhausted" } });
  });

  it("gives a Pro user the daily quota, then receipt_daily_exhausted with resetAt, resetting next UTC day", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    for (let i = 0; i < DAILY_RECEIPT_QUOTA; i += 1) {
      await receiptQuickAddRequest(imageRequest(), dependencies(db));
    }
    expect(db.data("usage_quotas/owner-1_receipt_2026-07-28")).toMatchObject({
      count: DAILY_RECEIPT_QUOTA,
      kind: "receipt_quickadd",
    });
    await expect(receiptQuickAddRequest(imageRequest(), dependencies(db))).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { reason: "receipt_daily_exhausted", resetAt: "2026-07-29T00:00:00.000Z" },
    });
    const nextDay = new Date("2026-07-29T00:30:00.000Z");
    const proposal = await receiptQuickAddRequest(imageRequest(), dependencies(db, goodModel, nextDay));
    expect(proposal.entryType).toBe("brake");
    expect(db.data("usage_quotas/owner-1_receipt_2026-07-29")).toMatchObject({ count: 1 });
  });

  it("charges the bucket matching the entitlement at call time when it flips mid-day", async () => {
    const db = new InMemoryFirestore();
    await receiptQuickAddRequest(imageRequest(), dependencies(db));
    await receiptQuickAddRequest(imageRequest(), dependencies(db));
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 2 });

    seedActivePro(db);
    await receiptQuickAddRequest(imageRequest(), dependencies(db));
    expect(db.data("usage_quotas/owner-1_receipt_2026-07-28")).toMatchObject({ count: 1 });
    // The free lifetime bucket is untouched by the Pro charge.
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 2 });
  });

  it("refunds the free lifetime bucket after an upstream network failure", async () => {
    const db = new InMemoryFirestore();
    const deps = dependencies(db);
    deps.fetchImpl = async (): Promise<Response> => {
      throw new Error("network unavailable");
    };
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), deps), "internal");
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 0 });
  });

  it("refunds the Pro daily bucket after an upstream 5xx failure", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const deps = dependencies(db);
    deps.fetchImpl = async (): Promise<Response> => new Response("upstream unavailable", { status: 502 });
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), deps), "internal");
    expect(db.data("usage_quotas/owner-1_receipt_2026-07-28")).toMatchObject({ count: 0 });
  });

  it("does not refund a 400 or 429 HTTP failure in either bucket", async () => {
    const freeDb = new InMemoryFirestore();
    const freeDeps = dependencies(freeDb);
    freeDeps.fetchImpl = async (): Promise<Response> => new Response("bad request", { status: 400 });
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), freeDeps), "internal");
    expect(freeDb.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 1 });

    const proDb = new InMemoryFirestore();
    seedActivePro(proDb);
    const proDeps = dependencies(proDb);
    proDeps.fetchImpl = async (): Promise<Response> => new Response("rate limited", { status: 429 });
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), proDeps), "internal");
    expect(proDb.data("usage_quotas/owner-1_receipt_2026-07-28")).toMatchObject({ count: 1 });
  });

  it("does not refund billed HTTP-OK malformed model output", async () => {
    const db = new InMemoryFirestore();
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), dependencies(db, "not json")), "internal");
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 1 });
  });
});

describe("receiptQuickAddRequest model-output handling", () => {
  it("maps documentLooksLikeReceipt=false to a typed not_a_receipt error and keeps the quota unit", async () => {
    const db = new InMemoryFirestore();
    await expect(receiptQuickAddRequest(
      imageRequest(),
      dependencies(db, { documentLooksLikeReceipt: false, entryType: "maintenance" }),
    )).rejects.toMatchObject({
      code: "failed-precondition",
      details: { reason: "not_a_receipt" },
    });
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 1 });
  });

  it("rejects schema-valid output with no core receipt signal (recognizability backstop)", async () => {
    const db = new InMemoryFirestore();
    await expectHttpsError(
      receiptQuickAddRequest(
        imageRequest(),
        dependencies(db, { documentLooksLikeReceipt: true, entryType: "maintenance", notes: "something" }),
      ),
      "internal",
    );
    // Inference was billed: the backstop keeps the quota unit.
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 1 });
  });

  it("accepts a PDF payload and sends it as a document block", async () => {
    const db = new InMemoryFirestore();
    const deps = dependencies(db);
    let captured: Record<string, unknown> | undefined;
    deps.fetchImpl = async (_url: unknown, init?: { body?: unknown }): Promise<Response> => {
      captured = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return new Response(
        JSON.stringify({ content: [{ type: "tool_use", name: "record_receipt_entry", input: goodModel }] }),
        { status: 200 },
      );
    };
    const proposal = await receiptQuickAddRequest(pdfRequest(), deps);
    expect(proposal.shopName).toBe(SECRET_SHOP);
    const messages = captured?.messages as Array<Record<string, unknown>>;
    const finalContent = messages[messages.length - 1].content as Array<Record<string, unknown>>;
    expect(finalContent[0]).toMatchObject({
      type: "document",
      source: { type: "base64", media_type: "application/pdf", data: pdfBase64 },
    });
  });

  it("picks the most populated tool_use block from a multi-block response", async () => {
    const db = new InMemoryFirestore();
    const deps = dependencies(db);
    deps.fetchImpl = async (): Promise<Response> =>
      new Response(JSON.stringify({
        content: [
          { type: "tool_use", name: "record_receipt_entry", input: { documentLooksLikeReceipt: true, entryType: "maintenance" } },
          { type: "tool_use", name: "record_receipt_entry", input: goodModel },
        ],
      }), { status: 200 });
    const proposal = await receiptQuickAddRequest(imageRequest(), deps);
    expect(proposal.shopName).toBe(SECRET_SHOP);
    expect(proposal.cost).toBe(462.78);
  });

  // Pins the accuracy-bearing request shape (the voice pattern: if the few-shot exemplar, the
  // anchored date line, the forced tool, or the block order regresses, this fails before the
  // golden eval ever has to be paid for).
  it("sends the few-shot exemplar, the anchored system date line, and image blocks before the text", async () => {
    const db = new InMemoryFirestore();
    const deps = dependencies(db);
    let captured: Record<string, unknown> | undefined;
    deps.fetchImpl = async (_url: unknown, init?: { body?: unknown }): Promise<Response> => {
      captured = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return new Response(
        JSON.stringify({ content: [{ type: "tool_use", name: "record_receipt_entry", input: goodModel }] }),
        { status: 200 },
      );
    };

    await receiptQuickAddRequest({
      auth: { uid: "owner-1" },
      data: { images: [jpegBase64, jpegBase64], vehicle: { year: 2019, make: "Toyota", model: "Tacoma", currentOdometer: 61200 } },
    }, deps);

    expect(captured).toBeDefined();
    expect(captured?.model).toBe("claude-haiku-4-5");
    expect(captured?.max_tokens).toBe(1024);
    expect(captured?.tool_choice).toEqual({ type: "tool", name: "record_receipt_entry" });
    // The live API rejects array-constraint keywords (maxItems et al.) in a strict tool
    // schema with a 400 — the 20-item cap is enforced by the sanitizer instead. This pin
    // fails cheaply if anyone reintroduces an unsupported keyword.
    const toolsJson = JSON.stringify(captured?.tools);
    expect(toolsJson).not.toContain("maxItems");
    expect(toolsJson).not.toContain("minItems");
    expect(toolsJson).not.toContain("maxLength");
    expect((captured?.tools as Array<Record<string, unknown>>)[0].strict).toBe(true);
    const system = String(captured?.system);
    expect(system).toContain("GRAND TOTAL");
    // fixedNow (2026-07-28) is a Tuesday; the line must anchor weekdays, not just name today.
    expect(system).toContain("Today is Tuesday 2026-07-28");
    expect(system).toContain("Monday was 2026-07-27");

    const messages = captured?.messages as Array<Record<string, unknown>>;
    expect(messages).toHaveLength(4);
    expect(messages[0].role).toBe("user");
    expect(messages[1].role).toBe("assistant");
    const example = (messages[1].content as Array<Record<string, unknown>>)[0]
      .input as Record<string, unknown>;
    // The exemplar's printed date must track the injected clock, never a hardcoded date.
    expect(example.entryDate).toBe("2026-07-25");
    expect(example.cost).toBe(462.78);
    expect(example.odometerReading).toBe(87412);

    const finalContent = (messages[3].content as Array<Record<string, unknown>>);
    expect(finalContent).toHaveLength(3);
    expect(finalContent[0]).toMatchObject({
      type: "image",
      source: { type: "base64", media_type: "image/jpeg", data: jpegBase64 },
    });
    expect(finalContent[1]).toMatchObject({ type: "image" });
    const text = String((finalContent[2] as Record<string, unknown>).text);
    expect(text).toContain("The vehicle is a 2019 Toyota Tacoma, current odometer 61200.");
    expect(text).toContain("Extract this vehicle service receipt into a log entry.");
  });
});

describe("receiptQuickAddRequest PII discipline", () => {
  function loggedText(): string {
    const spies = [logger.error, logger.info, logger.warn] as unknown as Array<{ mock: { calls: unknown[][] } }>;
    return JSON.stringify(spies.flatMap((spy) => spy.mock.calls));
  }

  it("never logs request or model content on the success path", async () => {
    const db = new InMemoryFirestore();
    await receiptQuickAddRequest(imageRequest(), dependencies(db));
    const logged = loggedText();
    expect(logged).not.toContain(jpegBase64);
    expect(logged).not.toContain(SECRET_SHOP);
  });

  it("never logs request or model content on failure paths", async () => {
    const db = new InMemoryFirestore();
    await expectHttpsError(
      receiptQuickAddRequest(imageRequest(), dependencies(db, `oops ${SECRET_SHOP}`)),
      "internal",
    );
    const deps = dependencies(db);
    deps.fetchImpl = async (): Promise<Response> => new Response(`upstream said ${SECRET_SHOP}`, { status: 502 });
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), deps), "internal");
    const badJson = dependencies(db);
    badJson.fetchImpl = async (): Promise<Response> => new Response(`{"broken": ${SECRET_SHOP}`, { status: 200 });
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), badJson), "internal");

    const logged = loggedText();
    expect(logged).not.toContain(jpegBase64);
    expect(logged).not.toContain(SECRET_SHOP);
  });
});

describe("sanitizeReceiptProposal", () => {
  it("clamps an unknown entryType to maintenance and drops out-of-range or wrong-typed values", () => {
    const result = sanitizeReceiptProposal({
      entryType: "spaceship_service",
      odometerReading: -5,
      cost: 9_999_999,
      shopName: "  Meridian Auto Care  ",
      isDiy: "yes",
      entryDate: "2099-01-01T00:00:00.000Z",
      notes: 123,
      lineItems: "not an array",
    }, fixedNow);
    expect(result.entryType).toBe("maintenance");
    expect(result.odometerReading).toBeNull();
    expect(result.cost).toBeNull();
    expect(result.shopName).toBe("Meridian Auto Care");
    expect(result.isDiy).toBeNull();
    expect(result.entryDate).toBeNull();
    expect(result.notes).toBeNull();
    expect(result.lineItems).toEqual([]);
  });

  it("keeps a decade-old backfill date and drops only implausible future dates", () => {
    const backfill = sanitizeReceiptProposal({ entryType: "oil_change", entryDate: "2016-03-14" }, fixedNow);
    expect(backfill.entryDate).toBe("2016-03-14T00:00:00.000Z");
    const tomorrow = sanitizeReceiptProposal({ entryType: "oil_change", entryDate: "2026-07-29" }, fixedNow);
    expect(tomorrow.entryDate).toBe("2026-07-29T00:00:00.000Z");
    const farFuture = sanitizeReceiptProposal({ entryType: "oil_change", entryDate: "2026-08-15" }, fixedNow);
    expect(farFuture.entryDate).toBeNull();
  });

  it("caps lineItems at 20 entries of 160 chars and drops non-string or blank members", () => {
    const raw = [
      ...Array.from({ length: 25 }, (_, i) => `Item ${i} — $1.00`),
    ];
    raw[3] = "x".repeat(500);
    (raw as unknown[])[5] = 42;
    raw[7] = "   ";
    const result = sanitizeReceiptProposal({ entryType: "maintenance", lineItems: raw }, fixedNow);
    expect(result.lineItems).toHaveLength(20);
    expect(result.lineItems[3]).toBe("x".repeat(160));
    expect(result.lineItems).not.toContain(42 as unknown as string);
    expect(result.lineItems.every((item) => typeof item === "string" && item.trim().length > 0 && item.length <= 160)).toBe(true);
  });

  it("keeps in-range numerics and trims strings", () => {
    const result = sanitizeReceiptProposal({
      entryType: "tire",
      odometerReading: 87412,
      cost: 462.78,
      shopName: "Discount Tire",
      isDiy: false,
      notes: `  Road hazard warranty included  `,
      lineItems: ["  4x Michelin CrossClimate 2 — $1,004.00  "],
    }, fixedNow);
    expect(result.entryType).toBe("tire");
    expect(result.odometerReading).toBe(87412);
    expect(result.cost).toBe(462.78);
    expect(result.notes).toBe("Road hazard warranty included");
    expect(result.lineItems).toEqual(["4x Michelin CrossClimate 2 — $1,004.00"]);
  });

  it("keeps the exported quota constants isolated and positive (pending tri-vote may adjust)", () => {
    expect(FREE_LIFETIME_RECEIPT_QUOTA).toBeGreaterThan(0);
    expect(DAILY_RECEIPT_QUOTA).toBeGreaterThan(FREE_LIFETIME_RECEIPT_QUOTA);
  });
});
