package com.writes.garage.core.notify

import com.writes.garage.TestFixtures
import com.writes.garage.core.model.Reminder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

class ReminderPlannerTest {
    private val now = Instant.parse("2026-06-01T12:00:00Z")
    private val v = TestFixtures.vehicle()

    private fun reminder(id: String, due: String?, done: Boolean = false, vehicle: String = "v1") = Reminder(
        id = id, vehicleId = vehicle, title = "Oil change", dueDate = due?.let { Instant.parse(it) },
        completedAt = if (done) now else null,
    )

    @Test
    fun schedulesLeadAndDayOfAtNineLocal() {
        val plan = ReminderPlanner.plan(listOf(v), listOf(reminder("r1", "2026-06-20T00:00:00Z")), now, ZoneOffset.UTC)
        assertEquals(listOf("r1:3", "r1:0"), plan.map { it.key })
        assertEquals(Instant.parse("2026-06-17T09:00:00Z"), plan[0].triggerAt)
        assertEquals(Instant.parse("2026-06-20T09:00:00Z"), plan[1].triggerAt)
        assertEquals("Daily: due in 3 days", plan[0].text)
        assertEquals("Daily: due today", plan[1].text)
    }

    @Test
    fun skipsPastCompletedMileageOnlyAndUnknownVehicle() {
        val plan = ReminderPlanner.plan(
            listOf(v),
            listOf(
                reminder("past", "2026-05-01T00:00:00Z"),
                reminder("done", "2026-07-01T00:00:00Z", done = true),
                reminder("miles", null),
                reminder("ghost", "2026-07-01T00:00:00Z", vehicle = "other"),
            ),
            now, ZoneOffset.UTC,
        )
        assertTrue(plan.isEmpty())
    }

    @Test
    fun dueSoonDropsTheAlreadyPassedLeadButKeepsDayOf() {
        val plan = ReminderPlanner.plan(listOf(v), listOf(reminder("r", "2026-06-02T00:00:00Z")), now, ZoneOffset.UTC)
        assertEquals(listOf("r:0"), plan.map { it.key })
    }

    @Test
    fun capsAndSortsBySoonest() {
        val many = (1..60).map { reminder("r$it", "2026-08-%02dT00:00:00Z".format((it % 28) + 1)) }
        val plan = ReminderPlanner.plan(listOf(v), many, now, ZoneOffset.UTC)
        assertEquals(ReminderPlanner.MAX_ALARMS, plan.size)
        assertEquals(plan.sortedBy { it.triggerAt }, plan)
    }

    @Test
    fun persistedPlanRoundTrips() {
        val plan = listOf(
            PlannedAlarm("r1:0", "r1", Instant.parse("2026-06-20T09:00:00Z"), "Oil\tchange", "Daily: due today"),
            PlannedAlarm("r2:3", "r2", Instant.parse("2026-06-21T09:00:00Z"), "Tires\nrotate", "x"),
        )
        val back = ReminderAlarms.load(ReminderAlarms.encode(plan))
        assertEquals(listOf("r1:0", "r2:3"), back.map { it.key })
        assertEquals("Oil change", back[0].title)
        assertEquals("Tires rotate", back[1].title)
        assertEquals(plan[0].triggerAt, back[0].triggerAt)
        assertTrue(ReminderAlarms.load(null).isEmpty())
    }

    @Test
    fun capKeepsTheSoonest48NotJustAnySorted48() {
        // 60 reminders due on distinct days; each yields a lead and a day-of alarm (120 candidates).
        val many = (1..60).map { reminder("r$it", Instant.parse("2026-07-01T00:00:00Z").plusSeconds(it * 86_400L).toString()) }
        val all = ReminderPlanner.plan(listOf(v), many, now, ZoneOffset.UTC)
        val uncapped = many.flatMap { r ->
            ReminderPlanner.LEAD_DAYS.map { lead ->
                r.dueDate!!.atZone(ZoneOffset.UTC).toLocalDate().minusDays(lead).atTime(9, 0).atZone(ZoneOffset.UTC).toInstant()
            }
        }.sorted()
        assertEquals(uncapped.take(ReminderPlanner.MAX_ALARMS), all.map { it.triggerAt })
    }

    @Test
    fun aTriggerExactlyAtNowIsDropped() {
        // Lead 0 fires at 09:00 on the due day; make "now" exactly that instant.
        val due = "2026-06-10T00:00:00Z"
        val atNine = Instant.parse("2026-06-10T09:00:00Z")
        assertTrue(ReminderPlanner.plan(listOf(v), listOf(reminder("r", due)), atNine, ZoneOffset.UTC).isEmpty())
        val justBefore = ReminderPlanner.plan(listOf(v), listOf(reminder("r", due)), atNine.minusSeconds(1), ZoneOffset.UTC)
        assertEquals(listOf("r:0"), justBefore.map { it.key })
    }

    @Test
    fun nineLocalHoldsAcrossADstChangeInLosAngeles() {
        val la = java.time.ZoneId.of("America/Los_Angeles")
        // US DST began on 2026-03-08. Due on 03-09 (lead 3 lands on 03-06, day-of after the change).
        val due = java.time.LocalDate.of(2026, 3, 9).atStartOfDay(la).toInstant()
        val plan = ReminderPlanner.plan(
            listOf(v), listOf(Reminder("r", "v1", "Brakes", dueDate = due)), Instant.parse("2026-03-01T00:00:00Z"), la,
        )
        assertEquals(2, plan.size)
        for (a in plan) assertEquals(9, a.triggerAt.atZone(la).hour)
        // 09:00 PST (UTC-8) before the change, 09:00 PDT (UTC-7) after.
        assertEquals(Instant.parse("2026-03-06T17:00:00Z"), plan[0].triggerAt)
        assertEquals(Instant.parse("2026-03-09T16:00:00Z"), plan[1].triggerAt)
    }

    @Test
    fun aDueDayStoredAsLocalMidnightKeepsItsCalendarDayInNegativeAndPositiveOffsets() {
        for (zone in listOf(java.time.ZoneId.of("America/Los_Angeles"), java.time.ZoneId.of("Pacific/Auckland"))) {
            val due = java.time.LocalDate.of(2026, 6, 20).atStartOfDay(zone).toInstant()
            val plan = ReminderPlanner.plan(listOf(v), listOf(Reminder("r", "v1", "t", dueDate = due)), now, zone)
            val dayOf = plan.first { it.key == "r:0" }.triggerAt.atZone(zone)
            assertEquals(zone.id, java.time.LocalDate.of(2026, 6, 20), dayOf.toLocalDate())
            assertEquals(9, dayOf.hour)
        }
    }

    @Test
    fun isFutureIsStrict() {
        val a = PlannedAlarm("k", "r", now.plusSeconds(1), "t", "x")
        assertTrue(ReminderPlanner.isFuture(a, now))
        assertTrue(!ReminderPlanner.isFuture(a.copy(triggerAt = now), now))
        assertTrue(!ReminderPlanner.isFuture(a.copy(triggerAt = now.minusSeconds(1)), now))
    }

    @Test
    fun carriageReturnsInTitlesDoNotCorruptThePersistedPlan() {
        val plan = listOf(
            PlannedAlarm("r1:0", "r1", Instant.parse("2026-06-20T09:00:00Z"), "Oil\r\nchange\rnow", "Daily: due today"),
            PlannedAlarm("r2:0", "r2", Instant.parse("2026-06-21T09:00:00Z"), "Tires", "x"),
        )
        val back = ReminderAlarms.load(ReminderAlarms.encode(plan))
        assertEquals(listOf("r1:0", "r2:0"), back.map { it.key })
        assertEquals("Oil  change now", back[0].title)
        assertEquals("Daily: due today", back[0].text)
    }

    @Test
    fun malformedPersistedLinesAreSkipped() {
        val raw = listOf(
            "k1\tr1\t1781000000000\tTitle\tText",
            "too\tfew\tfields",
            "k2\tr2\tnot-a-number\tTitle\tText",
            "",
            "k3\tr3\t1781000000001\tTitle\tText\textra",
        ).joinToString("\n")
        val back = ReminderAlarms.load(raw)
        assertEquals(listOf("k1", "k3"), back.map { it.key })
        assertTrue(ReminderAlarms.load("").isEmpty())
    }
}
