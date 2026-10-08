package com.writes.garage.core.data

import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

interface VehicleRepository {
    /** Non-deleted vehicles ordered by displayOrder. */
    fun observeVehicles(): Flow<List<Vehicle>>

    fun observeVehicle(vehicleId: String): Flow<Vehicle?>

    /** Id of the vehicle shown on Dashboard/Log/Stats; null when no vehicles exist. */
    val activeVehicleId: StateFlow<String?>

    suspend fun setActiveVehicle(vehicleId: String)

    /** Counted create. Throws [com.writes.garage.core.domain.VehicleLimitReachedException] past the plan limit. */
    suspend fun addVehicle(vehicle: Vehicle): Vehicle

    suspend fun updateVehicle(vehicle: Vehicle)

    /** Soft delete (sets deletedAt); never a hard delete client-side. */
    suspend fun deleteVehicle(vehicleId: String)
}
