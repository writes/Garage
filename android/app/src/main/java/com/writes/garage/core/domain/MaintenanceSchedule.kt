package com.writes.garage.core.domain

import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Reminder
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Generic service intervals and the rule for deciding what a vehicle is due for (port of iOS
 * `MaintenanceItem` / `MaintenanceAdvisor`). Intervals are the SHORT end of the typical range; the owner's
 * manual always wins.
 */
enum class MaintenanceItem(
    val label: String,
    val clearedBy: EntryType,
    val intervalMiles: Int,
    val intervalMonths: Int,
) {
    OIL_AND_FILTER("Oil & filter", EntryType.OIL_CHANGE, 5_000, 6),
    TIRE_ROTATION("Tire rotation", EntryType.TIRE, 6_000, 6),
    BRAKE_INSPECTION("Brake inspection", EntryType.BRAKE, 12_000, 12),
    WHEEL_ALIGNMENT("Wheel alignment", EntryType.ALIGNMENT, 12_000, 12),
}

enum class MaintenanceStatus { OVERDUE, DUE_SOON, UP_TO_DATE, NEVER_LOGGED }

data class MaintenanceDue(
    val item: MaintenanceItem,
    val status: MaintenanceStatus,
    /** Positive when past due, negative when still remaining; null with no odometer baseline. */
    val milesPastDue: Int?,
    val dueDate: Instant?,
    val lastServicedAt: Instant?,
)

object MaintenanceSchedule {
    const val DUE_SOON_FRACTION = 0.1
    private const val SECONDS_PER_MONTH = 30.44 * 24 * 60 * 60

    /** Tire actions that actually reset the rotation clock (measurements and removals do not). */
    private val rotationClearingActions = setOf("rotation", "new_install")

    private fun clears(item: MaintenanceItem, entry: Entry): Boolean {
        if (item != MaintenanceItem.TIRE_ROTATION) return entry.entryType == item.clearedBy
        return when (entry.entryType) {
            // Fails OPEN for tire entries predating the action discriminator.
            EntryType.TIRE -> {
                val action = entry.details["actionType"] as? String
                action == null || action in rotationClearingActions
            }
            // Fails CLOSED: only an explicit rotate/balance maintenance item counts.
            EntryType.MAINTENANCE -> entry.details["item"] == "rotate_balance_tires"
            else -> false
        }
    }

    private fun addMonths(from: Instant, months: Int): Instant =
        from.atZone(ZoneOffset.UTC).plusMonths(months.toLong()).toInstant()

    fun status(item: MaintenanceItem, entries: List<Entry>, currentOdometer: Int?, now: Instant): MaintenanceDue {
        val last = entries.filter { clears(item, it) }.maxByOrNull { it.entryDate }
            ?: return MaintenanceDue(item, MaintenanceStatus.NEVER_LOGGED, null, null, null)

        val dueDate = addMonths(last.entryDate, item.intervalMonths)
        // A zero odometer means "not recorded", not "mile zero".
        val milesPastDue = if (currentOdometer != null && currentOdometer > 0 && last.odometerReading > 0) {
            (currentOdometer - last.odometerReading) - item.intervalMiles
        } else {
            null
        }
        return MaintenanceDue(item, resolve(milesPastDue, dueDate, item, now), milesPastDue, dueDate, last.entryDate)
    }

    /** Either axis alone is enough to be due ("5,000 miles OR 6 months"). */
    private fun resolve(milesPastDue: Int?, dueDate: Instant, item: MaintenanceItem, now: Instant): MaintenanceStatus {
        val overdueOnMiles = (milesPastDue ?: Int.MIN_VALUE) >= 0
        val overdueOnTime = dueDate <= now
        if (overdueOnMiles || overdueOnTime) return MaintenanceStatus.OVERDUE

        val warningMiles = (item.intervalMiles * DUE_SOON_FRACTION).toInt()
        val soonOnMiles = milesPastDue?.let { it >= -warningMiles } ?: false
        val warningSeconds = item.intervalMonths * DUE_SOON_FRACTION * SECONDS_PER_MONTH
        val soonOnTime = (dueDate.epochSecond - now.epochSecond) <= warningSeconds
        return if (soonOnMiles || soonOnTime) MaintenanceStatus.DUE_SOON else MaintenanceStatus.UP_TO_DATE
    }

    private fun rank(s: MaintenanceStatus) = when (s) {
        MaintenanceStatus.OVERDUE -> 0
        MaintenanceStatus.DUE_SOON -> 1
        MaintenanceStatus.NEVER_LOGGED -> 2
        MaintenanceStatus.UP_TO_DATE -> 3
    }

    /** Everything that wants attention, worst first; empty when there is no history at all. */
    fun attentionNeeded(entries: List<Entry>, currentOdometer: Int?, now: Instant): List<MaintenanceDue> {
        if (entries.isEmpty()) return emptyList()
        return MaintenanceItem.entries
            .map { status(it, entries, currentOdometer, now) }
            .filter { it.status != MaintenanceStatus.UP_TO_DATE }
            .sortedWith(compareBy<MaintenanceDue> { rank(it.status) }.thenBy { it.item.name })
    }
}

/** Status of a user-created [Reminder] (due date and/or due mileage). */
enum class ReminderStatus { COMPLETED, OVERDUE, DUE_SOON, UPCOMING, NO_SCHEDULE }

object ReminderSchedule {
    /** Dates within this many days (or mileage within [SOON_MILES]) read as "due soon". */
    const val SOON_DAYS = 14L
    const val SOON_MILES = 500

    fun status(reminder: Reminder, currentOdometer: Int?, now: Instant): ReminderStatus {
        if (!reminder.isOutstanding) return ReminderStatus.COMPLETED
        val due = reminder.dueDate
        val dueMiles = reminder.dueMileage
        if (due == null && dueMiles == null) return ReminderStatus.NO_SCHEDULE

        val overdueDate = due != null && due <= now
        val overdueMiles = dueMiles != null && currentOdometer != null && currentOdometer > 0 && currentOdometer >= dueMiles
        if (overdueDate || overdueMiles) return ReminderStatus.OVERDUE

        val soonDate = due != null && due.epochSecond - now.epochSecond <= SOON_DAYS * 86_400
        val soonMiles = dueMiles != null && currentOdometer != null && currentOdometer > 0 &&
            dueMiles - currentOdometer <= SOON_MILES
        return if (soonDate || soonMiles) ReminderStatus.DUE_SOON else ReminderStatus.UPCOMING
    }

    /**
     * The follow-up of a repeating reminder after it was completed at [completedAt] (iOS `scheduleSuccessorIfRepeating` parity).
     *
     * Only a reminder that is BOTH date-based and has a repeat interval in months repeats: a mileage-only reminder (or one
     * that only has a miles interval) gets no successor. The due date rolls forward from whichever is later, the old due
     * date or [completedAt] (so a long-overdue completion does not roll from a stale date), by the calendar months in
     * [zone] (month ends clamp: Aug 31 + 6 months = Feb 28). The due mileage advances by the miles interval when both are
     * set. The id is deterministic ([successorId]) so retrying or double-tapping the completion can never mint two.
     */
    fun nextOccurrence(reminder: Reminder, completedAt: Instant, zone: ZoneId = ZoneId.systemDefault()): Reminder? {
        val months = reminder.repeatIntervalMonths?.takeIf { it > 0 } ?: return null
        val due = reminder.dueDate ?: return null
        val base = maxOf(due, completedAt)
        val miles = reminder.repeatIntervalMiles?.takeIf { it > 0 }
        return reminder.copy(
            id = successorId(reminder.id),
            dueDate = base.atZone(zone).plusMonths(months.toLong()).toInstant(),
            dueMileage = if (reminder.dueMileage != null && miles != null) reminder.dueMileage + miles else reminder.dueMileage,
            createdAt = null,
            completedAt = null,
        )
    }

    /**
     * Deterministic and bounded: `r1` -> `r1-next` -> `r1-next2` -> `r1-next3` (a generation counter instead of an ever
     * longer `-next-next-...` chain).
     */
    fun successorId(reminderId: String): String {
        val m = Regex("^(.*-next)(\\d*)$").matchEntire(reminderId) ?: return "$reminderId-next"
        val generation = m.groupValues[2].toIntOrNull() ?: 1
        return "${m.groupValues[1]}${generation + 1}"
    }
}
