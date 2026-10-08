package com.writes.garage.core.notify

import com.writes.garage.core.model.Reminder
import com.writes.garage.core.model.Vehicle
import java.time.Duration
import java.time.Instant
import java.time.ZoneId

/** One local notification to schedule. [key] is stable per (reminder, lead) so it can be replaced / cancelled. */
data class PlannedAlarm(
    val key: String,
    val reminderId: String,
    val triggerAt: Instant,
    val title: String,
    val text: String,
)

/** Pure planning of which reminder notifications should exist (no Android). */
object ReminderPlanner {
    const val NOTIFY_HOUR = 9
    val LEAD_DAYS = listOf(3L, 0L)

    /** Android caps alarms per app (~500); the soonest few are all that matter between app launches. */
    const val MAX_ALARMS = 48

    /**
     * Outstanding reminders with a due date get a nudge [LEAD_DAYS] days before, at 09:00 local, and on the day.
     * Mileage-only reminders have no clock time and are skipped. Triggers already in the past are dropped.
     */
    fun plan(
        vehicles: List<Vehicle>,
        reminders: List<Reminder>,
        now: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
    ): List<PlannedAlarm> {
        val names = vehicles.associate { it.id to it.displayName }
        val out = mutableListOf<PlannedAlarm>()
        for (r in reminders) {
            val due = r.dueDate ?: continue
            if (!r.isOutstanding) continue
            val name = names[r.vehicleId] ?: continue
            val dueDay = due.atZone(zone).toLocalDate()
            for (lead in LEAD_DAYS) {
                val at = dueDay.minusDays(lead).atTime(NOTIFY_HOUR, 0).atZone(zone).toInstant()
                if (!at.isAfter(now)) continue
                val text = if (lead == 0L) "$name: due today" else "$name: due in $lead days"
                out += PlannedAlarm("${r.id}:$lead", r.id, at, r.title, text)
            }
        }
        return out.sortedBy { it.triggerAt }.take(MAX_ALARMS)
    }

    /** True when the trigger is far enough away to bother persisting for boot rescheduling. */
    fun isFuture(alarm: PlannedAlarm, now: Instant): Boolean = Duration.between(now, alarm.triggerAt) > Duration.ZERO
}
