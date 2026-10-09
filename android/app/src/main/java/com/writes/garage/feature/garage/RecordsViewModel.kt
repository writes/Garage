package com.writes.garage.feature.garage

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.VehicleRecordRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant

data class RecordsUiState<T, F>(
    val items: List<T> = emptyList(),
    /** The open add/edit form, or null when only the list is showing. */
    val form: F? = null,
    val saving: Boolean = false,
    val error: String? = null,
)

/**
 * List + add/edit form over one per-vehicle record collection (warranties, spare parts, detailing). Subclasses supply
 * the form <-> model mapping; saving is an id-keyed upsert, so an edit updates the stored document.
 */
abstract class RecordsViewModel<T, F>(
    protected val repo: VehicleRecordRepository<T>,
    protected val vehicleId: String,
    /** Passed up (not a subclass field): the first emission is ordered inside this constructor, before subclass fields exist. */
    protected val clock: () -> Instant = Instant::now,
) : ViewModel() {
    protected val _state = MutableStateFlow(RecordsUiState<T, F>())
    val state: StateFlow<RecordsUiState<T, F>> = _state.asStateFlow()

    protected abstract fun idOf(item: T): String

    protected abstract fun newForm(): F

    protected abstract fun toForm(item: T): F

    /** Validated model + the form (carrying any field errors). */
    protected abstract fun build(form: F, existing: T?): Pair<T?, F>

    protected open fun order(items: List<T>): List<T> = items

    /** Called with the saved item, e.g. to upload media first. Default: nothing. */
    protected open suspend fun beforeSave(form: F, built: T): T = built

    private var editingId: String? = null

    init {
        viewModelScope.launch {
            repo.observe(vehicleId)
                .catch { e -> _state.update { it.copy(error = e.message ?: "Couldn't load these records.") } }
                .collect { list -> _state.update { it.copy(items = order(list)) } }
        }
    }

    fun startNew() {
        editingId = null
        _state.update { it.copy(form = newForm(), error = null) }
    }

    fun startEdit(item: T) {
        editingId = idOf(item)
        _state.update { it.copy(form = toForm(item), error = null) }
    }

    fun cancel() {
        editingId = null
        _state.update { it.copy(form = null, error = null) }
    }

    fun update(transform: F.() -> F) = _state.update { s -> s.form?.let { s.copy(form = it.transform()) } ?: s }

    fun save() {
        val s = _state.value
        val form = s.form ?: return
        if (s.saving) return
        val existing = editingId?.let { id -> s.items.firstOrNull { idOf(it) == id } }
        val (built, checked) = build(form, existing)
        if (built == null) {
            _state.update { it.copy(form = checked, error = "Fix the highlighted fields.") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(saving = true, error = null) }
            runCatching { repo.upsert(beforeSave(form, built)) }
                .onSuccess { editingId = null; _state.update { it.copy(saving = false, form = null) } }
                .onFailure { e -> _state.update { it.copy(saving = false, error = e.message ?: "Couldn't save.") } }
        }
    }

    open fun delete(item: T) {
        viewModelScope.launch {
            runCatching { repo.delete(vehicleId, idOf(item)) }
                .onFailure { e -> _state.update { it.copy(error = e.message ?: "Couldn't delete.") } }
        }
    }
}
