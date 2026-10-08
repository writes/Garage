package com.writes.garage.feature

import com.writes.garage.core.data.demo.DemoAuthRepository
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.domain.ReminderStatus
import com.writes.garage.feature.auth.AuthViewModel
import com.writes.garage.feature.dashboard.DashboardViewModel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class DashboardAuthTest {
    @get:Rule val main = MainDispatcherRule()

    private fun dashboard(env: DemoEnv) = DashboardViewModel(env.vehicles, env.entries, env.reminders) { env.now }

    @Test
    fun showsActiveVehicleRecentEntriesAndRankedReminders() = runTest {
        val env = DemoEnv()
        val vm = dashboard(env)
        keepHot(vm.state)
        vm.selectVehicle(SeedData.SQ5_ID)
        val s = vm.state.value
        assertEquals("Daily SQ5", s.activeVehicle?.displayName)
        assertEquals(82_440, s.activeVehicle?.currentOdometer)
        assertTrue(s.recentEntries.size in 1..10)
        assertEquals(s.recentEntries.sortedByDescending { it.entryDate }, s.recentEntries)
        // Overdue (tire rotation, due 5 days ago) sorts ahead of the upcoming oil change; completed ones are hidden.
        assertEquals(listOf("Rotate tires", "Oil change"), s.reminders.map { it.reminder.title })
        assertEquals(ReminderStatus.OVERDUE, s.reminders.first().status)
        assertEquals(1, s.overdueCount)
        assertEquals(2, s.vehicles.size)
        assertTrue(s.attention.isNotEmpty())
    }

    @Test
    fun completingARepeatingReminderSchedulesTheNextOne() = runTest {
        val env = DemoEnv()
        val vm = dashboard(env)
        keepHot(vm.state)
        vm.selectVehicle(SeedData.SQ5_ID)
        val oil = vm.state.value.reminders.first { it.reminder.title == "Oil change" }.reminder
        vm.completeReminder(oil)
        val titles = vm.state.value.reminders.map { it.reminder.title }
        assertEquals(1, titles.count { it == "Oil change" }) // old one done, successor created
        val next = vm.state.value.reminders.first { it.reminder.title == "Oil change" }.reminder
        assertTrue(next.id != oil.id)
        assertTrue(next.dueDate!! > oil.dueDate!!)
        assertEquals(82_440 + 10_000, next.dueMileage)
        assertNotNull(env.store.reminders.value.first { it.id == oil.id }.completedAt)
    }

    @Test
    fun emptyGarageShowsNoVehicle() = runTest {
        val env = DemoEnv()
        env.store.vehicles.value = emptyList()
        val vm = dashboard(env)
        keepHot(vm.state)
        assertNull(vm.state.value.activeVehicle)
        assertFalse(vm.state.value.loading)
    }

    @Test
    fun demoSignInAndOutGateTheApp() = runTest {
        val env = DemoEnv()
        val auth = DemoAuthRepository(env.store)
        val vm = AuthViewModel(auth, isDemo = true)
        assertTrue(vm.state.value.isDemo)
        assertFalse(vm.state.value.googleAvailable)
        assertNull(auth.currentUser.value)
        vm.continueInDemo()
        assertTrue(auth.currentUser.value!!.isDemo)
        assertFalse(vm.state.value.busy)
        auth.signOut()
        assertNull(auth.currentUser.first())
    }
}
