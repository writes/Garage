package com.writes.garage.core.data

import com.writes.garage.core.model.Entry
import kotlinx.coroutines.flow.Flow

interface EntryRepository {
    /** Entries for one vehicle, newest first. */
    fun observeEntries(vehicleId: String): Flow<List<Entry>>

    fun observeEntry(vehicleId: String, entryId: String): Flow<Entry?>

    /** Persists a new entry; the returned entry carries the assigned id/timestamps. */
    suspend fun addEntry(entry: Entry): Entry

    suspend fun updateEntry(entry: Entry)

    suspend fun deleteEntry(vehicleId: String, entryId: String)
}
