/**
 * Golden vehicle 3 — the track car. 2018 BMW M2 (N55), bought used in 2021, 34 entries: nine
 * track days (VIR ×3, Summit Point ×4, Watkins Glen ×2), four Blackstone oil analyses, three
 * DME reports, tread-depth wear snapshots, and a track-alignment/consumables cadence.
 *
 * This vehicle exercises the log's specialist entry types — track_day, oil_analysis, dme_report,
 * and tread_depth_reading wear snapshots — which is exactly the history a generic chatbot cannot
 * guess at. Domain notes: N55 sump is ~7 quarts; track users run a 5W-40 rather than the LL01
 * 0W-30; Pagid RSL29 and Motul RBF600 are the standard club-day pad/fluid pairing; overrev
 * "ranges" and their counts are what a BMW DME report actually reports.
 */
import type { GoldenVehicle } from "./types";
import { entry as e } from "./types";

const OIL = "Liqui Moly Molygen 5W-40, 7.0 qt";
const TIRE_SIZES = "245/35R19 front, 265/35R19 rear";

export const M2: GoldenVehicle = {
  id: "m2",
  label: "track-day car",
  year: 2018,
  make: "BMW",
  model: "M2",
  trim: "Coupe (N55), DCT",
  currentOdometer: 41850,
  ownedSince: "2021-04-28 (purchased used at 22,100 mi)",
  entries: [
    e("2021-05-02", 22410, "maintenance", 240.00, "Bimmer Werks", "pre-track baseline inspection",
      "suspension and cooling checked, no findings"),
    e("2021-05-22", 22680, "oil_change", 96.40, "DIY", OIL),
    e("2021-06-05", 22690, "track_day", 325.00, "Summit Point Motorsports Park",
      "Shenandoah Circuit", "4 sessions, dry"),
    e("2021-06-06", 22860, "tire", 0.00, "DIY", "tread_depth_reading",
      "Michelin Pilot Sport 4S — front 5/32, rear 4/32"),
    e("2021-07-17", 23410, "track_day", 445.00, "Virginia International Raceway", "full course", "hot, 5 sessions"),
    e("2021-07-19", 23600, "oil_analysis", 32.00, "Blackstone Labs", "post-track sample",
      "iron 18 ppm, fuel dilution 0.6%, TBN 5.1"),
    e("2021-08-14", 24050, "brake", 612.00, "DIY", "pads_replaced — front", "Pagid RSL29"),
    e("2021-09-11", 24700, "track_day", 445.00, "Virginia International Raceway", "full course"),
    e("2021-10-02", 25180, "dme_report", 0.00, "Bimmer Werks", "DME readout",
      "no fault codes; max 7,100 rpm; overrev range 1: 12 counts"),
    e("2022-03-19", 26340, "oil_change", 101.20, "DIY", OIL),
    e("2022-04-23", 27010, "tire", 1486.00, "Tire Rack / Bimmer Werks",
      `new_install — Michelin Pilot Sport 4S, ${TIRE_SIZES}`, "staggered set of four"),
    e("2022-04-23", 27010, "alignment", 220.00, "Bimmer Werks", "track alignment", "-2.5 deg front camber"),
    e("2022-05-21", 27600, "track_day", 525.00, "Watkins Glen International", "long course"),
    e("2022-06-18", 28120, "track_day", 340.00, "Summit Point Motorsports Park", "Main Circuit"),
    e("2022-07-09", 28400, "oil_analysis", 32.00, "Blackstone Labs", "post-track sample",
      "iron 24 ppm, fuel dilution 1.1%, TBN 4.2"),
    e("2022-08-13", 28900, "brake", 58.00, "DIY", "fluid_flush", "Motul RBF600"),
    e("2022-09-24", 29500, "track_day", 465.00, "Virginia International Raceway", "full course"),
    e("2022-10-15", 29900, "dme_report", 0.00, "Bimmer Werks", "DME readout",
      "no fault codes; overrev range 2: 3 counts"),
    e("2023-03-11", 31200, "oil_change", 104.80, "DIY", OIL),
    e("2023-05-13", 32100, "tire", 0.00, "DIY", "tread_depth_reading", "front 4/32, rear 3/32"),
    e("2023-06-24", 32800, "upgrade", 389.00, "Bimmer Werks", "aluminium charge pipe (engine)",
      "replaces the plastic OEM pipe"),
    e("2023-08-19", 33600, "track_day", 355.00, "Summit Point Motorsports Park", "Shenandoah Circuit"),
    e("2023-09-30", 34100, "oil_analysis", 34.00, "Blackstone Labs", "post-track sample",
      "iron 21 ppm, fuel dilution 0.9%, TBN 4.6"),
    e("2024-04-06", 35400, "oil_change", 108.50, "DIY", OIL),
    e("2024-05-18", 36050, "brake", 1024.00, "DIY", "pads_replaced — front and rear", "Pagid RSL29"),
    e("2024-06-22", 36700, "track_day", 545.00, "Watkins Glen International", "long course"),
    e("2024-09-14", 37500, "tire", 1612.00, "Tire Rack / Bimmer Werks",
      `new_install — Michelin Pilot Sport 4S, ${TIRE_SIZES}`, "staggered set of four"),
    e("2024-09-14", 37500, "alignment", 240.00, "Bimmer Werks", "track alignment", "-2.5 deg front camber"),
    e("2025-04-12", 38900, "oil_change", 112.30, "DIY", OIL),
    e("2025-06-14", 39600, "track_day", 375.00, "Summit Point Motorsports Park", "Main Circuit"),
    e("2025-07-26", 40200, "oil_analysis", 36.00, "Blackstone Labs", "post-track sample",
      "iron 26 ppm, fuel dilution 1.3%, TBN 3.9"),
    e("2025-10-11", 40900, "dme_report", 0.00, "Bimmer Werks", "DME readout",
      "no fault codes; overrev range 3: 1 count"),
    e("2026-04-18", 41500, "oil_change", 115.90, "DIY", OIL),
    e("2026-06-20", 41850, "maintenance", 20.00, "Roy's Auto Service", "Virginia state inspection", "passed"),
  ],
};
