package com.writes.garage.core.data.demo

import com.writes.garage.core.data.VehicleRecordRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update

/** In-memory per-vehicle record collection backed by one [MutableStateFlow] in the [DemoStore]. */
class DemoRecordRepository<T>(
    private val store: DemoStore,
    private val items: MutableStateFlow<List<T>>,
    private val idPrefix: String,
    private val id: (T) -> String,
    private val vehicleId: (T) -> String,
    private val withId: (T, String) -> T,
) : VehicleRecordRepository<T> {
    override fun observe(vehicleId: String): Flow<List<T>> =
        items.map { list -> list.filter { this.vehicleId(it) == vehicleId } }

    override suspend fun upsert(item: T): T {
        val saved = if (id(item).isBlank()) withId(item, store.newId(idPrefix)) else item
        items.update { list ->
            if (list.any { id(it) == id(saved) }) list.map { if (id(it) == id(saved)) saved else it } else list + saved
        }
        return saved
    }

    override suspend fun delete(vehicleId: String, id: String) {
        items.update { list -> list.filterNot { this.id(it) == id && this.vehicleId(it) == vehicleId } }
    }
}

/** Factories wiring each record type to its [DemoStore] flow. */
object DemoRecords {
    fun gallery(s: DemoStore) = DemoRecordRepository(s, s.gallery, "photo", { it.id }, { it.vehicleId }, { x, i -> x.copy(id = i) })

    fun warranties(s: DemoStore) =
        DemoRecordRepository(s, s.warranties, "warranty", { it.id }, { it.vehicleId }, { x, i -> x.copy(id = i) })

    fun parts(s: DemoStore) = DemoRecordRepository(s, s.parts, "part", { it.id }, { it.vehicleId }, { x, i -> x.copy(id = i) })

    fun detailing(s: DemoStore) =
        DemoRecordRepository(s, s.detailing, "detailing", { it.id }, { it.vehicleId }, { x, i -> x.copy(id = i) })

    fun recalls(s: DemoStore) =
        DemoRecordRepository(s, s.recalls, "recall", { it.id }, { it.vehicleId }, { x, i -> x.copy(id = i) })

    fun wear(s: DemoStore) = DemoRecordRepository(s, s.wear, "wear", { it.id }, { it.vehicleId }, { x, i -> x.copy(id = i) })
}
