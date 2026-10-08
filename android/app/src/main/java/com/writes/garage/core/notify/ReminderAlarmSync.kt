package com.writes.garage.core.notify

import android.content.Context
import com.writes.garage.core.data.ReminderRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.model.Reminder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.retryWhen
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * Keeps the OS alarms in step with the user's reminders and the Settings toggle. Runs for the life of the process;
 * the persisted plan covers the gaps (reboot) when the process is not running.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ReminderAlarmSync(
    private val context: Context,
    private val vehicles: VehicleRepository,
    private val reminders: ReminderRepository,
    private val settings: NotificationSettings,
    private val clock: () -> Instant = Instant::now,
) {
    fun start(scope: CoroutineScope) {
        scope.launch {
            val all: Flow<Pair<List<com.writes.garage.core.model.Vehicle>, List<Reminder>>> =
                vehicles.observeVehicles().flatMapLatest { vs ->
                    if (vs.isEmpty()) {
                        flowOf(vs to emptyList())
                    } else {
                        combine(vs.map { v -> reminders.observeReminders(v.id).catch { emit(emptyList()) } }) { lists ->
                            vs to lists.toList().flatten()
                        }
                    }
                }.retryWhen { _, attempt ->
                    // A listener error (e.g. at sign-out) must not end syncing for the rest of the process:
                    // clear the plan, back off, resubscribe.
                    emit(emptyList<com.writes.garage.core.model.Vehicle>() to emptyList())
                    delay(minOf(attempt + 1, 30L) * 1000)
                    true
                }
            combine(settings.enabled, all) { on, data -> if (on) data else null }.collectLatest { data ->
                val plan = data?.let { (vs, rs) -> ReminderPlanner.plan(vs, rs, clock()) }.orEmpty()
                runCatching { ReminderAlarms.apply(context, plan) }
            }
        }
    }
}
