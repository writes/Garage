package com.writes.garage.core.domain

import com.writes.garage.TestFixtures.NOW
import com.writes.garage.TestFixtures.entry
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Reminder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class MaintenanceScheduleTest {
    private fun oil(daysAgo: Long, odo: Int) = entry("oil$daysAgo", EntryType.OIL_CHANGE, daysAgo = daysAgo, odo = odo)

    @Test
    fun neverLoggedIsNotOverdue() {
        val due = MaintenanceSchedule.status(MaintenanceItem.OIL_AND_FILTER, listOf(entry("x", EntryType.FUEL)), 50_000, NOW)
        assertEquals(MaintenanceStatus.NEVER_LOGGED, due.status)
        assertNull(due.lastServicedAt)
    }

    @Test
    fun overdueOnMilesAlone() {
        val due = MaintenanceSchedule.status(MaintenanceItem.OIL_AND_FILTER, listOf(oil(30, 40_000)), 45_500, NOW)
        assertEquals(MaintenanceStatus.OVERDUE, due.status)
        assertEquals(500, due.milesPastDue)
    }

    @Test
    fun overdueOnTimeAloneEvenWithFewMiles() {
        val due = MaintenanceSchedule.status(MaintenanceItem.OIL_AND_FILTER, listOf(oil(200, 40_000)), 40_100, NOW)
        assertEquals(MaintenanceStatus.OVERDUE, due.status)
    }

    @Test
    fun dueSoonInsideLastTenthOfInterval() {
        // 4,600 of 5,000 miles used -> 400 left, warning window is 500
        val due = MaintenanceSchedule.status(MaintenanceItem.OIL_AND_FILTER, listOf(oil(10, 40_000)), 44_600, NOW)
        assertEquals(MaintenanceStatus.DUE_SOON, due.status)
        assertEquals(-400, due.milesPastDue)
    }

    @Test
    fun upToDateWhenFarFromBothLimits() {
        val due = MaintenanceSchedule.status(MaintenanceItem.OIL_AND_FILTER, listOf(oil(10, 40_000)), 41_000, NOW)
        assertEquals(MaintenanceStatus.UP_TO_DATE, due.status)
    }

    @Test
    fun zeroOdometerMeansNotRecordedNotMileZero() {
        val due = MaintenanceSchedule.status(MaintenanceItem.OIL_AND_FILTER, listOf(oil(10, 0)), 80_000, NOW)
        assertNull(due.milesPastDue)
        assertEquals(MaintenanceStatus.UP_TO_DATE, due.status)
    }

    @Test
    fun tireRotationClearingRules() {
        val newInstall = entry("t1", EntryType.TIRE, daysAgo = 5, odo = 50_000, details = mapOf("actionType" to "new_install"))
        val treadReading = entry("t2", EntryType.TIRE, daysAgo = 1, odo = 50_100, details = mapOf("actionType" to "tread_depth_reading"))
        val legacyTire = entry("t3", EntryType.TIRE, daysAgo = 2, odo = 50_050)
        val maintRotate = entry("m1", EntryType.MAINTENANCE, daysAgo = 3, odo = 50_020, details = mapOf("item" to "rotate_balance_tires"))
        val maintOther = entry("m2", EntryType.MAINTENANCE, daysAgo = 0, odo = 50_200, details = mapOf("item" to "spark_plugs"))

        fun last(vararg e: com.writes.garage.core.model.Entry) =
            MaintenanceSchedule.status(MaintenanceItem.TIRE_ROTATION, e.toList(), 50_300, NOW).lastServicedAt
        assertEquals(newInstall.entryDate, last(newInstall, treadReading))
        assertEquals(legacyTire.entryDate, last(legacyTire, treadReading)) // legacy fails OPEN, measurement excluded
        assertEquals(maintRotate.entryDate, last(maintRotate, maintOther)) // maintenance fails CLOSED
        assertNull(last(maintOther, treadReading))
    }

    @Test
    fun attentionNeededIsEmptyWithNoHistoryAndSortedWorstFirst() {
        assertTrue(MaintenanceSchedule.attentionNeeded(emptyList(), 50_000, NOW).isEmpty())
        val entries = listOf(oil(300, 40_000), entry("b", EntryType.BRAKE, daysAgo = 5, odo = 49_900))
        val result = MaintenanceSchedule.attentionNeeded(entries, 50_000, NOW)
        assertEquals(MaintenanceItem.OIL_AND_FILTER, result.first().item)
        assertEquals(MaintenanceStatus.OVERDUE, result.first().status)
        assertTrue(result.none { it.status == MaintenanceStatus.UP_TO_DATE })
    }

    // ---- reminders ----

    private fun reminder(due: Instant? = null, miles: Int? = null, completed: Instant? = null) =
        Reminder(id = "r", vehicleId = "v1", title = "t", dueDate = due, dueMileage = miles, completedAt = completed)

    @Test
    fun reminderStatuses() {
        assertEquals(ReminderStatus.COMPLETED, ReminderSchedule.status(reminder(completed = NOW), null, NOW))
        assertEquals(ReminderStatus.NO_SCHEDULE, ReminderSchedule.status(reminder(), null, NOW))
        assertEquals(ReminderStatus.OVERDUE, ReminderSchedule.status(reminder(due = NOW.minusSeconds(60)), null, NOW))
        assertEquals(ReminderStatus.OVERDUE, ReminderSchedule.status(reminder(miles = 50_000), 50_001, NOW))
        assertEquals(ReminderStatus.DUE_SOON, ReminderSchedule.status(reminder(due = NOW.plusSeconds(5 * 86_400)), null, NOW))
        assertEquals(ReminderStatus.DUE_SOON, ReminderSchedule.status(reminder(miles = 50_300), 50_000, NOW))
        assertEquals(ReminderStatus.UPCOMING, ReminderSchedule.status(reminder(due = NOW.plusSeconds(90 * 86_400)), null, NOW))
        assertEquals(ReminderStatus.UPCOMING, ReminderSchedule.status(reminder(miles = 60_000), 0, NOW)) // unrecorded odometer
    }

    @Test
    fun repeatingReminderSchedulesTheNextOccurrence() {
        val r = Reminder(id = "r1", vehicleId = "v1", title = "Oil", repeatIntervalMonths = 6, repeatIntervalMiles = 5_000)
        val next = ReminderSchedule.nextOccurrence(r, Instant.parse("2026-01-31T00:00:00Z"), 40_000)!!
        assertEquals("", next.id)
        assertEquals(Instant.parse("2026-07-31T00:00:00Z"), next.dueDate)
        assertEquals(45_000, next.dueMileage)
        assertNull(next.completedAt)
        assertNull(ReminderSchedule.nextOccurrence(r.copy(repeatIntervalMonths = null, repeatIntervalMiles = 0), NOW, 1))
    }
}
