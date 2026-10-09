package com.writes.garage.core.data

import com.writes.garage.core.model.DetailingRecord
import com.writes.garage.core.model.GalleryPhoto
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.SparePart
import com.writes.garage.core.model.Warranty
import com.writes.garage.core.model.WearSnapshot
import kotlinx.coroutines.flow.Flow

/**
 * A per-vehicle record collection (`vehicles/{vehicleId}/<collection>/{id}`): gallery, warranties, spare parts,
 * detailing, stored recalls and wear snapshots all share this shape.
 */
interface VehicleRecordRepository<T> {
    fun observe(vehicleId: String): Flow<List<T>>

    /** Creates (blank id: one is assigned) or replaces the record; returns it with its id. */
    suspend fun upsert(item: T): T

    suspend fun delete(vehicleId: String, id: String)
}

typealias GalleryRepository = VehicleRecordRepository<GalleryPhoto>
typealias WarrantyRepository = VehicleRecordRepository<Warranty>
typealias PartsRepository = VehicleRecordRepository<SparePart>
typealias DetailingRepository = VehicleRecordRepository<DetailingRecord>
typealias RecallRepository = VehicleRecordRepository<Recall>
typealias WearRepository = VehicleRecordRepository<WearSnapshot>
