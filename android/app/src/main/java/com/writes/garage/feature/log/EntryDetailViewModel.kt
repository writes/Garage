package com.writes.garage.feature.log

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.model.Entry
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class EntryDetailViewModel(
    private val repo: EntryRepository,
    private val vehicleId: String,
    private val entryId: String,
) : ViewModel() {
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    val entry: StateFlow<Entry?> = repo.observeEntry(vehicleId, entryId)
        .catch { e ->
            _error.value = e.message ?: "Couldn't load the entry."
            emit(null)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    fun delete(onDone: () -> Unit) {
        viewModelScope.launch {
            runCatching { repo.deleteEntry(vehicleId, entryId) }
                .onSuccess { onDone() }
                .onFailure { e -> _error.update { e.message ?: "Could not delete the entry." } }
        }
    }
}
