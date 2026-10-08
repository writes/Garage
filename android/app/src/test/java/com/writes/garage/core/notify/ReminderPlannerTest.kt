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
}
