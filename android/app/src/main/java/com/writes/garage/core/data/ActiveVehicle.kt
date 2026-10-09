package com.writes.garage.core.data

import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine

/** The selected vehicle, falling back to the first live vehicle (or null when the garage is empty). */
fun VehicleRepository.observeActiveVehicle(): Flow<Vehicle?> =
    combine(activeVehicleId, observeVehicles()) { id, list -> list.firstOrNull { it.id == id } ?: list.firstOrNull() }
