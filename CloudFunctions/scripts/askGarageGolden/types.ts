/**
 * Ask-Garage golden set — vehicle history model + the serializer that renders a history into
 * the GROUNDED system prompt.
 *
 * The entry shape mirrors the app's log entry (entryType comes from prod's VALID_ENTRY_TYPES,
 * imported not copied, so a vocabulary change breaks the build here too). `detail` is the
 * flattened stand-in for the schemaVersion-2 typed fields (oilGrade, quantityQuarts, brand,
 * serviceAction, tire sizes, workItem, nextDueOdometer, upgradeCategory) — the eval measures whether
 * the model can ANSWER from a history, not whether it can parse a particular JSON shape, so a
 * human-readable table is both the fair input and the one a real implementation would send.
 */
import type { EntryTypeValue } from "../../src/functions/typedExtraction";

export interface GoldenEntry {
  /** YYYY-MM-DD. Entries are authored in chronological order. */
  date: string;
  odometer: number | null;
  entryType: EntryTypeValue;
  cost: number | null;
  shopName: string | null;
  isDiy: boolean;
  /** Type-specific details, flattened (oil grade + quarts, tire sizes, service action, …). */
  detail?: string;
  notes?: string;
}

export interface GoldenVehicle {
  id: string;
  label: string;
  year: number;
  make: string;
  model: string;
  trim: string;
  /** Odometer as of NOW — the anchor for "how many miles since …" questions. */
  currentOdometer: number;
  ownedSince: string;
  entries: GoldenEntry[];
}

/**
 * Positional entry constructor — the corpus files are long enough that named-property literals
 * would bury the data. `shop === "DIY"` sets isDiy and leaves shopName null, matching how the
 * app records owner-performed work.
 */
export function entry(
  date: string, odometer: number | null, entryType: EntryTypeValue,
  cost: number | null, shop: string | null, detail?: string, notes?: string,
): GoldenEntry {
  return {
    date, odometer, entryType, cost,
    shopName: shop === "DIY" ? null : shop,
    isDiy: shop === "DIY",
    detail, notes,
  };
}

export function money(value: number): string {
  return `$${value.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",")}`;
}

export function miles(value: number): string {
  return `${value.toLocaleString("en-US")} mi`;
}

/** One entry → one pipe-delimited line. Stable field order; empty fields are elided. */
function entryLine(entry: GoldenEntry): string {
  const cells = [
    entry.date,
    entry.odometer === null ? "—" : miles(entry.odometer),
    entry.entryType,
    entry.cost === null ? "—" : money(entry.cost),
    entry.isDiy ? "DIY" : (entry.shopName ?? "—"),
  ];
  if (entry.detail) cells.push(entry.detail);
  if (entry.notes) cells.push(entry.notes);
  return cells.join(" | ");
}

/**
 * The GROUNDED payload: vehicle profile + every entry, newest last. Deterministic — no clock,
 * no ordering by object key — so the prompt bytes are identical run to run (and cacheable).
 */
export function serializeHistory(vehicle: GoldenVehicle, now: Date): string {
  const header = [
    `VEHICLE: ${vehicle.year} ${vehicle.make} ${vehicle.model} ${vehicle.trim}`,
    `Owned since: ${vehicle.ownedSince}`,
    `Current odometer: ${miles(vehicle.currentOdometer)} (as of ${now.toISOString().slice(0, 10)})`,
    `Service log: ${vehicle.entries.length} entries`,
    "",
    "date | odometer | type | cost | shop or DIY | details | notes",
    "---",
  ].join("\n");
  return `${header}\n${vehicle.entries.map(entryLine).join("\n")}`;
}

/** The UNGROUNDED payload: make/model/year only — no log, no odometer, no shops. */
export function vehicleOnly(vehicle: GoldenVehicle): string {
  return `VEHICLE: ${vehicle.year} ${vehicle.make} ${vehicle.model} ${vehicle.trim}\n`
    + "Service log: not available.";
}
