package com.writes.garage.feature.handover

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.ReminderRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.observeActiveVehicle
import com.writes.garage.core.domain.Validators
import com.writes.garage.core.export.CsvExporter
import com.writes.garage.core.export.DossierContent
import com.writes.garage.core.export.DossierLine
import com.writes.garage.core.export.IcsBuilder
import com.writes.garage.core.export.PdfExporter
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.Reminder
import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.OutputStream
import java.time.Instant
import java.time.ZoneId

data class HandoverUiState(
    val vehicle: Vehicle? = null,
    val entryCount: Int = 0,
    /** Outstanding reminders with a due date (the only ones an .ics event can represent). */
    val datedReminderCount: Int = 0,
    val includeRecalls: Boolean = true,
    val busy: Boolean = false,
    /** Set when a file is ready; the screen launches the share sheet and calls [HandoverViewModel.shareHandled]. */
    val pendingShare: ExportedFile? = null,
    val message: String? = null,
    val error: String? = null,
)

/** Exports the active vehicle's resale dossier (PDF), entries (CSV) and reminders (ICS) and hands them to the share sheet. */
@OptIn(ExperimentalCoroutinesApi::class)
class HandoverViewModel(
    private val vehicles: VehicleRepository,
    private val entries: EntryRepository,
    private val reminders: ReminderRepository,
    private val functions: FunctionsGateway,
    private val store: ExportFileStore,
    private val renderPdf: (List<DossierLine>, OutputStream) -> Int = PdfExporter::write,
    private val clock: () -> Instant = Instant::now,
    private val zone: ZoneId = ZoneId.systemDefault(),
    private val io: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {
    private val _state = MutableStateFlow(HandoverUiState())
    val state: StateFlow<HandoverUiState> = _state.asStateFlow()

    private var entryList: List<Entry> = emptyList()
    private var reminderList: List<Reminder> = emptyList()

    init {
        viewModelScope.launch {
            vehicles.observeActiveVehicle().flatMapLatest { v ->
                if (v == null) {
                    flowOf(Triple(null, emptyList<Entry>(), emptyList<Reminder>()))
                } else {
                    combine(entries.observeEntries(v.id), reminders.observeReminders(v.id)) { e, r -> Triple(v, e, r) }
                }
            }.collect { (v, e, r) ->
                entryList = e
                reminderList = r
                _state.update {
                    it.copy(
                        vehicle = v, entryCount = e.size,
                        datedReminderCount = r.count { x -> x.isOutstanding && x.dueDate != null },
                    )
                }
            }
        }
    }

    fun setIncludeRecalls(include: Boolean) = _state.update { it.copy(includeRecalls = include) }

    fun exportPdf() = run("Building dossier...") { v ->
        val recalls = if (_state.value.includeRecalls) fetchRecalls(v) else emptyList()
        val now = clock()
        val lines = DossierContent.build(v, entryList.sortedByDescending { it.entryDate }, recalls, now, zone)
        withContext(io) { store.write(fileName(v, "dossier", "pdf", now), "application/pdf") { renderPdf(lines, it) } }
    }

    fun exportCsv() = run("Building CSV...") { v ->
        val csv = CsvExporter.export(entryList)
        withContext(io) {
            store.write(fileName(v, "entries", "csv", clock()), "text/csv") { it.write(csv.toByteArray(Charsets.UTF_8)) }
        }
    }

    fun exportIcs() = run("Building calendar file...") { v ->
        val now = clock()
        val ics = IcsBuilder.makeCalendar(reminderList.filter { it.isOutstanding }, now)
            ?: error("No upcoming reminders with a due date to export.")
        withContext(io) {
            store.write(fileName(v, "reminders", "ics", now), "text/calendar") { it.write(ics.toByteArray(Charsets.UTF_8)) }
        }
    }

    fun shareHandled() = _state.update { it.copy(pendingShare = null) }

    private fun run(label: String, block: suspend (Vehicle) -> ExportedFile) {
        val v = _state.value.vehicle
        if (v == null) {
            _state.update { it.copy(error = "Add a vehicle first.") }
            return
        }
        if (_state.value.busy) return
        viewModelScope.launch {
            _state.update { it.copy(busy = true, message = label, error = null) }
            runCatching { block(v) }
                .onSuccess { f -> _state.update { it.copy(busy = false, message = "Ready: ${f.fileName}", pendingShare = f) } }
                .onFailure { e -> _state.update { it.copy(busy = false, message = null, error = e.message ?: "Export failed.") } }
        }
    }

    /** Best effort: the dossier is still useful if the recall lookup is unavailable. */
    private suspend fun fetchRecalls(v: Vehicle): List<Recall> {
        val vin = Validators.normalizeVin(v.vin) ?: return emptyList()
        return runCatching { functions.lookupRecalls(v.id, vin) }.getOrDefault(emptyList())
    }

    companion object {
        fun fileName(v: Vehicle, kind: String, ext: String, now: Instant): String {
            val slug = v.displayName.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-').ifEmpty { "vehicle" }
            return "garage-$slug-$kind-${now.toString().take(10)}.$ext"
        }
    }
}
