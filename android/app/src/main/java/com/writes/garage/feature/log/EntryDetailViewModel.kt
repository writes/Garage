package com.writes.garage.feature.log

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.AnalyticsEvents
import com.writes.garage.core.data.AnalyticsSink
import com.writes.garage.core.data.AttachmentMissingException
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.NoopAnalyticsSink
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.domain.AttachmentKind
import com.writes.garage.core.model.Entry
import com.writes.garage.feature.handover.ExportFileStore
import com.writes.garage.feature.handover.ExportedFile
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Loading state of one attachment shown on the entry detail. */
sealed interface AttachmentLoad {
    data object Loading : AttachmentLoad

    /** Image bytes for the thumbnail. */
    class Image(val bytes: ByteArray) : AttachmentLoad

    /** The Storage object is gone (e.g. removed by the server); the row offers to drop the dangling path. */
    data object Missing : AttachmentLoad

    data class Failed(val message: String) : AttachmentLoad

    /** A PDF: shown as a row with an Open action (opened in the system viewer on demand). */
    data object Pdf : AttachmentLoad
}

class EntryDetailViewModel(
    private val repo: EntryRepository,
    private val vehicleId: String,
    private val entryId: String,
    private val storage: StorageRepository? = null,
    private val store: ExportFileStore? = null,
    private val analytics: AnalyticsSink = NoopAnalyticsSink,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _attachments = MutableStateFlow<Map<String, AttachmentLoad>>(emptyMap())
    val attachments: StateFlow<Map<String, AttachmentLoad>> = _attachments.asStateFlow()

    /** A downloaded PDF ready for the system viewer; the screen launches it and calls [viewHandled]. */
    private val _pendingView = MutableStateFlow<ExportedFile?>(null)
    val pendingView: StateFlow<ExportedFile?> = _pendingView.asStateFlow()

    val entry: StateFlow<Entry?> = repo.observeEntry(vehicleId, entryId)
        .catch { e ->
            _error.value = e.message ?: "Couldn't load the entry."
            emit(null)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    init {
        viewModelScope.launch {
            entry.collect { e -> e?.attachmentPaths?.forEach { load(it) } }
        }
    }

    private fun load(path: String) {
        val s = storage
        if (s == null || _attachments.value.containsKey(path)) return
        if (AttachmentKind.fromPath(path) == AttachmentKind.PDF) {
            _attachments.update { it + (path to AttachmentLoad.Pdf) }
            return
        }
        _attachments.update { it + (path to AttachmentLoad.Loading) }
        viewModelScope.launch {
            val result = try {
                AttachmentLoad.Image(s.downloadAttachment(path))
            } catch (e: AttachmentMissingException) {
                AttachmentLoad.Missing
            } catch (e: Exception) {
                AttachmentLoad.Failed(e.message ?: "Couldn't load the attachment.")
            }
            _attachments.update { it + (path to result) }
        }
    }

    /** Downloads the PDF and hands it to the system viewer. */
    fun openPdf(path: String) {
        val s = storage ?: return
        val fileStore = store ?: return
        viewModelScope.launch {
            try {
                val bytes = s.downloadAttachment(path)
                val f = withContext(io) {
                    fileStore.write("attachment-${path.substringAfterLast('/')}", "application/pdf") { it.write(bytes) }
                }
                _pendingView.value = f
            } catch (e: AttachmentMissingException) {
                _attachments.update { it + (path to AttachmentLoad.Missing) }
            } catch (e: Exception) {
                _error.value = e.message ?: "Couldn't open the PDF."
            }
        }
    }

    fun viewHandled() {
        _pendingView.value = null
    }

    /** Drops a path whose Storage object no longer exists from the entry. */
    fun removeMissing(path: String) {
        val e = entry.value ?: return
        viewModelScope.launch {
            runCatching { repo.updateEntry(e.copy(attachmentPaths = e.attachmentPaths - path)) }
                .onFailure { err -> _error.update { err.message ?: "Couldn't update the entry." } }
        }
    }

    fun delete(onDone: () -> Unit) {
        viewModelScope.launch {
            runCatching { repo.deleteEntry(vehicleId, entryId) }
                .onSuccess {
                    analytics.log(AnalyticsEvents.ENTRY_DELETED, AnalyticsEvents.params())
                    onDone()
                }
                .onFailure { e -> _error.update { e.message ?: "Could not delete the entry." } }
        }
    }
}
