import { describe, expect, it } from "vitest";
import { normalizeVin } from "../src/functions/nhtsaRecalls";

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
