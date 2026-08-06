/**
 * Golden vehicle 1 — the meticulous owner. 2016 Honda Accord EX-L 2.4, bought new, 56 entries
 * across nine years (13k mi/yr), 19 oil changes on a ~5,300-mile cadence, three tire sets with
 * an alignment each, two brake jobs plus a fluid flush, two transmission drain-and-fills.
 *
 * Domain notes (a wrong-by-domain golden set invalidates the eval):
 *  - The K24W 2.4 takes 0W-20 and 4.4 quarts with a filter change; EX-L 4-cyl rides on 225/50R17.
 *  - It uses a timing CHAIN, so "when was the timing belt done" is unanswerable by construction —
 *    and the 2026 serpentine-belt entry is the near-miss distractor that makes it a real test.
 *  - Costs track a Northern Virginia dealer/independent mix; DIY oil changes are parts-only.
 */
import type { GoldenVehicle } from "./types";
import { entry as e } from "./types";

const OIL = "0W-20 full synthetic, 4.4 qt";

export const ACCORD: GoldenVehicle = {
  id: "accord",
  label: "meticulous 8-year sedan",
  year: 2016,
  make: "Honda",
  model: "Accord",
  trim: "EX-L 2.4",
  currentOdometer: 104120,
  ownedSince: "2016-11-04 (purchased new)",
  entries: [
    e("2017-03-11", 5120, "oil_change", 54.95, "Honda of Chantilly", OIL),
    e("2017-09-22", 10410, "oil_change", 54.95, "Honda of Chantilly", OIL),
    e("2018-03-16", 15780, "oil_change", 58.95, "Honda of Chantilly", OIL),
    e("2018-05-12", 17300, "maintenance", 38.60, "DIY", "engine air filter + cabin air filter"),
    e("2018-08-04", 20100, "upgrade", 329.00, "Honda of Chantilly", "OEM roof rack crossbars", "accessory install"),
    e("2018-09-28", 21050, "oil_change", 58.95, "Honda of Chantilly", OIL),
    e("2019-03-22", 26340, "oil_change", 61.95, "Honda of Chantilly", OIL),
    e("2019-04-06", 27100, "tire", 784.20, "Discount Tire",
      "new_install — Michelin Defender T+H, 225/50R17", "set of four, road hazard included"),
    e("2019-04-06", 27100, "alignment", 99.99, "Discount Tire", "four-wheel alignment"),
    e("2019-08-17", 30100, "maintenance", 20.00, "Roy's Auto Service", "Virginia state inspection", "passed"),
    e("2019-10-04", 31700, "oil_change", 39.80, "DIY", OIL, "Mobil 1 + Honda filter"),
    e("2020-04-10", 36920, "oil_change", 39.80, "DIY", OIL),
    e("2020-06-13", 38200, "tire", 25.00, "Discount Tire", "rotation"),
    e("2020-09-05", 40700, "maintenance", 189.00, "Honda of Chantilly",
      "transmission fluid drain and fill", "Honda ATF DW-1"),
    e("2020-11-13", 42180, "oil_change", 64.95, "Honda of Chantilly", OIL),
    e("2021-03-06", 45300, "brake", 486.50, "Midas",
      "pads_replaced — front pads and rotors", "Wagner ThermoQuiet pads"),
    e("2021-05-21", 47460, "oil_change", 42.60, "DIY", OIL),
    e("2021-08-07", 49900, "tire", 25.00, "Discount Tire", "rotation"),
    e("2021-09-25", 51200, "maintenance", 268.40, "Honda of Chantilly", "spark plugs replaced", "NGK iridium, set of four"),
    e("2021-11-19", 52830, "oil_change", 64.95, "Honda of Chantilly", OIL),
    e("2022-03-19", 56700, "maintenance", 189.99, "DIY", "battery replaced", "Interstate MTP-51R"),
    e("2022-05-13", 58090, "oil_change", 44.20, "DIY", OIL),
    e("2022-07-09", 60340, "tire", 812.44, "Discount Tire",
      "new_install — Continental TrueContact Tour, 225/50R17", "set of four"),
    e("2022-07-09", 60340, "alignment", 109.99, "Discount Tire", "four-wheel alignment"),
    e("2022-11-11", 63410, "oil_change", 69.95, "Honda of Chantilly", OIL),
    e("2023-01-28", 65100, "repair", 612.40, "Roy's Auto Service", "starter motor replaced",
      "no-crank condition, diagnosed and replaced same day"),
    e("2023-03-11", 66400, "maintenance", 149.00, "Honda of Chantilly", "coolant flush", "Honda Type 2 coolant"),
    e("2023-04-08", 67900, "fuel", 43.95, "Wawa", "12.8 gal regular"),
    e("2023-05-19", 68720, "oil_change", 46.80, "DIY", OIL),
    e("2023-06-24", 69200, "brake", 129.00, "Honda of Chantilly", "fluid_flush — brake fluid"),
    e("2023-08-05", 71200, "fuel", 45.60, "Sheetz", "13.1 gal regular"),
    e("2023-09-16", 72110, "tire", 28.00, "Discount Tire", "rotation"),
    e("2023-11-17", 74050, "oil_change", 72.95, "Honda of Chantilly", OIL),
    e("2024-02-17", 76900, "brake", 312.80, "Midas", "pads_replaced — rear pads", "rotors resurfaced"),
    e("2024-03-30", 78100, "fuel", 42.75, "Costco", "12.4 gal regular"),
    e("2024-05-24", 79380, "oil_change", 48.30, "DIY", OIL),
    e("2024-06-02", 79900, "fuel", 47.86, "Wawa", "13.4 gal regular"),
    e("2024-07-14", 80700, "fuel", 44.12, "Costco", "12.9 gal regular"),
    e("2024-08-10", 81650, "tire", 28.00, "Discount Tire", "rotation"),
    e("2024-09-21", 82900, "maintenance", 214.00, "Honda of Chantilly",
      "transmission fluid drain and fill", "Honda ATF DW-1"),
    e("2024-11-15", 84610, "oil_change", 74.95, "Honda of Chantilly", OIL),
    e("2025-01-19", 86400, "fuel", 41.30, "Wawa", "12.6 gal regular"),
    e("2025-02-08", 87300, "maintenance", 44.20, "DIY", "engine air filter + cabin air filter"),
    e("2025-04-05", 89100, "repair", 498.00, "Roy's Auto Service", "front wheel bearing replaced (driver side)"),
    e("2025-05-16", 89940, "oil_change", 51.20, "DIY", OIL),
    e("2025-06-21", 90600, "fuel", 47.10, "Wawa", "13.5 gal regular"),
    e("2025-08-16", 91880, "tire", 948.72, "Discount Tire",
      "new_install — Michelin CrossClimate2, 225/50R17", "set of four"),
    e("2025-08-16", 91880, "alignment", 119.99, "Discount Tire", "four-wheel alignment"),
    e("2025-09-27", 93100, "fuel", 49.55, "Sheetz", "14.1 gal regular"),
    e("2025-11-14", 95260, "oil_change", 79.95, "Honda of Chantilly", OIL),
    e("2026-02-08", 98300, "fuel", 46.02, "Costco", "13.2 gal regular"),
    e("2026-03-14", 99100, "maintenance", 178.00, "Honda of Chantilly", "serpentine belt replaced"),
    e("2026-04-25", 99900, "fuel", 50.24, "Sheetz", "14.0 gal regular"),
    e("2026-05-15", 100580, "oil_change", 52.90, "DIY", OIL, "Mobil 1 + Honda filter"),
    e("2026-06-20", 101900, "maintenance", 20.00, "Roy's Auto Service", "Virginia state inspection", "passed"),
    e("2026-07-11", 103200, "fuel", 48.71, "Wawa", "13.8 gal regular"),
  ],
};
