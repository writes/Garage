package com.writes.garage.core.domain

import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Reminder
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/** One-tap due dates (port of iOS `ReminderDueDatePreset`). */
enum class ReminderDueDatePreset(val months: Int, val label: String) {
    THREE_MONTHS(3, "In 3 months"),
    SIX_MONTHS(6, "In 6 months"),
    ONE_YEAR(12, "In 1 year");

    /** [months] out from today (a month-end source day clamps: Jan 31 + 3 months = Apr 30). */
    fun date(today: LocalDate): LocalDate = today.plusMonths(months.toLong())
}

/** Raw inputs of the reminder form. Numbers are strings until [ReminderForm.validate] says otherwise. */
data class ReminderFormState(
    val editingId: String? = null,
    val title: String = ReminderForm.DEFAULT_TITLE,
    val entryType: EntryType? = null,
    val hasDueDate: Boolean = false,
    val dueDate: LocalDate = LocalDate.now().plusDays(1),
    val dueMileage: String = "",
    val repeatMonths: String = "",
    val repeatMiles: String = "",
    val notes: String = "",
    val errors: Map<String, String> = emptyMap(),
) {
    val isEditing: Boolean get() = editingId != null
}

/** Pure form rules for the Reminders screen (port of iOS `ReminderConfigViewModel`). */
object ReminderForm {
    const val DEFAULT_TITLE = "Oil change"
    const val TITLE = "title"
    const val DUE_MILEAGE = "dueMileage"
    const val REPEAT_MONTHS = "repeatMonths"
    const val REPEAT_MILES = "repeatMiles"
    const val DUE_DATE = "dueDate"

    /** Due dates are stored at 09:00 local so the day the user picked never shifts across time zones. */
    val DUE_TIME: LocalTime = LocalTime.of(9, 0)

    fun fromReminder(r: Reminder, zone: ZoneId, today: LocalDate): ReminderFormState = ReminderFormState(
        editingId = r.id,
        title = r.title,
        entryType = r.entryType,
        hasDueDate = r.dueDate != null,
        dueDate = r.dueDate?.atZone(zone)?.toLocalDate() ?: today.plusDays(1),
        dueMileage = r.dueMileage?.toString().orEmpty(),
        repeatMonths = r.repeatIntervalMonths?.toString().orEmpty(),
        repeatMiles = r.repeatIntervalMiles?.toString().orEmpty(),
        notes = r.notes.orEmpty(),
    )

    fun validate(s: ReminderFormState, today: LocalDate): Map<String, String> {
        val errors = LinkedHashMap<String, String>()
        if (s.title.isBlank()) errors[TITLE] = "Required"
        positiveInt(s.dueMileage, DUE_MILEAGE, errors, max = 2_000_000)
        positiveInt(s.repeatMonths, REPEAT_MONTHS, errors, max = 600)
        positiveInt(s.repeatMiles, REPEAT_MILES, errors, max = 2_000_000)
        // A date that is already past can never schedule an alert; editing an existing past date is allowed unchanged.
        if (s.hasDueDate && s.dueDate.isBefore(today) && !s.isEditing) errors[DUE_DATE] = "Pick today or a future date"
        return errors
    }

    private fun positiveInt(text: String, key: String, errors: MutableMap<String, String>, max: Int) {
        val t = text.trim()
        if (t.isEmpty()) return
        val v = t.toIntOrNull()
        if (v == null || v <= 0 || v > max) errors[key] = "Whole number from 1 to $max"
    }

    /**
     * The mileage a new reminder repeats on: how far its due mileage sits ahead of the odometer today (a due mileage
     * at or below the reading, or an unrecorded odometer, yields none).
     */
    fun deriveRepeatMiles(dueMileage: Int?, currentOdometer: Int?): Int? {
        if (dueMileage == null || currentOdometer == null || currentOdometer <= 0 || dueMileage <= currentOdometer) return null
        return dueMileage - currentOdometer
    }

    /** Builds the document to save. On edit, fields the form does not show (createdAt, completedAt, isProFeature) are kept. */
    fun toReminder(s: ReminderFormState, vehicleId: String, existing: Reminder?, currentOdometer: Int?, zone: ZoneId): Reminder {
        val dueMileage = s.dueMileage.trim().toIntOrNull()?.takeIf { it > 0 }
        val explicitMiles = s.repeatMiles.trim().toIntOrNull()?.takeIf { it > 0 }
        val repeatMiles = when {
            dueMileage == null -> null
            explicitMiles != null -> explicitMiles
            existing != null -> existing.repeatIntervalMiles
            else -> deriveRepeatMiles(dueMileage, currentOdometer)
        }
        val due: Instant? = if (s.hasDueDate) s.dueDate.atTime(DUE_TIME).atZone(zone).toInstant() else null
        val base = existing ?: Reminder(id = "", vehicleId = vehicleId, title = "")
        return base.copy(
            vehicleId = vehicleId,
            title = s.title.trim(),
            entryType = s.entryType,
            dueDate = due,
            dueMileage = dueMileage,
            repeatIntervalMonths = s.repeatMonths.trim().toIntOrNull()?.takeIf { it > 0 },
            repeatIntervalMiles = repeatMiles,
            notes = s.notes.trim().ifEmpty { null },
        )
    }

    /** A mileage-only reminder cannot raise an alert (the phone cannot know when the odometer is reached). */
    fun mileageOnlyHint(s: ReminderFormState): String? =
        if (!s.hasDueDate) {
            "Mileage reminders appear in the list but can't send an alert, because your phone can't know when you reach the mileage. Add a date to get a notification."
        } else {
            null
        }
}
