import { beforeEach, describe, expect, it, vi } from "vitest";
import * as logger from "firebase-functions/logger";
import {
  FREE_LIFETIME_CONFIRMED_QUOTA,
  FREE_LIFETIME_SCAN_CEILING,
  MAX_IMAGE_BASE64_BYTES,
  MAX_RECEIPT_PDF_BASE64_BYTES,
  MAX_TOTAL_BASE64_BYTES,
  PRO_MONTHLY_CONFIRMED_QUOTA,
  PRO_MONTHLY_SCAN_CEILING,
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

function tokenDocs(db: InMemoryFirestore): Array<{ id: string; data: Record<string, unknown> }> {
  return db.collectionData("receipt_scan_tokens");
}

function onlyToken(db: InMemoryFirestore): Record<string, unknown> {
  const tokens = tokenDocs(db);
  expect(tokens).toHaveLength(1);
  return tokens[0].data;
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
  it("admits a free user with an additive token and byte-stable proposal fields", async () => {
    const db = new InMemoryFirestore(); // no subscription seeded
    const response = await receiptQuickAddRequest(imageRequest(), dependencies(db));
    const { token, quota, ...proposal } = response;
    const expectedProposal = {
      entryType: "brake",
      odometerReading: 87412,
      cost: 462.78,
      shopName: SECRET_SHOP,
      isDiy: false,
      entryDate: "2026-07-25T00:00:00.000Z",
      notes: null,
      lineItems: ["Front brake pads & rotors — $286.00", "Labor 1.5 hr — $142.50"],
    };
    expect(JSON.stringify(proposal)).toBe(JSON.stringify(expectedProposal));
    expect(token).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
    expect(quota).toEqual({
      entitlement: "free",
      scanRemaining: FREE_LIFETIME_SCAN_CEILING - 1,
      scanCeiling: FREE_LIFETIME_SCAN_CEILING,
      confirmedRemaining: FREE_LIFETIME_CONFIRMED_QUOTA - 1,
      confirmedAllowance: FREE_LIFETIME_CONFIRMED_QUOTA,
      resetAt: null,
      creditsRemaining: 0,
      creditsScanRemaining: 0,
      creditsGranted: 0,
      creditsDeficit: 0,
    });
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({
      count: 1,
      kind: "receipt_quickadd_lifetime",
    });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ count: 0, reserved: 1 });
    expect(onlyToken(db)).toMatchObject({
      uid: "owner-1",
      entitlementUsed: "free",
      confirmedBucketId: "owner-1_receipt_confirmed_lifetime",
      createdAtMillis: fixedNow.getTime(),
      expiresAtMillis: fixedNow.getTime() + 24 * 60 * 60 * 1000,
      resetAtMillis: null,
      consumed: false,
    });
  });

  it("admits exactly five unconfirmed free scans, then denies the sixth reservation", async () => {
    const db = new InMemoryFirestore();
    for (let i = 0; i < FREE_LIFETIME_CONFIRMED_QUOTA; i += 1) {
      await receiptQuickAddRequest(imageRequest(), dependencies(db));
    }
    await expect(receiptQuickAddRequest(imageRequest(), dependencies(db))).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { reason: "receipt_confirmed_exhausted", scope: "free_lifetime" },
    });
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 5 });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ count: 0, reserved: 5 });
  });

  it("uses monthly Pro buckets and flips at the UTC month boundary", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const july = await receiptQuickAddRequest(imageRequest(), dependencies(db));
    expect(july.quota).toMatchObject({ entitlement: "pro", resetAt: "2026-08-01T00:00:00.000Z" });
    expect(db.data("usage_quotas/owner-1_receipt_scan_2026-07")).toMatchObject({ count: 1 });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_2026-07")).toMatchObject({ count: 0, reserved: 1 });

    const august = new Date("2026-08-01T00:30:00.000Z");
    const response = await receiptQuickAddRequest(imageRequest(), dependencies(db, goodModel, august));
    expect(response.entryType).toBe("brake");
    expect(db.data("usage_quotas/owner-1_receipt_scan_2026-08")).toMatchObject({ count: 1 });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_2026-08")).toMatchObject({ count: 0, reserved: 1 });
  });

  it("charges the bucket matching the entitlement at call time when it flips mid-day", async () => {
    const db = new InMemoryFirestore();
    await receiptQuickAddRequest(imageRequest(), dependencies(db));
    await receiptQuickAddRequest(imageRequest(), dependencies(db));
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 2 });

    seedActivePro(db);
    await receiptQuickAddRequest(imageRequest(), dependencies(db));
    expect(db.data("usage_quotas/owner-1_receipt_scan_2026-07")).toMatchObject({ count: 1 });
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
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ reserved: 0 });
    expect(onlyToken(db)).toMatchObject({ consumed: true, released: true });
  });

  it("refunds the Pro monthly bucket after an upstream 5xx failure", async () => {
    const db = new InMemoryFirestore();
    seedActivePro(db);
    const deps = dependencies(db);
    deps.fetchImpl = async (): Promise<Response> => new Response("upstream unavailable", { status: 502 });
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), deps), "internal");
    expect(db.data("usage_quotas/owner-1_receipt_scan_2026-07")).toMatchObject({ count: 0 });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_2026-07")).toMatchObject({ reserved: 0 });
    expect(onlyToken(db)).toMatchObject({ consumed: true, released: true });
  });

  it("keeps a billed 400 scan but releases its reservation, and refunds a 429", async () => {
    const freeDb = new InMemoryFirestore();
    const freeDeps = dependencies(freeDb);
    freeDeps.fetchImpl = async (): Promise<Response> => new Response("bad request", { status: 400 });
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), freeDeps), "internal");
    expect(freeDb.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 1 });
    expect(freeDb.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ reserved: 0 });
    expect(onlyToken(freeDb)).toMatchObject({ consumed: true, released: true });

    const proDb = new InMemoryFirestore();
    seedActivePro(proDb);
    const proDeps = dependencies(proDb);
    proDeps.fetchImpl = async (): Promise<Response> => new Response("rate limited", { status: 429 });
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), proDeps), "internal");
    expect(proDb.data("usage_quotas/owner-1_receipt_scan_2026-07")).toMatchObject({ count: 0 });
    expect(proDb.data("usage_quotas/owner-1_receipt_confirmed_2026-07")).toMatchObject({ reserved: 0 });
    expect(onlyToken(proDb)).toMatchObject({ consumed: true, released: true });
  });

  it("does not refund billed HTTP-OK malformed model output", async () => {
    const db = new InMemoryFirestore();
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), dependencies(db, "not json")), "internal");
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 1 });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ reserved: 0 });
    expect(onlyToken(db)).toMatchObject({ consumed: true, released: true });
  });

  it("refunds a fetch timeout and exposes the deadline error", async () => {
    const db = new InMemoryFirestore();
    const deps = dependencies(db);
    deps.fetchImpl = async (_url: string | URL | Request, init?: RequestInit): Promise<Response> => {
      expect(init?.signal).toBeTruthy();
      throw new DOMException("timed out", "TimeoutError");
    };
    await expectHttpsError(receiptQuickAddRequest(imageRequest(), deps), "deadline-exceeded");
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 0 });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ reserved: 0 });
    expect(onlyToken(db)).toMatchObject({ consumed: true, released: true });
  });

  it("enforces scan ceilings in both scopes and honors the legacy free scan counter", async () => {
    const freeDb = new InMemoryFirestore();
    freeDb.seed("usage_quotas/owner-1_receipt_lifetime", { count: FREE_LIFETIME_SCAN_CEILING });
    await expect(receiptQuickAddRequest(imageRequest(), dependencies(freeDb))).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { reason: "receipt_scan_exhausted", scope: "free_lifetime" },
    });

    const proDb = new InMemoryFirestore();
    seedActivePro(proDb);
    proDb.seed("usage_quotas/owner-1_receipt_scan_2026-07", { count: PRO_MONTHLY_SCAN_CEILING });
    await expect(receiptQuickAddRequest(imageRequest(), dependencies(proDb))).rejects.toMatchObject({
      code: "resource-exhausted",
      details: {
        reason: "receipt_scan_exhausted",
        scope: "pro_month",
        resetAt: "2026-08-01T00:00:00.000Z",
      },
    });
  });

  it("lazily releases an expired token before admitting a replacement scan", async () => {
    const db = new InMemoryFirestore();
    db.seed("usage_quotas/owner-1_receipt_lifetime", { count: 4 });
    db.seed("usage_quotas/owner-1_receipt_confirmed_lifetime", { count: 0, reserved: 1 });
    db.seed("receipt_scan_tokens/expired-token", {
      uid: "owner-1",
      entitlementUsed: "free",
      confirmedBucketId: "owner-1_receipt_confirmed_lifetime",
      resetAtMillis: null,
      createdAtMillis: fixedNow.getTime() - 48 * 60 * 60 * 1000,
      expiresAtMillis: fixedNow.getTime() - 1,
      consumed: false,
    });

    await receiptQuickAddRequest(imageRequest(), dependencies(db));
    expect(db.data("usage_quotas/owner-1_receipt_lifetime")).toMatchObject({ count: 5 });
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ count: 0, reserved: 1 });
    expect(db.data("receipt_scan_tokens/expired-token")).toMatchObject({
      consumed: true,
      consumedAtMillis: fixedNow.getTime(),
      released: true,
    });
    expect(tokenDocs(db)).toHaveLength(2);
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
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ reserved: 0 });
    expect(onlyToken(db)).toMatchObject({ consumed: true, released: true });
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
    expect(db.data("usage_quotas/owner-1_receipt_confirmed_lifetime")).toMatchObject({ reserved: 0 });
    expect(onlyToken(db)).toMatchObject({ consumed: true, released: true });
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

  it("keeps the exported confirmed quotas and scan ceilings positive and distinct", () => {
    expect(FREE_LIFETIME_CONFIRMED_QUOTA).toBeGreaterThan(0);
    expect(FREE_LIFETIME_SCAN_CEILING).toBeGreaterThan(FREE_LIFETIME_CONFIRMED_QUOTA);
    expect(PRO_MONTHLY_CONFIRMED_QUOTA).toBeGreaterThan(FREE_LIFETIME_CONFIRMED_QUOTA);
    expect(PRO_MONTHLY_SCAN_CEILING).toBeGreaterThan(PRO_MONTHLY_CONFIRMED_QUOTA);
  });
});
