package com.writes.garage.core.notify

import com.writes.garage.TestFixtures
import com.writes.garage.core.data.ReminderRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.model.Reminder
import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class ReminderAlarmSyncTest {
    private val now = Instant.parse("2026-06-01T12:00:00Z")

    private class FakeVehicles(initial: List<Vehicle>, private val failFirst: Boolean = false) : VehicleRepository {
        val vehicles = MutableStateFlow(initial)
        var subscriptions = 0
        override fun observeVehicles(): Flow<List<Vehicle>> = flow {
            subscriptions++
            if (failFirst && subscriptions == 1) throw RuntimeException("listener died")
            emitAll(vehicles)
        }
        override fun observeVehicle(vehicleId: String): Flow<Vehicle?> = throw UnsupportedOperationException()
        override val activeVehicleId: StateFlow<String?> = MutableStateFlow(null)
        override suspend fun setActiveVehicle(vehicleId: String) = Unit
        override suspend fun addVehicle(vehicle: Vehicle): Vehicle = vehicle
        override suspend fun updateVehicle(vehicle: Vehicle) = Unit
        override suspend fun deleteVehicle(vehicleId: String) = Unit
    }

    private class FakeReminders : ReminderRepository {
        val byVehicle = mutableMapOf<String, MutableStateFlow<List<Reminder>>>()
        val failing = mutableSetOf<String>()
        fun flowFor(id: String) = byVehicle.getOrPut(id) { MutableStateFlow(emptyList()) }
        override fun observeReminders(vehicleId: String): Flow<List<Reminder>> =
            if (vehicleId in failing) flow { throw RuntimeException("permission denied") } else flowFor(vehicleId)
        override suspend fun addReminder(reminder: Reminder) = reminder
        override suspend fun updateReminder(reminder: Reminder) = Unit
        override suspend fun completeReminder(vehicleId: String, reminderId: String) = Unit
        override suspend fun deleteReminder(vehicleId: String, reminderId: String) = Unit
    }

    private fun reminder(id: String, vehicle: String = "v1", due: String = "2026-06-20T12:00:00Z") =
        Reminder(id = id, vehicleId = vehicle, title = "Oil change", dueDate = Instant.parse(due))

    private val plans = mutableListOf<List<PlannedAlarm>>()
    private val last get() = plans.last()
    private fun keys(plan: List<PlannedAlarm>) = plan.map { it.key }.sorted()

    @Test
    fun toggleOffClearsThePlanAndOnRestoresIt() = runTest {
        val vehicles = FakeVehicles(listOf(TestFixtures.vehicle()))
        val reminders = FakeReminders().apply { flowFor("v1").value = listOf(reminder("r1")) }
        val enabled = InMemoryNotificationSettings(initial = false)
        ReminderAlarmSync({ plans += it }, vehicles, reminders, enabled) { now }.start(backgroundScope)
        runCurrent()
        assertTrue("disabled means an empty plan is pushed (alarms cancelled)", plans.isNotEmpty() && last.isEmpty())

        enabled.setEnabled(true)
        runCurrent()
        assertEquals(listOf("r1:0", "r1:3"), keys(last))

        enabled.setEnabled(false)
        runCurrent()
        assertTrue(last.isEmpty())
    }

    @Test
    fun editingAReminderReplansWithoutToggling() = runTest {
        val vehicles = FakeVehicles(listOf(TestFixtures.vehicle()))
        val reminders = FakeReminders().apply { flowFor("v1").value = listOf(reminder("r1")) }
        ReminderAlarmSync({ plans += it }, vehicles, reminders, InMemoryNotificationSettings(true)) { now }.start(backgroundScope)
        runCurrent()
        reminders.flowFor("v1").value = listOf(reminder("r1"), reminder("r2"))
        runCurrent()
        assertEquals(listOf("r1:0", "r1:3", "r2:0", "r2:3"), keys(last))
        reminders.flowFor("v1").value = listOf(reminder("r2"))
        runCurrent()
        assertEquals(listOf("r2:0", "r2:3"), keys(last))
    }

    @Test
    fun aVehicleAddedMidStreamIsPickedUp() = runTest {
        val v1 = TestFixtures.vehicle("v1")
        val v2 = TestFixtures.vehicle("v2")
        val vehicles = FakeVehicles(listOf(v1))
        val reminders = FakeReminders().apply {
            flowFor("v1").value = listOf(reminder("a", "v1"))
            flowFor("v2").value = listOf(reminder("b", "v2"))
        }
        ReminderAlarmSync({ plans += it }, vehicles, reminders, InMemoryNotificationSettings(true)) { now }.start(backgroundScope)
        runCurrent()
        assertEquals(listOf("a:0", "a:3"), keys(last))
        vehicles.vehicles.value = listOf(v1, v2)
        runCurrent()
        assertEquals(listOf("a:0", "a:3", "b:0", "b:3"), keys(last))
        // And removing a vehicle drops its alarms.
        vehicles.vehicles.value = listOf(v2)
        runCurrent()
        assertEquals(listOf("b:0", "b:3"), keys(last))
    }

    @Test
    fun noVehiclesMeansAnEmptyPlan() = runTest {
        val vehicles = FakeVehicles(emptyList())
        ReminderAlarmSync({ plans += it }, vehicles, FakeReminders(), InMemoryNotificationSettings(true)) { now }.start(backgroundScope)
        runCurrent()
        assertTrue(plans.isNotEmpty() && last.isEmpty())
    }

    @Test
    fun aListenerErrorClearsThePlanThenResubscribesAndReplans() = runTest {
        val vehicles = FakeVehicles(listOf(TestFixtures.vehicle()), failFirst = true)
        val reminders = FakeReminders().apply { flowFor("v1").value = listOf(reminder("r1")) }
        ReminderAlarmSync({ plans += it }, vehicles, reminders, InMemoryNotificationSettings(true)) { now }.start(backgroundScope)
        runCurrent()
        assertEquals("one failed subscription so far", 1, vehicles.subscriptions)
        assertTrue("plan cleared on the error", last.isEmpty())
        advanceTimeBy(1_500)
        runCurrent()
        assertEquals("resubscribed after the backoff", 2, vehicles.subscriptions)
        assertEquals(listOf("r1:0", "r1:3"), keys(last))
    }

    @Test
    fun aFailingReminderListenerOnlyLosesThatVehicle() = runTest {
        val vehicles = FakeVehicles(listOf(TestFixtures.vehicle("v1"), TestFixtures.vehicle("v2")))
        val reminders = FakeReminders().apply {
            flowFor("v1").value = listOf(reminder("a", "v1"))
            flowFor("v2").value = listOf(reminder("b", "v2"))
            failing += "v1"
        }
        ReminderAlarmSync({ plans += it }, vehicles, reminders, InMemoryNotificationSettings(true)) { now }.start(backgroundScope)
        runCurrent()
        assertEquals(listOf("b:0", "b:3"), keys(last))
        assertEquals("the failure must not trigger a full resubscribe", 1, vehicles.subscriptions)
    }

    @Test
    fun aSchedulerCrashDoesNotEndSyncing() = runTest {
        val vehicles = FakeVehicles(listOf(TestFixtures.vehicle()))
        val reminders = FakeReminders().apply { flowFor("v1").value = listOf(reminder("r1")) }
        var calls = 0
        ReminderAlarmSync(
            { plan -> calls++; if (calls == 1) throw IllegalStateException("AlarmManager unavailable"); plans += plan },
            vehicles, reminders, InMemoryNotificationSettings(true),
        ) { now }.start(backgroundScope)
        runCurrent()
        reminders.flowFor("v1").value = listOf(reminder("r1"), reminder("r2"))
        runCurrent()
        assertEquals(listOf("r1:0", "r1:3", "r2:0", "r2:3"), keys(last))
    }
}
