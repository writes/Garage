package com.writes.garage.core.data

import com.writes.garage.core.domain.WearSnapshotFactory
import kotlinx.coroutines.flow.first

/**
 * Deleting an entry also removes what hangs off it (port of iOS `EntryService.deleteEntry` cascade): its Storage
 * attachments and its wear snapshots. The entry document is deleted first; the cleanup is best-effort so a failed
 * Storage delete never resurrects or blocks the deletion the user asked for.
 */
class CascadingEntryRepository(
    private val delegate: EntryRepository,
    private val storage: StorageRepository,
    private val wear: WearRepository,
    private val onCleanupFailure: (Throwable) -> Unit = {},
) : EntryRepository by delegate {
    override suspend fun deleteEntry(vehicleId: String, entryId: String) {
        val paths = runCatching { delegate.observeEntry(vehicleId, entryId).first()?.attachmentPaths.orEmpty() }
            .getOrDefault(emptyList())
        delegate.deleteEntry(vehicleId, entryId)
        for (path in paths) runCatching { storage.deleteAttachment(path) }.onFailure(onCleanupFailure)
        for (id in WearSnapshotFactory.allIdsFor(entryId)) runCatching { wear.delete(vehicleId, id) }.onFailure(onCleanupFailure)
    }
}
