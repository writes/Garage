package com.writes.garage.core.data

import com.writes.garage.core.domain.ReminderSchedule
import com.writes.garage.core.model.Reminder
import kotlinx.coroutines.flow.first
import java.time.Instant
import java.time.ZoneId

/**
 * Marks [reminder] done and, if it repeats, creates its successor.
 *
 * The successor is written FIRST under a deterministic id: if that write fails nothing was completed (the reminder is
 * still outstanding and retryable); if the completion write fails afterwards, a retry re-writes the same document
 * instead of minting a second one. A double tap therefore yields exactly one successor.
 */
suspend fun ReminderRepository.completeAndRoll(reminder: Reminder, now: Instant, zone: ZoneId = ZoneId.systemDefault()) {
    ReminderSchedule.nextOccurrence(reminder, now, zone)?.let { next ->
        // addReminder is a plain set: never rewrite a successor that already exists (it may itself be completed by now,
        // and a retry of the stale original must not resurrect it as outstanding).
        if (observeReminders(reminder.vehicleId).first().none { it.id == next.id }) addReminder(next)
    }
    completeReminder(reminder.vehicleId, reminder.id)
}
