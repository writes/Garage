package com.writes.garage.core.data

import com.writes.garage.core.domain.OdometerFloor
import kotlinx.coroutines.flow.first

/**
 * Best effort: after an entry is saved, move the vehicle's odometer per [OdometerFloor]. The entry is already
 * persisted, so a failure here must not fail the save; it returns false so the caller can choose to mention it.
 */
suspend fun VehicleRepository.syncOdometer(
    vehicleId: String,
    reading: Int,
    otherEntriesMax: Int? = null,
    isEditing: Boolean = false,
    previousReading: Int? = null,
): Boolean = runCatching {
    val v = observeVehicle(vehicleId).first() ?: return@runCatching true
    val next = OdometerFloor.resulting(v.currentOdometer, reading, otherEntriesMax, isEditing, previousReading)
    if (next != v.currentOdometer) updateVehicle(v.copy(currentOdometer = next))
}.isSuccess
