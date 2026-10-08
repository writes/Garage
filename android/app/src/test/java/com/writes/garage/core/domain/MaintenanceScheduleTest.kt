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

    // ---- T12 edge cases

    @Test
    fun brakeInspectionDueByTimeAloneWhenNoMilesWereRecorded() {
        val brake = entry("b", EntryType.BRAKE, daysAgo = 400, odo = 0)
        val due = MaintenanceSchedule.status(MaintenanceItem.BRAKE_INSPECTION, listOf(brake), 50_000, NOW)
        assertNull(due.milesPastDue)
        assertEquals(MaintenanceStatus.OVERDUE, due.status)
        val soon = MaintenanceSchedule.status(MaintenanceItem.BRAKE_INSPECTION, listOf(entry("b2", EntryType.BRAKE, daysAgo = 345, odo = 0)), 50_000, NOW)
        assertEquals(MaintenanceStatus.DUE_SOON, soon.status)
        val fine = MaintenanceSchedule.status(MaintenanceItem.BRAKE_INSPECTION, listOf(entry("b3", EntryType.BRAKE, daysAgo = 30, odo = 0)), 50_000, NOW)
        assertEquals(MaintenanceStatus.UP_TO_DATE, fine.status)
    }

    @Test
    fun wheelAlignmentUsesTwelveMonthsAndTwelveThousandMiles() {
        val a = entry("a", EntryType.ALIGNMENT, daysAgo = 20, odo = 30_000)
        assertEquals(MaintenanceStatus.OVERDUE, MaintenanceSchedule.status(MaintenanceItem.WHEEL_ALIGNMENT, listOf(a), 42_000, NOW).status)
        assertEquals(MaintenanceStatus.DUE_SOON, MaintenanceSchedule.status(MaintenanceItem.WHEEL_ALIGNMENT, listOf(a), 41_000, NOW).status)
        assertEquals(MaintenanceStatus.UP_TO_DATE, MaintenanceSchedule.status(MaintenanceItem.WHEEL_ALIGNMENT, listOf(a), 35_000, NOW).status)
    }

    @Test
    fun nullOdometerFallsBackToTheTimeAxisOnly() {
        val sevenMonths = MaintenanceSchedule.status(MaintenanceItem.OIL_AND_FILTER, listOf(oil(215, 40_000)), null, NOW)
        assertNull(sevenMonths.milesPastDue)
        assertEquals(MaintenanceStatus.OVERDUE, sevenMonths.status)
        // 170 days ago: due 2026-06-13, 12 days away, inside the 18.3-day warning window.
        assertEquals(MaintenanceStatus.DUE_SOON, MaintenanceSchedule.status(MaintenanceItem.OIL_AND_FILTER, listOf(oil(170, 40_000)), null, NOW).status)
        assertEquals(MaintenanceStatus.UP_TO_DATE, MaintenanceSchedule.status(MaintenanceItem.OIL_AND_FILTER, listOf(oil(60, 40_000)), null, NOW).status)
    }

    @Test
    fun theMostRecentServiceIsTheBaseline() {
        val old = oil(400, 30_000)
        val recent = oil(20, 44_000)
        for (list in listOf(listOf(old, recent), listOf(recent, old))) {
            val due = MaintenanceSchedule.status(MaintenanceItem.OIL_AND_FILTER, list, 45_000, NOW)
            assertEquals(recent.entryDate, due.lastServicedAt)
            assertEquals(-4_000, due.milesPastDue)
            assertEquals(MaintenanceStatus.UP_TO_DATE, due.status)
        }
    }

    @Test
    fun unrelatedEntriesAndTireRemovalDoNotClearTheRotation() {
        val removed = entry("t", EntryType.TIRE, daysAgo = 5, odo = 50_000, details = mapOf("actionType" to "removed"))
        val others = listOf(
            entry("f", EntryType.FUEL, daysAgo = 1, odo = 50_100), entry("r", EntryType.REPAIR, daysAgo = 2, odo = 50_100),
            removed,
        )
        assertEquals(MaintenanceStatus.NEVER_LOGGED, MaintenanceSchedule.status(MaintenanceItem.TIRE_ROTATION, others, 50_200, NOW).status)
        // And none of them clear oil either.
        assertEquals(MaintenanceStatus.NEVER_LOGGED, MaintenanceSchedule.status(MaintenanceItem.OIL_AND_FILTER, others, 50_200, NOW).status)
    }

    @Test
    fun attentionOrderIsOverdueThenDueSoonThenNeverLoggedWithNameTieBreak() {
        val entries = listOf(
            oil(300, 40_000), // OVERDUE
            entry("b", EntryType.BRAKE, daysAgo = 345, odo = 0), // DUE_SOON by time
            // tire rotation + alignment never logged
        )
        val order = MaintenanceSchedule.attentionNeeded(entries, 41_000, NOW)
        assertEquals(
            listOf(
                MaintenanceItem.OIL_AND_FILTER to MaintenanceStatus.OVERDUE,
                MaintenanceItem.BRAKE_INSPECTION to MaintenanceStatus.DUE_SOON,
                MaintenanceItem.TIRE_ROTATION to MaintenanceStatus.NEVER_LOGGED,
                MaintenanceItem.WHEEL_ALIGNMENT to MaintenanceStatus.NEVER_LOGGED,
            ),
            order.map { it.item to it.status },
        )
        // Two overdue items tie-break by name.
        val twoOverdue = listOf(oil(300, 40_000), entry("t", EntryType.TIRE, daysAgo = 300, odo = 40_000, details = mapOf("actionType" to "rotation")))
        assertEquals(
            listOf(MaintenanceItem.OIL_AND_FILTER, MaintenanceItem.TIRE_ROTATION),
            MaintenanceSchedule.attentionNeeded(twoOverdue, 50_000, NOW).filter { it.status == MaintenanceStatus.OVERDUE }.map { it.item },
        )
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

    // ---- successor contract (iOS ReminderService.scheduleSuccessorIfRepeating parity)

    private val utc = java.time.ZoneOffset.UTC

    private fun repeating(
        due: String? = "2026-06-11T09:00:00Z", months: Int? = 6, miles: Int? = 5_000, dueMileage: Int? = 40_000,
    ) = Reminder(
        id = "r1", vehicleId = "v1", title = "Oil", dueDate = due?.let { Instant.parse(it) },
        dueMileage = dueMileage, repeatIntervalMonths = months, repeatIntervalMiles = miles,
    )

    @Test
    fun aRepeatingReminderWithNoDueDateYieldsNoSuccessor() {
        assertNull(ReminderSchedule.nextOccurrence(repeating(due = null), NOW, utc))
    }

    @Test
    fun milesOnlyOrNoRepeatYieldsNoSuccessor() {
        // iOS requires BOTH a due date and a months interval; a miles-only repeat is explicitly not a successor.
        assertNull(ReminderSchedule.nextOccurrence(repeating(months = null, miles = 5_000), NOW, utc))
        assertNull(ReminderSchedule.nextOccurrence(repeating(months = 0, miles = 0), NOW, utc))
        assertNull(ReminderSchedule.nextOccurrence(repeating(months = null, miles = null), NOW, utc))
    }

    @Test
    fun dueInTenDaysCompletedTodayRollsFromTheOriginalDueDate() {
        val r = repeating(due = NOW.plusSeconds(10 * 86_400).toString())
        val next = ReminderSchedule.nextOccurrence(r, NOW, utc)!!
        val expected = r.dueDate!!.atZone(utc).plusMonths(6).toInstant()
        assertEquals(expected, next.dueDate)
    }

    @Test
    fun aLongOverdueCompletionRollsFromNowNotFromTheStaleDate() {
        val r = repeating(due = "2024-01-01T09:00:00Z", months = 6)
        val next = ReminderSchedule.nextOccurrence(r, NOW, utc)!!
        assertEquals(NOW.atZone(utc).plusMonths(6).toInstant(), next.dueDate)
    }

    @Test
    fun successorMileageAdvancesFromTheReminderNotTheOdometer() {
        val next = ReminderSchedule.nextOccurrence(repeating(dueMileage = 40_000, miles = 5_000), NOW, utc)!!
        assertEquals(45_000, next.dueMileage)
        // No miles interval: the mileage is carried over unchanged (iOS copies the reminder).
        assertEquals(40_000, ReminderSchedule.nextOccurrence(repeating(dueMileage = 40_000, miles = null), NOW, utc)!!.dueMileage)
        // No due mileage: stays unset even with an interval.
        assertNull(ReminderSchedule.nextOccurrence(repeating(dueMileage = null, miles = 5_000), NOW, utc)!!.dueMileage)
    }

    @Test
    fun monthEndClampsAugust31PlusSixMonthsToFebruary28() {
        val r = repeating(due = "2027-08-31T09:00:00Z", months = 6)
        val next = ReminderSchedule.nextOccurrence(r, Instant.parse("2027-08-01T00:00:00Z"), utc)!!
        assertEquals(Instant.parse("2028-02-29T09:00:00Z"), next.dueDate) // 2028 is a leap year
        val r2 = repeating(due = "2026-08-31T09:00:00Z", months = 6)
        assertEquals(Instant.parse("2027-02-28T09:00:00Z"), ReminderSchedule.nextOccurrence(r2, Instant.parse("2026-08-01T00:00:00Z"), utc)!!.dueDate)
    }

    @Test
    fun successorIdsStayBoundedAcrossGenerations() {
        assertEquals("r1-next", ReminderSchedule.successorId("r1"))
        assertEquals("r1-next2", ReminderSchedule.successorId("r1-next"))
        assertEquals("r1-next3", ReminderSchedule.successorId("r1-next2"))
        assertEquals("r1-next11", ReminderSchedule.successorId("r1-next10"))
    }

    @Test
    fun successorKeepsTheDefinitionButIsFreshAndHasADeterministicId() {
        val r = repeating().copy(notes = "n", entryType = EntryType.OIL_CHANGE, createdAt = NOW, completedAt = NOW)
        val next = ReminderSchedule.nextOccurrence(r, NOW, utc)!!
        assertEquals("r1-next", next.id)
        assertEquals(ReminderSchedule.successorId("r1"), next.id)
        assertEquals(listOf("Oil", "n", EntryType.OIL_CHANGE, "v1"), listOf(next.title, next.notes, next.entryType, next.vehicleId))
        assertEquals(6, next.repeatIntervalMonths)
        assertEquals(5_000, next.repeatIntervalMiles)
        assertNull(next.completedAt)
        assertNull(next.createdAt)
    }

    @Test
    fun rollsByCalendarMonthsInTheUsersZoneAcrossDst() {
        val la = java.time.ZoneId.of("America/Los_Angeles")
        val due = java.time.LocalDate.of(2026, 2, 15).atTime(9, 0).atZone(la).toInstant() // PST
        val next = ReminderSchedule.nextOccurrence(repeating(due = due.toString(), months = 6), Instant.parse("2026-02-01T00:00:00Z"), la)!!
        // 09:00 local stays 09:00 local in August (PDT), i.e. 16:00Z rather than 17:00Z.
        assertEquals(java.time.LocalDate.of(2026, 8, 15).atTime(9, 0).atZone(la).toInstant(), next.dueDate)
        assertEquals(Instant.parse("2026-08-15T16:00:00Z"), next.dueDate)
    }
}
