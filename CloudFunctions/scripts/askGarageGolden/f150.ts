/**
 * Golden vehicle 2 — the sparse logger. 2022 Ford F-150 XLT SuperCrew 3.5L EcoBoost, bought
 * used at 18,400 mi in Sept 2024, 15 entries in under two years.
 *
 * Sparseness is the point: this vehicle carries most of the UNANSWERABLE questions. Whole
 * maintenance categories (transmission, differential, plugs, brake pads) have simply never been
 * logged, so a model that answers them at all is fabricating. Domain notes: the 3.5 EcoBoost
 * takes 6.0 quarts of 5W-30; a 26-gallon tank makes $80 fill-ups normal.
 */
import type { GoldenVehicle } from "./types";
import { entry as e } from "./types";

const OIL = "5W-30 full synthetic, 6.0 qt";

export const F150: GoldenVehicle = {
  id: "f150",
  label: "sparse-record 2-year truck",
  year: 2022,
  make: "Ford",
  model: "F-150",
  trim: "XLT SuperCrew 3.5L EcoBoost",
  currentOdometer: 31600,
  ownedSince: "2024-09-14 (purchased used at 18,400 mi)",
  entries: [
    e("2024-09-14", 18400, "maintenance", 175.00, "Firestone", "pre-purchase inspection", "no findings"),
    e("2024-10-02", 19100, "oil_change", 89.99, "Sheehy Ford", OIL, "Motorcraft filter"),
    e("2024-11-20", 20800, "fuel", 78.40, "Wawa", "24.1 gal regular"),
    e("2025-01-11", 22300, "maintenance", 28.40, "DIY", "cabin air filter"),
    e("2025-03-08", 23900, "oil_change", 54.30, "DIY", OIL, "Motorcraft filter, parts only"),
    e("2025-04-19", 24700, "tire", 0.00, "DIY", "rotation"),
    e("2025-06-27", 26200, "repair", 263.75, "Sheehy Ford", "tailgate latch actuator replaced"),
    e("2025-08-30", 27400, "oil_change", 92.50, "Sheehy Ford", OIL),
    e("2025-10-18", 28300, "fuel", 81.15, "Costco", "25.3 gal regular"),
    e("2026-01-24", 29200, "maintenance", 229.99, "DIY", "battery replaced", "Motorcraft BXT-65-650"),
    e("2026-03-21", 30100, "oil_change", 94.75, "Sheehy Ford", OIL),
    e("2026-03-21", 30100, "tire", 0.00, "Sheehy Ford", "rotation", "included with oil service"),
    e("2026-05-09", 30800, "fuel", 84.60, "Sheetz", "26.0 gal regular"),
    e("2026-06-13", 31200, "maintenance", 16.00, "Sheehy Ford", "Virginia state inspection", "passed"),
    e("2026-07-26", 31600, "brake", 65.00, "Sheehy Ford", "inspection",
      "front squeal investigated — pads measured 6 mm, no work performed"),
  ],
};
