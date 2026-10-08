package com.writes.garage.feature.garage

import com.writes.garage.core.data.MediaFolder
import com.writes.garage.core.data.PartsRepository
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.domain.PartForm
import com.writes.garage.core.domain.PartFormState
import com.writes.garage.core.model.SparePart
import com.writes.garage.feature.entry.PendingAttachment
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.ZoneId
import java.util.UUID

/** Spare-parts inventory: name, category, brand, part number, quantity, unit cost, location, condition, photo, receipt. */
class PartsViewModel(
    repo: PartsRepository,
    vehicleId: String,
    private val storage: StorageRepository? = null,
    private val zone: ZoneId = ZoneId.systemDefault(),
) : RecordsViewModel<SparePart, PartFormState>(repo, vehicleId) {
    /** Picks made in the open form, uploaded when it is saved (so cancelling uploads nothing). */
    private var pendingPhoto: PendingAttachment? = null
    private var pendingReceipt: PendingAttachment? = null
    private var removedPaths = mutableListOf<String>()

    override fun idOf(item: SparePart) = item.id

    override fun newForm() = PartFormState()

    override fun toForm(item: SparePart) = PartForm.from(item, zone)

    override fun build(form: PartFormState, existing: SparePart?): Pair<SparePart?, PartFormState> {
        val (p, errors) = PartForm.build(form, vehicleId, existing, zone)
        return p to form.copy(errors = errors)
    }

    override fun order(items: List<SparePart>) = PartForm.ordered(items)

    val hasStorage: Boolean get() = storage != null

    fun pickPhoto(a: PendingAttachment) {
        pendingPhoto = a
        update { copy(photoPath = photoPath?.also { removedPaths += it }?.let { null }) }
    }

    fun pickReceipt(a: PendingAttachment) {
        pendingReceipt = a
        update { copy(receiptPath = receiptPath?.also { removedPaths += it }?.let { null }) }
    }

    fun clearPhoto() {
        pendingPhoto = null
        update { copy(photoPath = photoPath?.also { removedPaths += it }?.let { null }) }
    }

    fun clearReceipt() {
        pendingReceipt = null
        update { copy(receiptPath = receiptPath?.also { removedPaths += it }?.let { null }) }
    }

    fun pendingPhotoName(): String? = pendingPhoto?.displayName

    fun pendingReceiptName(): String? = pendingReceipt?.displayName

    override suspend fun beforeSave(form: PartFormState, built: SparePart): SparePart {
        val repoStorage = storage
        val id = built.id.ifBlank { UUID.randomUUID().toString() }
        var out = built.copy(id = id)
        val uploaded = mutableListOf<String>()
        try {
            if (repoStorage != null) {
                pendingPhoto?.let { p ->
                    out = out.copy(photoStoragePath = repoStorage.uploadMedia(vehicleId, p.uri, p.mimeType, MediaFolder.PHOTOS, id).also { uploaded += it })
                }
                pendingReceipt?.let { r ->
                    out = out.copy(receiptStoragePath = repoStorage.uploadMedia(vehicleId, r.uri, r.mimeType, MediaFolder.RECEIPTS, id).also { uploaded += it })
                }
            }
        } catch (e: Throwable) {
            uploaded.forEach { runCatching { repoStorage?.deleteAttachment(it) } }
            throw e
        }
        // Replaced / cleared files are removed only once the record that referenced them is saved.
        removedPaths.toList().forEach { runCatching { repoStorage?.deleteAttachment(it) } }
        removedPaths.clear()
        pendingPhoto = null
        pendingReceipt = null
        return out
    }

    override fun delete(item: SparePart) {
        super.delete(item)
        val repoStorage = storage ?: return
        viewModelScope.launch {
            listOfNotNull(item.photoStoragePath, item.receiptStoragePath).forEach { runCatching { repoStorage.deleteAttachment(it) } }
        }
    }

    /** Toggles the consumed state without opening the form (consumed parts drop out of "on hand" and the dossier). */
    fun markConsumed(item: SparePart, consumed: Boolean) {
        viewModelScope.launch {
            runCatching { repo.upsert(item.copy(isConsumed = consumed)) }
                .onFailure { e -> _state.update { it.copy(error = e.message ?: "Couldn't update the part.") } }
        }
    }
}
