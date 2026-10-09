package com.writes.garage.feature.log

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.observeActiveVehicle
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryQuery
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Entries of one calendar month, newest first. */
data class MonthGroup(val month: YearMonth, val label: String, val entries: List<Entry>) {
    val total: Double get() = entries.sumOf { it.cost ?: 0.0 }
}

data class LogUiState(
    val vehicles: List<Vehicle> = emptyList(),
    val activeVehicleId: String? = null,
    val entries: List<Entry> = emptyList(),
    val groups: List<MonthGroup> = emptyList(),
    val totalCount: Int = 0,
    val search: String = "",
    val types: Set<EntryType> = emptySet(),
    val hasVehicle: Boolean = true,
) {
    val isFiltering: Boolean get() = search.isNotBlank() || types.isNotEmpty()
}

private val monthLabel = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.US)

/** Groups [entries] (already sorted newest first) by calendar month in [zone]; keeps the incoming order. */
fun groupByMonth(entries: List<Entry>, zone: ZoneId): List<MonthGroup> =
    entries.groupBy { YearMonth.from(it.entryDate.atZone(zone)) }
        .map { (month, list) -> MonthGroup(month, monthLabel.format(month), list) }
        .sortedByDescending { it.month }

@OptIn(ExperimentalCoroutinesApi::class)
class LogViewModel(
    private val vehicleRepo: VehicleRepository,
    entryRepo: EntryRepository,
    private val zone: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    private val search = MutableStateFlow("")
    private val types = MutableStateFlow<Set<EntryType>>(emptySet())

    private data class Source(val vehicleId: String?, val entries: List<Entry>)

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    val state: StateFlow<LogUiState> = combine(
        vehicleRepo.observeVehicles(),
        vehicleRepo.observeActiveVehicle().flatMapLatest { v ->
            if (v == null) flowOf(Source(null, emptyList())) else entryRepo.observeEntries(v.id).map { Source(v.id, it) }
        },
        search,
        types,
    ) { vehicles, source, s, t ->
        val filtered = source.vehicleId?.let { id ->
            val q = EntryQuery(id, t, s)
            source.entries.filter(q::matches).sortedByDescending { it.entryDate }
        }.orEmpty()
        LogUiState(
            vehicles = vehicles,
            activeVehicleId = source.vehicleId,
            entries = filtered,
            groups = groupByMonth(filtered, zone),
            totalCount = source.entries.size,
            search = s,
            types = t,
            hasVehicle = source.vehicleId != null,
        )
    }.catch { e ->
        _error.value = e.message ?: "Couldn't load your log."
        emit(LogUiState())
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), LogUiState())

    fun setSearch(text: String) = search.update { text }

    fun toggleType(type: EntryType) = types.update { if (type in it) it - type else it + type }

    fun clearFilters() {
        search.value = ""
        types.value = emptySet()
    }

    fun selectVehicle(id: String) {
        viewModelScope.launch { runCatching { vehicleRepo.setActiveVehicle(id) } }
    }
}
