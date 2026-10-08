package com.writes.garage.feature.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.ReminderRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.observeActiveVehicle
import com.writes.garage.core.domain.Constants
import com.writes.garage.core.domain.MaintenanceDue
import com.writes.garage.core.domain.MaintenanceSchedule
import com.writes.garage.core.domain.ReminderSchedule
import com.writes.garage.core.domain.ReminderStatus
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.Reminder
import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Instant

data class ReminderRow(val reminder: Reminder, val status: ReminderStatus)

data class DashboardUiState(
    val vehicles: List<Vehicle> = emptyList(),
    val activeVehicle: Vehicle? = null,
    val recentEntries: List<Entry> = emptyList(),
    /** Outstanding reminders, overdue first, then by due date. */
    val reminders: List<ReminderRow> = emptyList(),
    /** Generic service intervals that want attention (see [MaintenanceSchedule]). */
    val attention: List<MaintenanceDue> = emptyList(),
    val loading: Boolean = true,
) {
    val upcomingReminders: List<Reminder> get() = reminders.map { it.reminder }
    val overdueCount: Int get() = reminders.count { it.status == ReminderStatus.OVERDUE }
}

/** Orders outstanding reminders for display: overdue, due soon, upcoming, unscheduled; then by due date. */
fun rankReminders(reminders: List<Reminder>, odometer: Int?, now: Instant): List<ReminderRow> =
    reminders.filter { it.isOutstanding }
        .map { ReminderRow(it, ReminderSchedule.status(it, odometer, now)) }
        .sortedWith(compareBy<ReminderRow> { it.status.ordinal }.thenBy { it.reminder.dueDate ?: Instant.MAX })

@OptIn(ExperimentalCoroutinesApi::class)
class DashboardViewModel(
    private val vehicleRepo: VehicleRepository,
    entryRepo: EntryRepository,
    private val reminderRepo: ReminderRepository,
    private val clock: () -> Instant = { Instant.now() },
) : ViewModel() {
    private val _error = MutableStateFlow<String?>(null)

    /** Listener / action failures (e.g. PERMISSION_DENIED while signing out); shown inline, never a crash. */
    val error: StateFlow<String?> = _error.asStateFlow()

    val state: StateFlow<DashboardUiState> = combine(
        vehicleRepo.observeVehicles(),
        vehicleRepo.observeActiveVehicle().flatMapLatest { v -> v?.let { withVehicle(it, entryRepo, reminderRepo) } ?: flowOf(null) },
    ) { vehicles, active ->
        val now = clock()
        val odometer = active?.vehicle?.currentOdometer
        DashboardUiState(
            vehicles = vehicles,
            activeVehicle = active?.vehicle,
            recentEntries = active?.entries.orEmpty().sortedByDescending { it.entryDate }.take(Constants.DASHBOARD_RECENT_LIMIT),
            reminders = rankReminders(active?.reminders.orEmpty(), odometer, now),
            attention = active?.let { MaintenanceSchedule.attentionNeeded(it.entries, odometer, now) }.orEmpty(),
            loading = false,
        )
    }.catch { e ->
        _error.value = e.message ?: "Couldn't load your dashboard."
        emit(DashboardUiState(loading = false))
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DashboardUiState())

    fun selectVehicle(id: String) {
        viewModelScope.launch { runCatching { vehicleRepo.setActiveVehicle(id) } }
    }

    fun dismissError() {
        _error.value = null
    }

    /** Marks the reminder done; a repeating reminder schedules its next occurrence. */
    fun completeReminder(reminder: Reminder) {
        viewModelScope.launch {
            val now = clock()
            val odometer = state.value.activeVehicle?.currentOdometer
            runCatching {
                reminderRepo.completeReminder(reminder.vehicleId, reminder.id)
                ReminderSchedule.nextOccurrence(reminder, now, odometer)?.let { reminderRepo.addReminder(it) }
            }.onFailure { e -> _error.value = e.message ?: "Couldn't complete the reminder." }
        }
    }

    private class ActiveBundle(val vehicle: Vehicle, val entries: List<Entry>, val reminders: List<Reminder>)

    private fun withVehicle(v: Vehicle, entries: EntryRepository, reminders: ReminderRepository): Flow<ActiveBundle?> =
        combine(entries.observeEntries(v.id), reminders.observeReminders(v.id)) { e, r -> ActiveBundle(v, e, r) }
}
