package com.writes.garage.core.notify

import android.app.AlarmManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.time.Instant

@RunWith(RobolectricTestRunner::class)
class ReminderAlarmsTest {
    private lateinit var context: Context
    private val now = Instant.parse("2026-06-01T12:00:00Z")

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
    }

    private fun alarm(key: String, plusHours: Long) =
        PlannedAlarm(key, key.substringBefore(':'), now.plusSeconds(plusHours * 3600), "Title $key", "Text $key")

    /** Keys of the alarms the (fake) AlarmManager currently holds, recovered from each PendingIntent's data uri. */
    private fun scheduledKeys(): List<String> {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return shadowOf(am).scheduledAlarms
            .map { android.net.Uri.decode(shadowOf(it.operation).savedIntent.data!!.lastPathSegment!!) }
            .sorted()
    }

    private fun persisted(): List<PlannedAlarm> =
        ReminderAlarms.load(context.getSharedPreferences("garage_reminder_alarms", Context.MODE_PRIVATE).getString("plan", null))

    @Test
    fun applySchedulesEveryPlannedAlarmAtItsTriggerTime() {
        ReminderAlarms.apply(context, listOf(alarm("r1:3", 24), alarm("r1:0", 72)))
        assertEquals(listOf("r1:0", "r1:3"), scheduledKeys())
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val times = shadowOf(am).scheduledAlarms.map { it.triggerAtMs }.sorted()
        assertEquals(listOf(now.plusSeconds(24 * 3600).toEpochMilli(), now.plusSeconds(72 * 3600).toEpochMilli()), times)
    }

    @Test
    fun applyingASecondPlanCancelsAlarmsThatAreNoLongerPlanned() {
        ReminderAlarms.apply(context, listOf(alarm("a:0", 1), alarm("b:0", 2), alarm("c:0", 3)))
        assertEquals(listOf("a:0", "b:0", "c:0"), scheduledKeys())
        ReminderAlarms.apply(context, listOf(alarm("b:0", 2), alarm("d:0", 4)))
        assertEquals("a and c are cancelled, b is kept (not duplicated), d is added", listOf("b:0", "d:0"), scheduledKeys())
    }

    @Test
    fun anEmptyPlanCancelsEverythingAndPersistsNothing() {
        ReminderAlarms.apply(context, listOf(alarm("a:0", 1), alarm("b:0", 2)))
        ReminderAlarms.apply(context, emptyList())
        assertTrue(scheduledKeys().isEmpty())
        assertTrue(persisted().isEmpty())
    }

    @Test
    fun reschedulingTheSameAlarmReplacesItInPlace() {
        ReminderAlarms.apply(context, listOf(alarm("a:0", 1)))
        ReminderAlarms.apply(context, listOf(alarm("a:0", 5)))
        assertEquals(listOf("a:0"), scheduledKeys())
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        assertEquals(now.plusSeconds(5 * 3600).toEpochMilli(), shadowOf(am).scheduledAlarms.single().triggerAtMs)
    }

    @Test
    fun theLatestPlanIsPersistedForBootRescheduling() {
        val plan = listOf(alarm("a:0", 1), alarm("b:0", 2))
        ReminderAlarms.apply(context, plan)
        assertEquals(plan.map { it.key }, persisted().map { it.key })
        ReminderAlarms.apply(context, listOf(plan[1]))
        assertEquals(listOf("b:0"), persisted().map { it.key })
    }

    @Test
    fun rescheduleFromStoreDropsPastTriggersAndRearmsTheRest() {
        // Simulate a reboot: the persisted plan exists but the AlarmManager is empty.
        context.getSharedPreferences("garage_reminder_alarms", Context.MODE_PRIVATE).edit()
            .putString("plan", ReminderAlarms.encode(listOf(alarm("past:0", -5), alarm("future:0", 5), alarm("now:0", 0))))
            .commit()
        assertTrue(scheduledKeys().isEmpty())
        ReminderAlarms.rescheduleFromStore(context, now)
        assertEquals("only strictly-future triggers are re-armed", listOf("future:0"), scheduledKeys())
    }

    @Test
    fun rescheduleFromStoreWithNothingPersistedIsANoop() {
        ReminderAlarms.rescheduleFromStore(context, now)
        assertTrue(scheduledKeys().isEmpty())
    }

    @Test
    fun theBootReceiverRearmsOnlyOnBootCompleted() {
        context.getSharedPreferences("garage_reminder_alarms", Context.MODE_PRIVATE).edit()
            .putString("plan", ReminderAlarms.encode(listOf(alarm("future:0", 5000)))).commit()
        val receiver = BootReceiver()
        receiver.onReceive(context, android.content.Intent("android.intent.action.TIMEZONE_CHANGED"))
        assertTrue(scheduledKeys().isEmpty())
        receiver.onReceive(context, android.content.Intent(android.content.Intent.ACTION_BOOT_COMPLETED))
        assertEquals(listOf("future:0"), scheduledKeys())
    }
}
