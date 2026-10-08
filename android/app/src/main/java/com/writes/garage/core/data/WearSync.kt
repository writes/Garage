package com.writes.garage.core.data

import com.writes.garage.core.domain.WearSnapshotFactory
import com.writes.garage.core.model.Entry

/** Writes (or clears) the wear snapshots a brake/tire entry implies, alongside the entry save. Best-effort. */
class WearSync(private val wear: WearRepository) {
    /** [entry] must carry its final id. On an edit, snapshots the entry no longer produces are deleted. */
    suspend fun sync(entry: Entry, isEdit: Boolean) {
        val write = WearSnapshotFactory.write(entry, entry.entryDate)
        write.snapshots.forEach { runCatching { wear.upsert(it) } }
        val stale = if (isEdit) {
            (write.clearedIds + WearSnapshotFactory.allIdsFor(entry.id)).distinct() - write.snapshots.map { it.id }.toSet()
        } else {
            emptyList()
        }
        stale.forEach { runCatching { wear.delete(entry.vehicleId, it) } }
    }
}
