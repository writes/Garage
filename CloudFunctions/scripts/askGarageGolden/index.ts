import type { GoldenVehicle } from "./types";
import type { VehicleId } from "./questions";
import { ACCORD } from "./accord";
import { F150 } from "./f150";
import { M2 } from "./m2";

export const GOLDEN_VEHICLES: Record<VehicleId, GoldenVehicle> = {
  accord: ACCORD,
  f150: F150,
  m2: M2,
};

export * from "./types";
export * from "./questions";
export * from "./aggregates";
