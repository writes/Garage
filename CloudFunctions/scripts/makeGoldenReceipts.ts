/**
 * Synthetic golden-receipt corpus generator (plan §7, graft G6 / fix F7).
 *
 * Generates ~18 SYNTHETIC receipts — zero real PII; every name, address, VIN, and number is
 * invented — as deterministic SVG sources, then renders them to JPEG (and one PDF) for
 * scripts/receiptGoldenEval.ts:
 *
 *   cd CloudFunctions && npx tsx scripts/makeGoldenReceipts.ts
 *
 * Rendering chain (no new npm dependencies, by design):
 *   1. SVG sources are written to scripts/golden/receipts/svg/ — fully deterministic.
 *   2. If a Chrome/Chromium binary is found (CHROME_BIN env, standard macOS paths, or PATH),
 *      each SVG is screenshotted headlessly to PNG and converted to JPEG via macOS `sips`
 *      (or ImageMagick if present). The PDF case uses Chrome --print-to-pdf.
 *   3. If no renderer is available, the corpus stays SVG-only and manifest.json records
 *      renderer: "svg-only" — the eval then refuses to run and prints the one manual render
 *      step required. SVG content (the semantic truth) is deterministic either way; pixel
 *      output depends on the local Chrome/font versions, which is fine for an accuracy eval.
 *
 * manifest.json carries per-case expected fields in the shape receiptGoldenEval.ts scores.
 * Dates are absolute and all ≤ the eval's pinned NOW (2026-07-28) so the prod sanitizer's
 * future-date clamp never interferes.
 */
import { execFileSync } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

const OUT_DIR = path.join(__dirname, "golden", "receipts");
const SVG_DIR = path.join(OUT_DIR, "svg");

// ---------------------------------------------------------------------------------------------
// SVG receipt builder
// ---------------------------------------------------------------------------------------------

type FontKey = "mono" | "sans" | "serif" | "hand";

const FONTS: Record<FontKey, string> = {
  mono: "'Courier New', Courier, monospace",
  sans: "Helvetica, Arial, sans-serif",
  serif: "Georgia, 'Times New Roman', serif",
  hand: "'Bradley Hand', 'Segoe Script', 'Comic Sans MS', cursive",
};

interface TextLine {
  t: string;
  size?: number;
  b?: boolean;
  center?: boolean;
  right?: boolean;
  gap?: number;
  font?: FontKey;
}

type Degrade = "none" | "fade" | "blur" | "skew" | "lowlight";

interface SvgSpec {
  width: number;
  height: number;
  font: FontKey;
  degrade: Degrade;
  lines: TextLine[];
}

function escapeXml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function textElements(spec: SvgSpec, pad: number, ink: string): string {
  let y = pad;
  const parts: string[] = [];
  for (const line of spec.lines) {
    const size = line.size ?? 15;
    y += line.gap ?? Math.round(size * 1.55);
    if (line.t.length === 0) continue;
    const font = FONTS[line.font ?? spec.font];
    const anchor = line.center ? "middle" : line.right ? "end" : "start";
    const x = line.center ? spec.width / 2 : line.right ? spec.width - pad : pad;
    parts.push(
      `<text x="${x}" y="${y}" font-family="${font}" font-size="${size}"` +
      `${line.b ? ' font-weight="bold"' : ""} text-anchor="${anchor}" fill="${ink}"` +
      ` style="white-space:pre">${escapeXml(line.t)}</text>`,
    );
  }
  return parts.join("\n  ");
}

/** Deterministic degradations, baked into the SVG itself (recorded steps, plan §7). */
function buildSvg(spec: SvgSpec): string {
  const { width, height } = spec;
  const pad = 24;

  let defs = "";
  let paper = `<rect width="${width}" height="${height}" fill="#ffffff"/>`;
  let ink = "#1a1a1a";
  let openGroup = "<g>";
  let closeGroup = "</g>";
  let overlay = "";

  if (spec.degrade === "fade") {
    defs = `<filter id="fade"><feGaussianBlur stdDeviation="0.35"/></filter>`;
    paper = `<rect width="${width}" height="${height}" fill="#f3efe6"/>`;
    ink = "#a9a49a"; // thermal print fading toward the paper tone
    openGroup = `<g filter="url(#fade)">`;
  } else if (spec.degrade === "blur") {
    defs = `<filter id="blur"><feGaussianBlur stdDeviation="0.6"/></filter>`;
    openGroup = `<g filter="url(#blur)">`;
  } else if (spec.degrade === "skew") {
    // A phone photo on a workbench: dark background, receipt rotated with a soft shadow.
    defs = `<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">` +
      `<feDropShadow dx="6" dy="8" stdDeviation="7" flood-color="#000000" flood-opacity="0.45"/></filter>`;
    paper = `<rect width="${width}" height="${height}" fill="#5e5347"/>` +
      `<rect x="${pad * 2}" y="${pad * 2}" width="${width - pad * 4}" height="${height - pad * 4}"` +
      ` fill="#fdfcf7" filter="url(#shadow)"` +
      ` transform="rotate(7 ${width / 2} ${height / 2})"/>`;
    openGroup = `<g transform="rotate(7 ${width / 2} ${height / 2})">`;
  } else if (spec.degrade === "lowlight") {
    paper = `<rect width="${width}" height="${height}" fill="#e8e4da"/>`;
    ink = "#4a4a4a";
    overlay = `<rect width="${width}" height="${height}" fill="#101020" opacity="0.34"/>`;
  }

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
<defs>${defs}</defs>
${paper}
${openGroup}
  ${textElements(spec, spec.degrade === "skew" ? pad * 3 : pad, ink)}
${closeGroup}
${overlay}
</svg>
`;
}

// ---------------------------------------------------------------------------------------------
// Case definitions (all values synthetic; dates absolute; traps per plan §7)
// ---------------------------------------------------------------------------------------------

// NOTE: do not import from this script — loading it runs generation. The eval reads
// manifest.json and declares these shapes locally.
interface GoldenReceiptExpect {
  documentLooksLikeReceipt: boolean;
  entryType?: string[];
  cost?: number | null;
  odometerReading?: number | null;
  shopName?: string | null;
  entryDay?: string | null;
  isDiy?: boolean | null;
  lineItemsContain?: string[];
}

interface GoldenReceiptCase {
  id: string;
  kind: "images" | "pdf";
  files: string[];
  description: string;
  expect: GoldenReceiptExpect;
}

interface CaseSpec {
  id: string;
  kind: "images" | "pdf";
  description: string;
  svgs: SvgSpec[];
  expect: GoldenReceiptExpect;
}

const S = (t: string, extra: Partial<TextLine> = {}): TextLine => ({ t, ...extra });
const RULE = (width: number): TextLine => S("-".repeat(Math.floor(width / 9)), { size: 13 });

const CASES: CaseSpec[] = [
  {
    id: "clean-dealer",
    kind: "images",
    description: "Clean dealer service invoice with a printed mileage line.",
    svgs: [{
      width: 620, height: 780, font: "sans", degrade: "none",
      lines: [
        S("HELMSWORTH FORD SERVICE", { size: 24, b: true, center: true }),
        S("4410 Commerce Park Drive, Rivergate, TN 37072", { size: 12, center: true }),
        S("(615) 555-0147", { size: 12, center: true }),
        RULE(620),
        S("Invoice: 204518          Service Date: 06/12/2026", { size: 14 }),
        S("Advisor: T. Bell         Mileage: 34,218", { size: 14, b: true }),
        RULE(620),
        S("SYNTHETIC BLEND OIL CHANGE            $69.95", { size: 14, font: "mono" }),
        S("  0W-20 semi-syn 6 qts, filter incl.", { size: 12, font: "mono" }),
        S("TIRE ROTATION                         $24.95", { size: 14, font: "mono" }),
        S("MULTI-POINT INSPECTION                 $0.00", { size: 14, font: "mono" }),
        RULE(620),
        S("Subtotal                              $94.90", { size: 14, font: "mono" }),
        S("Tax                                    $7.59", { size: 14, font: "mono" }),
        S("TOTAL                                $102.49", { size: 17, b: true, font: "mono" }),
        S(""),
        S("Next service due at 39,218 miles", { size: 12 }),
        S("Thank you for servicing with Helmsworth Ford", { size: 12 }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["oil_change", "maintenance"],
      cost: 102.49,
      odometerReading: 34218,
      shopName: "Helmsworth Ford",
      entryDay: "2026-06-12",
      isDiy: false,
      lineItemsContain: ["oil"],
    },
  },
  {
    id: "thermal-faded",
    kind: "images",
    description: "Faded gas-station thermal receipt (fuel, no odometer).",
    svgs: [{
      width: 380, height: 560, font: "mono", degrade: "fade",
      lines: [
        S("GASNGO #77", { size: 20, b: true, center: true }),
        S("HWY 12 & MERCER RD", { size: 13, center: true }),
        S("07/03/2026  16:41", { size: 13, center: true }),
        RULE(380),
        S("PUMP 04   UNL REG", { size: 14 }),
        S("12.418 GAL @ $3.899", { size: 14 }),
        S("FUEL TOTAL    $48.42", { size: 16, b: true }),
        RULE(380),
        S("CREDIT        $48.42", { size: 14 }),
        S("AUTH #002214", { size: 13 }),
        S(""),
        S("THANK YOU", { size: 14, center: true }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["fuel"],
      cost: 48.42,
      odometerReading: null,
      shopName: "GasNGo",
      entryDay: "2026-07-03",
    },
  },
  {
    id: "skewed-photo",
    kind: "images",
    description: "Skewed phone photo of an alignment invoice on a workbench.",
    svgs: [{
      width: 640, height: 760, font: "sans", degrade: "skew",
      lines: [
        S("TORREY PINES TIRE & AUTO", { size: 21, b: true, center: true }),
        S("Alignment • Tires • Suspension", { size: 12, center: true }),
        S("Date: 05/21/2026     Mileage: 78,902", { size: 14, b: true }),
        RULE(500),
        S("FOUR WHEEL ALIGNMENT             $119.00", { size: 14, font: "mono" }),
        S("  Camber/caster/toe set to spec", { size: 12, font: "mono" }),
        RULE(500),
        S("Subtotal                         $119.00", { size: 14, font: "mono" }),
        S("Tax                                $9.52", { size: 14, font: "mono" }),
        S("TOTAL                            $128.52", { size: 16, b: true, font: "mono" }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["alignment"],
      cost: 128.52,
      odometerReading: 78902,
      shopName: "Torrey Pines",
      entryDay: "2026-05-21",
    },
  },
  {
    id: "handwritten-total",
    kind: "images",
    description: "Small-shop invoice with a handwritten total and date.",
    svgs: [{
      width: 600, height: 700, font: "serif", degrade: "none",
      lines: [
        S("EDDIE'S GARAGE", { size: 24, b: true, center: true }),
        S("Honest work since 1987", { size: 12, center: true }),
        RULE(600),
        S("Customer: walk-in", { size: 14 }),
        S("Date: 4/18/2026", { size: 19, font: "hand" }),
        S(""),
        S("Replace serpentine belt", { size: 18, font: "hand" }),
        S("parts + labor", { size: 16, font: "hand" }),
        S(""),
        S("Total  $240", { size: 28, b: true, font: "hand" }),
        S(""),
        S("PAID - CASH", { size: 18, font: "hand" }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["repair", "maintenance"],
      cost: 240,
      shopName: "Eddie's Garage",
      entryDay: "2026-04-18",
    },
  },
  {
    id: "parts-store",
    kind: "images",
    description: "Retail parts-store receipt with no labor lines (DIY signal).",
    svgs: [{
      width: 400, height: 640, font: "mono", degrade: "none",
      lines: [
        S("AUTOZONE #4821", { size: 19, b: true, center: true }),
        S("1180 GATEWAY BLVD", { size: 12, center: true }),
        S("06/28/2026 10:22 REG 2", { size: 12, center: true }),
        RULE(400),
        S("DURALAST GOLD PADS", { size: 14 }),
        S("  DG1234        $54.99", { size: 14 }),
        S("BRAKE CLEANER 12OZ", { size: 14 }),
        S("                 $4.49", { size: 14 }),
        RULE(400),
        S("SUBTOTAL        $59.48", { size: 14 }),
        S("TAX              $4.76", { size: 14 }),
        S("TOTAL           $64.24", { size: 16, b: true }),
        S("DEBIT           $64.24", { size: 14 }),
        RULE(400),
        S("ITEMS SOLD: 2", { size: 12 }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["brake"],
      cost: 64.24,
      odometerReading: null,
      shopName: "AutoZone",
      entryDay: "2026-06-28",
      isDiy: true,
      lineItemsContain: ["pads"],
    },
  },
  {
    id: "tire-roadhazard",
    kind: "images",
    description: "Tire invoice with road-hazard certificate lines.",
    svgs: [{
      width: 640, height: 860, font: "sans", degrade: "none",
      lines: [
        S("DISCOUNT TIRE", { size: 24, b: true, center: true }),
        S("Store 1044 — Invoice 88-51230", { size: 12, center: true }),
        S("Date: 03/09/2026        Mileage: 45,102", { size: 14, b: true }),
        RULE(640),
        S("MICHELIN DEFENDER2 225/60R17  4 @ $167.00   $668.00", { size: 13, font: "mono" }),
        S("ROAD HAZARD CERTIFICATE       4 @ $22.00     $88.00", { size: 13, font: "mono" }),
        S("MOUNT/BALANCE/VALVE           4 @ $20.00     $80.00", { size: 13, font: "mono" }),
        RULE(640),
        S("Subtotal                                    $836.00", { size: 13, font: "mono" }),
        S("Tax                                          $66.88", { size: 13, font: "mono" }),
        S("TOTAL                                       $902.88", { size: 16, b: true, font: "mono" }),
        S(""),
        S("Rotation and flat repair free for tire life", { size: 12 }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["tire"],
      cost: 902.88,
      odometerReading: 45102,
      shopName: "Discount Tire",
      entryDay: "2026-03-09",
      lineItemsContain: ["road hazard"],
    },
  },
  {
    id: "twopage",
    kind: "images",
    description: "Two-page independent-shop invoice: lines on page 1, totals on page 2.",
    svgs: [
      {
        width: 620, height: 800, font: "sans", degrade: "none",
        lines: [
          S("BAVARIAN MOTOR WERKS INDEPENDENT", { size: 20, b: true, center: true }),
          S("Invoice 7719 — Page 1 of 2", { size: 12, center: true }),
          S("Service Date: 02/14/2026    Miles In: 98,340", { size: 14, b: true }),
          RULE(620),
          S("VALVE COVER GASKET SET                 $145.00", { size: 13, font: "mono" }),
          S("ENGINE OIL + FILTER (LL-01 5W-30)       $98.00", { size: 13, font: "mono" }),
          S("LABOR: R&I VALVE COVER, RESEAL 3.8 HR  $532.00", { size: 13, font: "mono" }),
          S("SHOP SUPPLIES                           $40.00", { size: 13, font: "mono" }),
          RULE(620),
          S("Continued on page 2 ...", { size: 12 }),
        ],
      },
      {
        width: 620, height: 800, font: "sans", degrade: "none",
        lines: [
          S("BAVARIAN MOTOR WERKS INDEPENDENT", { size: 20, b: true, center: true }),
          S("Invoice 7719 — Page 2 of 2", { size: 12, center: true }),
          RULE(620),
          S("Subtotal                               $815.00", { size: 13, font: "mono" }),
          S("Tax                                     $65.20", { size: 13, font: "mono" }),
          S("TOTAL DUE                              $880.20", { size: 16, b: true, font: "mono" }),
          S(""),
          S("Warranty: 24 months / 24,000 miles on repairs", { size: 12 }),
          S("Thank you — see you at the next oil service.", { size: 12 }),
        ],
      },
    ],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["repair"],
      cost: 880.20,
      odometerReading: 98340,
      shopName: "Bavarian Motor Werks",
      entryDay: "2026-02-14",
      lineItemsContain: ["valve cover"],
    },
  },
  {
    id: "tall-thermal",
    kind: "images",
    description: "Tall 3:1 quick-lube thermal receipt (P1 VisionKit/tiling evidence case).",
    svgs: [{
      width: 400, height: 1200, font: "mono", degrade: "none",
      lines: [
        S("QUICK LUBE EXPRESS", { size: 19, b: true, center: true }),
        S("BAY 2  INV 55201", { size: 13, center: true }),
        S("07/15/2026 09:12", { size: 13, center: true }),
        S("ODOMETER: 66,410", { size: 15, b: true, center: true }),
        RULE(400),
        S("FULL SYNTHETIC 0W-20", { size: 14 }),
        S("  6 QTS         $52.99", { size: 14 }),
        S("OIL FILTER       $9.99", { size: 14 }),
        S("AIR FILTER      $19.99", { size: 14 }),
        S("WASHER FLUID     $0.00", { size: 14 }),
        S("COOLANT TOP-OFF  $0.00", { size: 14 }),
        S("TIRES CHECKED    $0.00", { size: 14 }),
        S("CHASSIS LUBE     $0.00", { size: 14 }),
        RULE(400),
        S("SUBTOTAL        $82.97", { size: 14 }),
        S("DISPOSAL FEE     $2.00", { size: 14 }),
        S("TAX              $5.02", { size: 14 }),
        S("TOTAL           $89.99", { size: 17, b: true }),
        RULE(400),
        S("VISA            $89.99", { size: 14 }),
        S(""),
        S("NEXT SERVICE:", { size: 13 }),
        S("71,410 MI OR 6 MO", { size: 13 }),
        S(""),
        S("THANK YOU!", { size: 15, center: true }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["oil_change"],
      cost: 89.99,
      odometerReading: 66410,
      shopName: "Quick Lube Express",
      entryDay: "2026-07-15",
    },
  },
  {
    id: "ro-mileage-trap",
    kind: "images",
    description: "TRAP: RO number printed beside the mileage; phone and ZIP also mileage-shaped.",
    svgs: [{
      width: 620, height: 720, font: "sans", degrade: "none",
      lines: [
        S("SUMMIT AUTOMOTIVE", { size: 23, b: true, center: true }),
        S("2905 Frontage Rd, San Diego, CA 92108", { size: 12, center: true }),
        S("(619) 555-0182", { size: 12, center: true }),
        RULE(620),
        S("RO# 118427            Mileage: 52,880", { size: 15, b: true }),
        S("Service Date: 06/02/2026", { size: 14 }),
        RULE(620),
        S("COOLANT SYSTEM FLUSH                 $149.99", { size: 13, font: "mono" }),
        S("  OAT coolant, pressure test incl.", { size: 12, font: "mono" }),
        RULE(620),
        S("Subtotal                             $149.99", { size: 13, font: "mono" }),
        S("Tax                                   $12.12", { size: 13, font: "mono" }),
        S("TOTAL                                $162.11", { size: 16, b: true, font: "mono" }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["maintenance"],
      cost: 162.11,
      odometerReading: 52880,
      shopName: "Summit Automotive",
      entryDay: "2026-06-02",
    },
  },
  {
    id: "subtotal-trap",
    kind: "images",
    description: "TRAP: subtotal / supplies / tax / TOTAL / tendered / change stack; slight focus blur.",
    svgs: [{
      width: 440, height: 680, font: "mono", degrade: "blur",
      lines: [
        S("PRECISION MUFFLER", { size: 19, b: true, center: true }),
        S("TICKET 3308  05/30/2026", { size: 13, center: true }),
        RULE(440),
        S("EXHAUST LEAK REPAIR", { size: 14 }),
        S("  WELD FLEX JOINT  $389.00", { size: 14 }),
        RULE(440),
        S("SUBTOTAL           $389.00", { size: 14 }),
        S("SHOP SUPPLIES       $12.00", { size: 14 }),
        S("TAX                 $32.08", { size: 14 }),
        S("TOTAL              $433.08", { size: 16, b: true }),
        S("AMOUNT TENDERED    $440.00", { size: 14 }),
        S("CHANGE               $6.92", { size: 14 }),
        RULE(440),
        S("CASH SALE - THANK YOU", { size: 13, center: true }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["repair"],
      cost: 433.08,
      odometerReading: null,
      shopName: "Precision Muffler",
      entryDay: "2026-05-30",
    },
  },
  {
    id: "discount-line",
    kind: "images",
    description: "Coupon/discount line between the service line and the total.",
    svgs: [{
      width: 620, height: 720, font: "sans", degrade: "none",
      lines: [
        S("LAKESIDE HONDA SERVICE", { size: 22, b: true, center: true }),
        S("Appt 09:30 — Advisor M. Ito", { size: 12, center: true }),
        S("Date: 04/02/2026        Mileage: 41,775", { size: 14, b: true }),
        RULE(620),
        S("BRAKE FLUID EXCHANGE                 $129.95", { size: 13, font: "mono" }),
        S("COUPON SAVE20                        -$20.00", { size: 13, font: "mono" }),
        RULE(620),
        S("Subtotal                             $109.95", { size: 13, font: "mono" }),
        S("Tax                                    $8.80", { size: 13, font: "mono" }),
        S("TOTAL                                $118.75", { size: 16, b: true, font: "mono" }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["brake", "maintenance"],
      cost: 118.75,
      odometerReading: 41775,
      shopName: "Lakeside Honda",
      entryDay: "2026-04-02",
    },
  },
  {
    id: "vin-prominent",
    kind: "images",
    description: "TRAP: dealer invoice with a prominent VIN near the mileage line.",
    svgs: [{
      width: 640, height: 760, font: "sans", degrade: "none",
      lines: [
        S("NORTHGATE TOYOTA", { size: 23, b: true, center: true }),
        S("Service Invoice 62-8871", { size: 12, center: true }),
        RULE(640),
        S("VIN: 4T1BF1FK5HU301992", { size: 15, b: true }),
        S("Stock: T8871    License: 8ZKD442", { size: 13 }),
        S("Mileage: 30,112    Date: 03/27/2026", { size: 15, b: true }),
        RULE(640),
        S("30,000 MILE SERVICE                  $289.00", { size: 13, font: "mono" }),
        S("  Oil/filter, rotate, cabin filter,", { size: 12, font: "mono" }),
        S("  inspect brakes and driveline", { size: 12, font: "mono" }),
        RULE(640),
        S("Subtotal                             $289.00", { size: 13, font: "mono" }),
        S("Tax                                   $23.12", { size: 13, font: "mono" }),
        S("TOTAL                                $312.12", { size: 16, b: true, font: "mono" }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["maintenance"],
      cost: 312.12,
      odometerReading: 30112,
      shopName: "Northgate Toyota",
      entryDay: "2026-03-27",
    },
  },
  {
    id: "due-date-trap",
    kind: "images",
    description: "TRAP: service date vs invoice date vs PAYMENT DUE date.",
    svgs: [{
      width: 640, height: 740, font: "sans", degrade: "none",
      lines: [
        S("MERIDIAN FLEET SERVICES", { size: 22, b: true, center: true }),
        S("INVOICE — NET 30", { size: 13, center: true }),
        RULE(640),
        S("Service Date: 06/10/2026", { size: 15, b: true }),
        S("Invoice Date: 06/11/2026", { size: 13 }),
        S("PAYMENT DUE:  07/10/2026", { size: 15, b: true }),
        S("Unit 44 — Mileage: 88,210", { size: 14, b: true }),
        RULE(640),
        S("TRANSMISSION FLUID SERVICE           $249.00", { size: 13, font: "mono" }),
        S("  Drain/fill, new gasket + filter", { size: 12, font: "mono" }),
        RULE(640),
        S("Subtotal                             $249.00", { size: 13, font: "mono" }),
        S("Fleet discount                       -$12.45", { size: 13, font: "mono" }),
        S("Tax                                   $52.89", { size: 13, font: "mono" }),
        S("TOTAL                                $289.44", { size: 16, b: true, font: "mono" }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["maintenance"],
      cost: 289.44,
      odometerReading: 88210,
      shopName: "Meridian Fleet",
      entryDay: "2026-06-10",
    },
  },
  {
    id: "date-free",
    kind: "images",
    description: "No date printed anywhere — the model must omit entryDate, not invent one.",
    svgs: [{
      width: 420, height: 520, font: "mono", degrade: "none",
      lines: [
        S("CORNER CAR CARE", { size: 19, b: true, center: true }),
        S("CASH RECEIPT", { size: 13, center: true }),
        RULE(420),
        S("WIPER BLADES PAIR  $24.99", { size: 14 }),
        S("INSTALL             $5.00", { size: 14 }),
        RULE(420),
        S("SUBTOTAL           $29.99", { size: 14 }),
        S("TAX                 $2.51", { size: 14 }),
        S("TOTAL              $32.50", { size: 16, b: true }),
        S(""),
        S("THANKS!", { size: 14, center: true }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["maintenance"],
      cost: 32.50,
      shopName: "Corner Car Care",
      entryDay: null,
    },
  },
  {
    id: "decade-old",
    kind: "images",
    description: "Decade-old backfill receipt — the sanitizer must keep the 2016 date.",
    svgs: [{
      width: 620, height: 720, font: "serif", degrade: "lowlight",
      lines: [
        S("VALLEY IMPORT REPAIR", { size: 22, b: true, center: true }),
        S("Invoice 5512", { size: 12, center: true }),
        S("Date: 09/22/2016     Mileage: 101,220", { size: 15, b: true }),
        RULE(620),
        S("TIMING BELT KIT W/ WATER PUMP        $312.00", { size: 13, font: "mono" }),
        S("LABOR 4.2 HR                         $336.00", { size: 13, font: "mono" }),
        RULE(620),
        S("Subtotal                             $648.00", { size: 13, font: "mono" }),
        S("Tax                                   $36.31", { size: 13, font: "mono" }),
        S("TOTAL                                $684.31", { size: 16, b: true, font: "mono" }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["repair", "maintenance"],
      cost: 684.31,
      odometerReading: 101220,
      shopName: "Valley Import",
      entryDay: "2016-09-22",
      lineItemsContain: ["timing belt"],
    },
  },
  {
    id: "pdf-invoice",
    kind: "pdf",
    description: "PDF invoice (document block path).",
    svgs: [{
      width: 620, height: 780, font: "sans", degrade: "none",
      lines: [
        S("CASCADE AUTO WORKS", { size: 24, b: true, center: true }),
        S("INVOICE 2026-1188", { size: 13, center: true }),
        S("Service Date: 07/08/2026    Mileage: 59,644", { size: 14, b: true }),
        RULE(620),
        S("AGM BATTERY GROUP 48                 $219.00", { size: 13, font: "mono" }),
        S("INSTALL + REGISTER BATTERY            $39.00", { size: 13, font: "mono" }),
        S("CORE CREDIT                          -$22.00", { size: 13, font: "mono" }),
        RULE(620),
        S("Subtotal                             $236.00", { size: 13, font: "mono" }),
        S("Tax                                   $10.13", { size: 13, font: "mono" }),
        S("TOTAL                                $246.13", { size: 16, b: true, font: "mono" }),
        S(""),
        S("Battery warranty: 48 months free replacement", { size: 12 }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["repair", "maintenance"],
      cost: 246.13,
      odometerReading: 59644,
      shopName: "Cascade Auto Works",
      entryDay: "2026-07-08",
    },
  },
  {
    id: "non-receipt",
    kind: "images",
    description: "Control: a cartoon dog, not a document — documentLooksLikeReceipt must be false.",
    svgs: [{
      width: 560, height: 560, font: "sans", degrade: "none",
      lines: [],
    }],
    expect: { documentLooksLikeReceipt: false },
  },
  {
    id: "fewshot-anchor",
    kind: "images",
    description: "A/B anchor mirroring the few-shot exemplar's structure with different values.",
    svgs: [{
      width: 620, height: 720, font: "sans", degrade: "none",
      lines: [
        S("HARBOR VIEW AUTO CARE", { size: 22, b: true, center: true }),
        S("311 Marina Blvd", { size: 12, center: true }),
        S("RO #77105   Date: 07/20/2026   Mileage: 64,388", { size: 14, b: true }),
        RULE(620),
        S("FRONT BRAKE PADS & ROTORS            $262.00", { size: 13, font: "mono" }),
        S("LABOR 1.5 HR                         $138.00", { size: 13, font: "mono" }),
        RULE(620),
        S("Subtotal                             $400.00", { size: 13, font: "mono" }),
        S("Tax                                   $32.00", { size: 13, font: "mono" }),
        S("TOTAL                                $432.00", { size: 16, b: true, font: "mono" }),
        S("VISA TEND                            $432.00", { size: 13, font: "mono" }),
      ],
    }],
    expect: {
      documentLooksLikeReceipt: true,
      entryType: ["brake"],
      cost: 432.00,
      odometerReading: 64388,
      shopName: "Harbor View",
      entryDay: "2026-07-20",
    },
  },
];

/** The control case is a drawing, not text — built separately for clarity. */
function dogSvg(): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="560" height="560" viewBox="0 0 560 560">
<rect width="560" height="560" fill="#8fc177"/>
<rect y="420" width="560" height="140" fill="#5f9e4b"/>
<circle cx="470" cy="90" r="48" fill="#f7d94c"/>
<ellipse cx="270" cy="360" rx="130" ry="85" fill="#a5713f"/>
<circle cx="200" cy="240" r="70" fill="#a5713f"/>
<ellipse cx="150" cy="185" rx="26" ry="48" fill="#7c4f27" transform="rotate(-25 150 185)"/>
<ellipse cx="250" cy="185" rx="26" ry="48" fill="#7c4f27" transform="rotate(25 250 185)"/>
<circle cx="180" cy="230" r="10" fill="#20160c"/>
<circle cx="222" cy="230" r="10" fill="#20160c"/>
<ellipse cx="200" cy="262" rx="14" ry="10" fill="#20160c"/>
<path d="M186 276 Q200 292 214 276" stroke="#20160c" stroke-width="5" fill="none"/>
<ellipse cx="190" cy="430" rx="22" ry="34" fill="#8a5a30"/>
<ellipse cx="255" cy="438" rx="22" ry="34" fill="#8a5a30"/>
<ellipse cx="330" cy="438" rx="22" ry="34" fill="#8a5a30"/>
<path d="M390 330 Q450 290 445 345" stroke="#a5713f" stroke-width="26" fill="none" stroke-linecap="round"/>
</svg>
`;
}

// ---------------------------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------------------------

function findChrome(): string | undefined {
  const fromEnv = process.env.CHROME_BIN;
  if (fromEnv && fs.existsSync(fromEnv)) return fromEnv;
  const candidates = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  for (const name of ["google-chrome", "chromium", "chromium-browser"]) {
    try {
      const found = execFileSync("which", [name], { encoding: "utf8" }).trim();
      if (found) return found;
    } catch {
      // keep looking
    }
  }
  return undefined;
}

function hasCommand(name: string): boolean {
  try {
    return execFileSync("which", [name], { encoding: "utf8" }).trim().length > 0;
  } catch {
    return false;
  }
}

function chromeArgs(extra: string[]): string[] {
  return [
    "--headless",
    "--disable-gpu",
    "--hide-scrollbars",
    "--force-device-scale-factor=1",
    "--default-background-color=FFFFFFFF",
    "--no-first-run",
    "--disable-extensions",
    ...extra,
  ];
}

function wrapHtml(svg: string, width: number, height: number): string {
  return `<!doctype html><html><head><meta charset="utf-8"><style>` +
    `html,body{margin:0;padding:0;width:${width}px;height:${height}px;overflow:hidden}</style>` +
    `</head><body>${svg}</body></html>`;
}

function renderJpeg(chrome: string, svg: string, spec: SvgSpec, outFile: string, tmpDir: string): void {
  const base = path.basename(outFile, ".jpg");
  const htmlFile = path.join(tmpDir, `${base}.html`);
  const pngFile = path.join(tmpDir, `${base}.png`);
  fs.writeFileSync(htmlFile, wrapHtml(svg, spec.width, spec.height));
  execFileSync(chrome, chromeArgs([
    `--screenshot=${pngFile}`,
    `--window-size=${spec.width},${spec.height}`,
    `file://${htmlFile}`,
  ]), { stdio: "ignore", timeout: 60_000 });

  if (hasCommand("sips")) {
    execFileSync("sips", ["-s", "format", "jpeg", "-s", "formatOptions", "85", pngFile, "--out", outFile],
      { stdio: "ignore", timeout: 60_000 });
  } else if (hasCommand("magick")) {
    execFileSync("magick", [pngFile, "-quality", "85", outFile], { stdio: "ignore", timeout: 60_000 });
  } else {
    throw new Error("no PNG->JPEG converter (need macOS sips or ImageMagick)");
  }

  const magic = fs.readFileSync(outFile).subarray(0, 3);
  if (!magic.equals(Buffer.from([0xff, 0xd8, 0xff]))) {
    throw new Error(`${outFile} is not a JPEG after conversion`);
  }
}

function renderPdf(chrome: string, svg: string, spec: SvgSpec, outFile: string, tmpDir: string): void {
  const htmlFile = path.join(tmpDir, `${path.basename(outFile, ".pdf")}.html`);
  fs.writeFileSync(htmlFile, wrapHtml(svg, spec.width, spec.height));
  execFileSync(chrome, chromeArgs([
    `--print-to-pdf=${outFile}`,
    "--no-pdf-header-footer",
    `file://${htmlFile}`,
  ]), { stdio: "ignore", timeout: 60_000 });

  const magic = fs.readFileSync(outFile).subarray(0, 5).toString("utf8");
  if (magic !== "%PDF-") throw new Error(`${outFile} is not a PDF after rendering`);
}

function main(): void {
  fs.mkdirSync(SVG_DIR, { recursive: true });
  const chrome = findChrome();
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "golden-receipts-"));
  const rendered: GoldenReceiptCase[] = [];
  let renderer: string;

  if (chrome) {
    renderer = `chrome-headless+${hasCommand("sips") ? "sips" : "magick"}`;
  } else {
    renderer = "svg-only";
    console.warn("No Chrome/Chromium found: writing SVG sources only. Manual step: render each");
    console.warn("svg/*.svg to a JPEG of the same pixel size (and pdf-invoice to PDF) before eval.");
  }

  for (const c of CASES) {
    const files: string[] = [];
    c.svgs.forEach((spec, index) => {
      const suffix = c.svgs.length > 1 ? `-${index + 1}` : "";
      const stem = `${c.id}${suffix}`;
      const svg = c.id === "non-receipt" ? dogSvg() : buildSvg(spec);
      fs.writeFileSync(path.join(SVG_DIR, `${stem}.svg`), svg);

      const outName = c.kind === "pdf" ? `${stem}.pdf` : `${stem}.jpg`;
      files.push(outName);
      if (!chrome) return;
      const outFile = path.join(OUT_DIR, outName);
      if (c.kind === "pdf") {
        renderPdf(chrome, svg, spec, outFile, tmpDir);
      } else {
        renderJpeg(chrome, svg, spec, outFile, tmpDir);
      }
      console.log(`rendered ${outName} (${spec.width}x${spec.height})`);
    });
    rendered.push({ id: c.id, kind: c.kind, files, description: c.description, expect: c.expect });
  }

  const manifest = {
    // Deterministic on purpose: no timestamps. Semantic content is pinned by the SVG sources;
    // pixel bytes may vary with the local Chrome/font versions, which is fine for the eval.
    generator: "scripts/makeGoldenReceipts.ts",
    renderer,
    note: "All receipts are SYNTHETIC — every name, address, VIN, and number is invented (plan G6/F7).",
    cases: rendered,
  };
  fs.writeFileSync(path.join(OUT_DIR, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  fs.rmSync(tmpDir, { recursive: true, force: true });
  console.log(`manifest: ${path.join(OUT_DIR, "manifest.json")} (${rendered.length} cases, renderer: ${renderer})`);
}

main();
