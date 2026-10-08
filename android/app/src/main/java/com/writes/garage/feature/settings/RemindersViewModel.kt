package com.writes.garage.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.AnalyticsEvents
import com.writes.garage.core.data.AnalyticsSink
import com.writes.garage.core.data.NoopAnalyticsSink
import com.writes.garage.core.data.ReminderRepository
import com.writes.garage.core.data.completeAndRoll
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.observeActiveVehicle
import com.writes.garage.core.domain.ReminderDueDatePreset
import com.writes.garage.core.domain.ReminderForm
import com.writes.garage.core.domain.ReminderFormState
import com.writes.garage.core.export.IcsBuilder
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Reminder
import com.writes.garage.core.model.Vehicle
import com.writes.garage.feature.dashboard.ReminderRow
import com.writes.garage.feature.dashboard.rankReminders
import com.writes.garage.feature.handover.ExportFileStore
import com.writes.garage.feature.handover.ExportedFile
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

data class RemindersUiState(
    val vehicle: Vehicle? = null,
    /** Outstanding reminders, overdue first. */
    val outstanding: List<ReminderRow> = emptyList(),
    /** Completed reminders, newest completion first. */
    val completed: List<Reminder> = emptyList(),
    val form: ReminderFormState = ReminderFormState(),
    val saving: Boolean = false,
    val saved: Boolean = false,
    val pendingShare: ExportedFile? = null,
    val error: String? = null,
) {
    val mileageOnlyHint: String? get() = ReminderForm.mileageOnlyHint(form)
}

/**
 * Create / edit / delete / mark-done reminders for the active vehicle, plus a per-reminder ICS hand-off. Alarms follow
 * automatically: `ReminderAlarmSync` re-plans whenever the repository's reminder flow emits.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RemindersViewModel(
    private val vehicles: VehicleRepository,
    private val reminders: ReminderRepository,
    private val store: ExportFileStore,
    private val clock: () -> Instant = Instant::now,
    private val zone: ZoneId = ZoneId.systemDefault(),
    private val io: CoroutineDispatcher = Dispatchers.IO,
    private val analytics: AnalyticsSink = NoopAnalyticsSink,
) : ViewModel() {
    private val _state = MutableStateFlow(RemindersUiState(form = ReminderFormState(dueDate = today().plusDays(1))))
    val state: StateFlow<RemindersUiState> = _state.asStateFlow()

    private var all: List<Reminder> = emptyList()
    private var vehicle: Vehicle? = null

    init {
        viewModelScope.launch {
            vehicles.observeActiveVehicle().flatMapLatest { v ->
                vehicle = v
                if (v == null) flowOf<Pair<Vehicle?, List<Reminder>>>(null to emptyList()) else reminders.observeReminders(v.id).map { v to it }
            }.catch { e -> _state.update { it.copy(error = e.message ?: "Couldn't load reminders.") } }
                .collect { (v, list) ->
                    all = list
                    _state.update {
                        it.copy(
                            vehicle = v,
                            outstanding = rankReminders(list, v?.currentOdometer, clock()),
                            completed = list.filter { r -> !r.isOutstanding }.sortedByDescending { r -> r.completedAt },
                        )
                    }
                }
        }
    }

    private fun today(): LocalDate = clock().atZone(zone).toLocalDate()

    // ---- form ----

    fun updateForm(transform: ReminderFormState.() -> ReminderFormState) =
        _state.update { it.copy(form = it.form.transform().copy(errors = emptyMap()), saved = false) }

    fun setEntryType(type: EntryType?) = updateForm { copy(entryType = type) }

    fun applyPreset(preset: ReminderDueDatePreset) = updateForm { copy(hasDueDate = true, dueDate = preset.date(today())) }

    fun beginEditing(r: Reminder) = _state.update {
        it.copy(form = ReminderForm.fromReminder(r, zone, today()), saved = false, pendingShare = null, error = null)
    }

    fun cancelEdit() = _state.update { it.copy(form = ReminderFormState(dueDate = today().plusDays(1)), saved = false) }

    fun save() {
        val s = _state.value
        val v = s.vehicle ?: run {
            _state.update { it.copy(error = "Add a vehicle first.") }
            return
        }
        if (s.saving) return
        val errors = ReminderForm.validate(s.form, today())
        if (errors.isNotEmpty()) {
            _state.update { it.copy(form = it.form.copy(errors = errors), error = "Fix the highlighted fields.") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(saving = true, error = null) }
            val existing = s.form.editingId?.let { id -> all.firstOrNull { it.id == id } }
            val reminder = ReminderForm.toReminder(s.form, v.id, existing, v.currentOdometer, zone)
            runCatching { if (existing == null) reminders.addReminder(reminder) else reminders.updateReminder(reminder) }
                .onSuccess {
                    if (existing == null) analytics.log(AnalyticsEvents.REMINDER_CREATED, AnalyticsEvents.params())
                    _state.update {
                        it.copy(saving = false, saved = true, form = ReminderFormState(dueDate = today().plusDays(1)), pendingShare = null)
                    }
                }
                .onFailure { e -> _state.update { it.copy(saving = false, error = e.message ?: "Couldn't save the reminder.") } }
        }
    }

    // ---- row actions ----

    fun delete(r: Reminder) {
        viewModelScope.launch {
            runCatching { reminders.deleteReminder(r.vehicleId, r.id) }
                .onSuccess {
                    analytics.log(AnalyticsEvents.REMINDER_DELETED, AnalyticsEvents.params())
                    if (_state.value.form.editingId == r.id) cancelEdit()
                }
                .onFailure { e -> _state.update { it.copy(error = e.message ?: "Couldn't delete the reminder.") } }
        }
    }

    private val completing = mutableSetOf<String>()

    /** Marks done; a repeating reminder schedules its next occurrence (same rule as the Dashboard). */
    fun markDone(r: Reminder) {
        if (!completing.add(r.id)) return // a double tap while the first completion is still running
        viewModelScope.launch {
            val now = clock()
            runCatching { reminders.completeAndRoll(r, now, zone) }.also { completing.remove(r.id) }.onSuccess {
                analytics.log(AnalyticsEvents.REMINDER_COMPLETED, AnalyticsEvents.params())
                if (_state.value.form.editingId == r.id) cancelEdit()
            }
                .onFailure { e -> _state.update { it.copy(error = e.message ?: "Couldn't complete the reminder.") } }
        }
    }

    /** Builds a single-event .ics for [r] and hands it to the share sheet. */
    fun exportCalendar(r: Reminder) {
        viewModelScope.launch {
            val now = clock()
            val ics = IcsBuilder.makeCalendar(r, now)
            if (ics == null) {
                _state.update { it.copy(error = "Add a due date to export this reminder to a calendar.") }
                return@launch
            }
            runCatching {
                withContext(io) {
                    store.write("garage-reminder-${r.id.take(8)}.ics", "text/calendar") { it.write(ics.toByteArray(Charsets.UTF_8)) }
                }
            }.onSuccess { f -> _state.update { it.copy(pendingShare = f, error = null) } }
                .onFailure { e -> _state.update { it.copy(error = e.message ?: "Couldn't create the calendar file.") } }
        }
    }

    fun shareHandled() = _state.update { it.copy(pendingShare = null) }

    fun dismissError() = _state.update { it.copy(error = null) }
}
