/**
 * Server-style pre-computed aggregates — the architecture probe.
 *
 * The v1 sweep put every grounded failure on the DERIVED bucket: counting rows, summing costs,
 * subtracting two odometers. Those are arithmetic, and a production Cloud Function would never
 * ask the model to do them — it has the entries in Firestore and can compute counts and totals
 * deterministically before the prompt is built. This module is that computation, run by the
 * HARNESS over the same golden data, so the figures are correct by construction.
 *
 * That is the point AND the caveat: the `grounded-computed` arm therefore measures "can the
 * model read the right line out of a summary", not "can the model compute". Every one of the
 * eight derived questions is directly served by a line in this block. Anyone reading the numbers
 * must read that sentence with them.
 *
 * Everything here is deterministic — entry types iterate in prod's VALID_ENTRY_TYPES order,
 * venues in first-appearance order, money is summed in integer cents — so the prompt bytes are
 * identical run to run.
 */
import { VALID_ENTRY_TYPES } from "../../src/functions/typedExtraction";
import type { EntryTypeValue } from "../../src/functions/typedExtraction";
import type { GoldenVehicle } from "./types";
import { miles, money } from "./types";

function sumCents(values: Array<number | null>): number {
  return values.reduce<number>((total, value) => total + Math.round((value ?? 0) * 100), 0);
}

function average(values: number[]): number | null {
  if (values.length === 0) return null;
  return Math.round(values.reduce((total, value) => total + value, 0) / values.length);
}

export function computeSummary(vehicle: GoldenVehicle, now: Date): string {
  const lines: string[] = [];
  lines.push("COMPUTED SUMMARY (calculated by the app from the log below — these figures are"
    + " authoritative for any count, total, or interval)");
  lines.push(`As of ${now.toISOString().slice(0, 10)} · current odometer ${miles(vehicle.currentOdometer)}`
    + ` · ${vehicle.entries.length} entries`
    + ` · first ${vehicle.entries[0].date} · latest ${vehicle.entries[vehicle.entries.length - 1].date}`);
  lines.push("");
  lines.push("By entry type — count | total spent | most recent date | most recent odometer");

  for (const entryType of VALID_ENTRY_TYPES as ReadonlyArray<EntryTypeValue>) {
    const matches = vehicle.entries.filter((candidate) => candidate.entryType === entryType);
    if (matches.length === 0) continue;
    const last = matches[matches.length - 1];
    lines.push(`  ${entryType.padEnd(15)} | ${String(matches.length).padStart(2)}`
      + ` | ${money(sumCents(matches.map((match) => match.cost)) / 100).padStart(10)}`
      + ` | ${last.date} | ${last.odometer === null ? "—" : miles(last.odometer)}`);
  }

  const oilChanges = vehicle.entries.filter((candidate) => candidate.entryType === "oil_change");
  if (oilChanges.length > 0) {
    const last = oilChanges[oilChanges.length - 1];
    const intervals: number[] = [];
    for (let index = 1; index < oilChanges.length; index += 1) {
      const previous = oilChanges[index - 1].odometer;
      const current = oilChanges[index].odometer;
      if (previous !== null && current !== null) intervals.push(current - previous);
    }
    const lastInterval = intervals.length > 0 ? intervals[intervals.length - 1] : null;
    const meanInterval = average(intervals);
    lines.push("");
    lines.push(`Oil changes: ${oilChanges.length} total`
      + ` · most recent ${last.date}${last.odometer === null ? "" : ` at ${miles(last.odometer)}`}`
      + (last.odometer === null ? "" : ` · ${miles(vehicle.currentOdometer - last.odometer)} since`)
      + (lastInterval === null ? "" : ` · interval between the last two: ${miles(lastInterval)}`)
      + (meanInterval === null ? "" : ` · average interval ${miles(meanInterval)}`));
  }

  const trackDays = vehicle.entries.filter((candidate) => candidate.entryType === "track_day");
  if (trackDays.length > 0) {
    const venues: string[] = [];
    for (const day of trackDays) {
      const venue = day.shopName ?? "unspecified venue";
      if (!venues.includes(venue)) venues.push(venue);
    }
    lines.push("");
    lines.push(`Track days by venue (${trackDays.length} total,`
      + ` ${money(sumCents(trackDays.map((day) => day.cost)) / 100)} in entry fees):`);
    for (const venue of venues) {
      const atVenue = trackDays.filter((day) => (day.shopName ?? "unspecified venue") === venue);
      lines.push(`  ${venue} | ${atVenue.length}`
        + ` | ${money(sumCents(atVenue.map((day) => day.cost)) / 100)}`
        + ` | ${atVenue.map((day) => day.date).join(", ")}`);
    }
  }

  return lines.join("\n");
}
