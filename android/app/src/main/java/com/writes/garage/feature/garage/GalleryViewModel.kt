package com.writes.garage.feature.garage

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.GalleryRepository
import com.writes.garage.core.data.MediaFolder
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.domain.GalleryForm
import com.writes.garage.core.domain.GalleryFormState
import com.writes.garage.core.model.GalleryPhoto
import com.writes.garage.core.model.GallerySection
import com.writes.garage.feature.entry.PendingAttachment
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.ZoneId

data class GalleryUiState(
    /** This screen's section only, in display order. */
    val photos: List<GalleryPhoto> = emptyList(),
    val form: GalleryFormState? = null,
    /** The picked file waiting for a title (new photo); null while editing a stored one. */
    val pending: PendingAttachment? = null,
    val saving: Boolean = false,
    val error: String? = null,
)

/** Photo gallery (section MAIN) and wheel gallery (section WHEEL): upload, edit metadata, export flag, ordering. */
class GalleryViewModel(
    private val repo: GalleryRepository,
    private val storage: StorageRepository,
    private val vehicleId: String,
    private val section: GallerySection,
    private val zone: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    private val _state = MutableStateFlow(GalleryUiState())
    val state: StateFlow<GalleryUiState> = _state.asStateFlow()

    /** Every photo of the vehicle (both sections): ordering numbers are allocated across the whole collection. */
    private var all: List<GalleryPhoto> = emptyList()

    init {
        viewModelScope.launch {
            repo.observe(vehicleId)
                .catch { e -> _state.update { it.copy(error = e.message ?: "Couldn't load the gallery.") } }
                .collect { list ->
                    all = list
                    _state.update { it.copy(photos = list.filter { p -> p.section == section }.sortedBy { p -> p.displayOrder }) }
                }
        }
    }

    /** A photo was picked: ask for its details; nothing is uploaded until the form is saved. */
    fun pick(a: PendingAttachment) {
        if (!a.mimeType.startsWith("image/")) {
            _state.update { it.copy(error = "Only photos can be added to the gallery.") }
            return
        }
        _state.update {
            it.copy(
                pending = a, error = null,
                form = GalleryFormState(section = section, title = if (section == GallerySection.WHEEL) "Wheel set" else ""),
            )
        }
    }

    fun edit(p: GalleryPhoto) = _state.update { it.copy(form = GalleryForm.from(p, zone), pending = null, error = null) }

    fun cancel() = _state.update { it.copy(form = null, pending = null, error = null) }

    fun update(transform: GalleryFormState.() -> GalleryFormState) = _state.update { s -> s.form?.let { s.copy(form = it.transform()) } ?: s }

    fun save() {
        val s = _state.value
        val form = s.form ?: return
        if (s.saving) return
        val errors = GalleryForm.validate(form)
        if (errors.isNotEmpty()) {
            _state.update { it.copy(form = form.copy(errors = errors), error = "Fix the highlighted fields.") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(saving = true, error = null) }
            var uploaded: String? = null
            runCatching {
                val existing = form.editingId?.let { id -> all.firstOrNull { it.id == id } }
                val base = if (existing != null) {
                    existing
                } else {
                    val pending = s.pending ?: error("Pick a photo first.")
                    uploaded = storage.uploadMedia(vehicleId, pending.uri, pending.mimeType, MediaFolder.GALLERY)
                    GalleryPhoto(id = "", vehicleId = vehicleId, title = "", storagePath = uploaded!!, displayOrder = GalleryForm.nextOrder(all))
                }
                repo.upsert(GalleryForm.apply(form, base, zone))
            }.onSuccess { _state.update { it.copy(saving = false, form = null, pending = null) } }
                .onFailure { e ->
                    // The photo never got a record: don't leave an orphaned file behind.
                    uploaded?.let { path -> runCatching { storage.deleteAttachment(path) } }
                    _state.update { it.copy(saving = false, error = e.message ?: "Couldn't save the photo.") }
                }
        }
    }

    fun toggleExport(p: GalleryPhoto) = write { repo.upsert(p.copy(includeInExport = !p.includeInExport)) }

    /** [delta] -1 moves the photo earlier, +1 later within this section. */
    fun move(p: GalleryPhoto, delta: Int) {
        val index = _state.value.photos.indexOfFirst { it.id == p.id }
        if (index < 0) return
        val reordered = GalleryForm.reorder(_state.value.photos, index, delta)
        val before = _state.value.photos.associate { it.id to it.displayOrder }
        write { reordered.filter { before[it.id] != it.displayOrder }.forEach { repo.upsert(it) } }
    }

    fun delete(p: GalleryPhoto) = write {
        repo.delete(vehicleId, p.id)
        runCatching { storage.deleteAttachment(p.storagePath) }
    }

    fun reportError(message: String) = _state.update { it.copy(error = message) }

    private fun write(block: suspend () -> Unit) {
        viewModelScope.launch {
            runCatching { block() }.onFailure { e -> _state.update { it.copy(error = e.message ?: "Couldn't update the gallery.") } }
        }
    }
}
