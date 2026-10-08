package com.writes.garage.feature

import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.demo.DemoAuthRepository
import com.writes.garage.core.data.demo.DemoFunctionsGateway
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Recall
import com.writes.garage.feature.auth.AuthViewModel
import com.writes.garage.feature.dashboard.DashboardViewModel
import com.writes.garage.feature.entry.EntryEditViewModel
import com.writes.garage.feature.garage.GarageViewModel
import com.writes.garage.feature.garage.RecallsViewModel
import com.writes.garage.feature.log.EntryDetailViewModel
import com.writes.garage.feature.log.LogViewModel
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneOffset

/** T10 + the T4 reminder-completion atomicity cases: the failure branches the always-succeeding Demo repos never hit. */
class FailurePathsTest {
    @get:Rule val main = MainDispatcherRule()

    private val boom = IllegalStateException("backend unavailable")

    // ---- Garage

    @Test
    fun garageDeleteFailureSetsAnErrorThatDismissClears() = runTest {
        val env = DemoEnv()
        val vehicles = FailingVehicles(env.vehicles).apply { deleteFailure = boom }
        val vm = GarageViewModel(vehicles, env.purchases)
        keepHot(vm.state)
        vm.delete(SeedData.VIPER_ID)
        assertEquals("backend unavailable", vm.error.value)
        assertEquals("the vehicle must still be there", 2, vm.state.value.vehicles.size)
        vm.dismissError()
        assertNull(vm.error.value)
        // And a retry that works clears the old error first.
        vehicles.deleteFailure = null
        vm.delete(SeedData.VIPER_ID)
        assertNull(vm.error.value)
        assertEquals(1, vm.state.value.vehicles.size)
    }

    @Test
    fun garageListenerErrorSurfacesAndLeavesAnEmptyState() = runTest {
        val env = DemoEnv()
        val vehicles = object : com.writes.garage.core.data.VehicleRepository by env.vehicles {
            override fun observeVehicles() = kotlinx.coroutines.flow.flow<List<com.writes.garage.core.model.Vehicle>> { throw boom }
        }
        val vm = GarageViewModel(vehicles, env.purchases)
        keepHot(vm.state)
        assertEquals("backend unavailable", vm.error.value)
        assertTrue(vm.state.value.vehicles.isEmpty())
    }

    // ---- Entry detail

    private fun detail(env: DemoEnv, entries: FailingEntries, id: String = "seed-sq5-oil") =
        EntryDetailViewModel(entries, SeedData.SQ5_ID, id, io = kotlinx.coroutines.Dispatchers.Unconfined)

    @Test
    fun entryDetailDeleteFailureKeepsTheScreenAndSetsError() = runTest {
        val env = DemoEnv()
        val entries = FailingEntries(env.entries).apply { deleteFailure = boom }
        val vm = detail(env, entries)
        keepHot(vm.entry)
        var done = 0
        vm.delete { done++ }
        assertEquals("backend unavailable", vm.error.value)
        assertEquals(0, done)
        assertNotNull(env.store.entries.value.firstOrNull { it.id == "seed-sq5-oil" })
    }

    @Test
    fun entryDetailDeleteSuccessCallsOnDoneAndRemovesTheEntry() = runTest {
        val env = DemoEnv()
        val vm = detail(env, FailingEntries(env.entries))
        keepHot(vm.entry)
        var done = 0
        vm.delete { done++ }
        assertEquals(1, done)
        assertNull(vm.error.value)
        assertTrue(env.store.entries.value.none { it.id == "seed-sq5-oil" })
    }

    @Test
    fun entryDetailListenerErrorSetsErrorAndNullEntry() = runTest {
        val env = DemoEnv()
        val entries = FailingEntries(env.entries).apply { observeOneFailure = boom }
        val vm = detail(env, entries)
        keepHot(vm.entry)
        assertEquals("backend unavailable", vm.error.value)
        assertNull(vm.entry.value)
    }

    @Test
    fun entryDetailRemoveMissingAttachmentFailureSetsError() = runTest {
        val env = DemoEnv()
        env.store.entries.value = env.store.entries.value.map { if (it.id == "seed-sq5-oil") it.copy(attachmentPaths = listOf("gone.jpg")) else it }
        val entries = FailingEntries(env.entries).apply { updateFailure = boom }
        val vm = detail(env, entries)
        keepHot(vm.entry)
        vm.removeMissing("gone.jpg")
        assertEquals("backend unavailable", vm.error.value)
    }

    // ---- Auth

    @Test
    fun googleSignInFailureShowsTheErrorAndClearsBusy() = runTest {
        val env = DemoEnv()
        val auth = RecordingAuth(DemoAuthRepository(env.store), googleFailure = IllegalStateException("token rejected"))
        val vm = AuthViewModel(auth, isDemo = false)
        vm.signInWithGoogle("id-token")
        assertEquals("token rejected", vm.state.value.error)
        assertFalse(vm.state.value.busy)
        assertNull(auth.currentUser.value)
        // Retrying with a working backend clears the error.
        auth.googleFailure = null
        vm.signInWithGoogle("id-token")
        assertNull(vm.state.value.error)
        assertFalse(vm.state.value.busy)
    }

    // ---- Entry edit

    @Test
    fun entryEditSaveFailureClearsSavingAndShowsTheMessage() = runTest {
        val env = DemoEnv()
        val entries = FailingEntries(env.entries).apply { addFailure = boom }
        val vm = EntryEditViewModel(entries, env.vehicles, SeedData.SQ5_ID, null, ZoneOffset.UTC, today = { LocalDate.of(2026, 1, 1) })
        vm.setType(EntryType.OIL_CHANGE)
        vm.setOdometer("83000")
        vm.setDetail("oilBrand", "x")
        vm.setDetail("oilGrade", "y")
        vm.setDetail("quantityQuarts", "5")
        var done = false
        val before = env.store.entries.value.size
        vm.save { done = true }
        assertFalse(done)
        val s = vm.state.value
        assertFalse(s.saving)
        assertEquals("backend unavailable", s.formError)
        assertEquals(before, env.store.entries.value.size)
        assertEquals("the odometer must not move for an entry that was not saved", 82_440, env.store.vehicles.value.first { it.id == SeedData.SQ5_ID }.currentOdometer)
        // Fix the backend and save again from the same form.
        entries.addFailure = null
        vm.save { done = true }
        assertTrue(done)
        assertEquals(before + 1, env.store.entries.value.size)
    }

    // ---- Dashboard / Log listener errors

    @Test
    fun dashboardListenerErrorSetsErrorAndStopsLoading() = runTest {
        val env = DemoEnv()
        val entries = FailingEntries(env.entries).apply { observeFailure = boom }
        val vm = DashboardViewModel(env.vehicles, entries, env.reminders) { env.now }
        keepHot(vm.state)
        assertEquals("backend unavailable", vm.error.value)
        assertFalse(vm.state.value.loading)
        vm.dismissError()
        assertNull(vm.error.value)
    }

    @Test
    fun logListenerErrorSetsError() = runTest {
        val env = DemoEnv()
        val entries = FailingEntries(env.entries).apply { observeFailure = boom }
        val vm = LogViewModel(env.vehicles, entries, ZoneOffset.UTC)
        keepHot(vm.state)
        assertEquals("backend unavailable", vm.error.value)
        assertTrue(vm.state.value.entries.isEmpty())
    }

    // ---- Dashboard reminder completion (T4)

    private fun dash(env: DemoEnv, reminders: FailingReminders) =
        DashboardViewModel(env.vehicles, env.entries, reminders, zone = ZoneOffset.UTC) { env.now }

    @Test
    fun aFailedSuccessorWriteLeavesTheReminderOutstandingAndRetryable() = runTest {
        val env = DemoEnv()
        val reminders = FailingReminders(env.reminders).apply { addFailure = boom }
        val vm = dash(env, reminders)
        keepHot(vm.state)
        vm.selectVehicle(SeedData.SQ5_ID)
        val oil = vm.state.value.reminders.first { it.reminder.title == "Oil change" }.reminder
        vm.completeReminder(oil)
        assertEquals("backend unavailable", vm.error.value)
        assertEquals("the repository must not be left half-done", 0, reminders.completeCalls)
        assertTrue(env.store.reminders.value.first { it.id == oil.id }.isOutstanding)

        reminders.addFailure = null
        vm.completeReminder(oil)
        assertEquals(1, env.store.reminders.value.count { it.title == "Oil change" && it.vehicleId == SeedData.SQ5_ID && it.isOutstanding })
    }

    @Test
    fun completingTwiceCreatesExactlyOneSuccessor() = runTest {
        val env = DemoEnv()
        val reminders = FailingReminders(env.reminders)
        val vm = dash(env, reminders)
        keepHot(vm.state)
        vm.selectVehicle(SeedData.SQ5_ID)
        val oil = vm.state.value.reminders.first { it.reminder.title == "Oil change" }.reminder
        val before = env.store.reminders.value.size
        vm.completeReminder(oil)
        vm.completeReminder(oil) // a second tap on the stale row
        assertEquals(before + 1, env.store.reminders.value.size)
        val successors = env.store.reminders.value.filter { it.id.endsWith("-next") }
        assertEquals(listOf("${oil.id}-next"), successors.map { it.id })
        assertTrue(successors.single().isOutstanding)
    }

    @Test
    fun retryingAStaleOriginalNeverResurrectsACompletedSuccessor() = runTest {
        val env = DemoEnv()
        val vm = dash(env, FailingReminders(env.reminders))
        keepHot(vm.state)
        vm.selectVehicle(SeedData.SQ5_ID)
        val oil = vm.state.value.reminders.first { it.reminder.title == "Oil change" }.reminder
        vm.completeReminder(oil)
        val successor = env.store.reminders.value.first { it.id == "${oil.id}-next" }
        env.reminders.completeReminder(successor.vehicleId, successor.id) // the successor is done too
        vm.completeReminder(oil) // stale retry of the original
        assertFalse(env.store.reminders.value.first { it.id == successor.id }.isOutstanding)
    }

    @Test
    fun aFailedCompletionAfterTheSuccessorWasWrittenDoesNotDuplicateOnRetry() = runTest {
        val env = DemoEnv()
        val reminders = FailingReminders(env.reminders).apply { completeFailure = boom }
        val vm = dash(env, reminders)
        keepHot(vm.state)
        vm.selectVehicle(SeedData.SQ5_ID)
        val oil = vm.state.value.reminders.first { it.reminder.title == "Oil change" }.reminder
        vm.completeReminder(oil)
        assertEquals("backend unavailable", vm.error.value)
        reminders.completeFailure = null
        vm.completeReminder(oil)
        assertEquals(1, env.store.reminders.value.count { it.id == "${oil.id}-next" })
        assertFalse(env.store.reminders.value.first { it.id == oil.id }.isOutstanding)
    }

    @Test
    fun completingANonRepeatingReminderMakesNoSuccessor() = runTest {
        val env = DemoEnv()
        val reminders = FailingReminders(env.reminders)
        val vm = dash(env, reminders)
        keepHot(vm.state)
        vm.selectVehicle(SeedData.SQ5_ID)
        val tires = vm.state.value.reminders.first { it.reminder.title == "Rotate tires" }.reminder // miles-only repeat, no months
        val before = env.store.reminders.value.size
        vm.completeReminder(tires)
        assertEquals(before, env.store.reminders.value.size)
        assertEquals(0, reminders.addCalls)
    }

    // ---- Recalls

    private val vin = "WA1CGAFP5FA012345"

    private fun recallsEnv() = DemoEnv().also { e ->
        e.store.activeVehicleId.value = SeedData.SQ5_ID
        e.store.vehicles.value = e.store.vehicles.value.map { if (it.id == SeedData.SQ5_ID) it.copy(vin = vin) else it }
    }

    @Test
    fun recallsCheckWithoutAVinExplainsAndNeverCallsTheServer() = runTest {
        val e = DemoEnv()
        var calls = 0
        val gateway = object : FunctionsGateway by DemoFunctionsGateway(e.store) {
            override suspend fun lookupRecalls(vehicleId: String, vin: String): List<Recall> { calls++; return emptyList() }
        }
        val vm = RecallsViewModel(gateway, e.vehicles, e.recalls, SeedData.SQ5_ID) { e.now }
        vm.check()
        assertTrue(vm.state.value.error!!.contains("17-character VIN"))
        assertFalse(vm.state.value.checking)
        assertEquals(0, calls)
    }

    @Test
    fun recallsLookupFailureShowsTheMessageAndStopsChecking() = runTest {
        val e = recallsEnv()
        val gateway = object : FunctionsGateway by DemoFunctionsGateway(e.store) {
            override suspend fun lookupRecalls(vehicleId: String, vin: String): List<Recall> = throw boom
        }
        val vm = RecallsViewModel(gateway, e.vehicles, e.recalls, SeedData.SQ5_ID) { e.now }
        vm.check()
        assertEquals("backend unavailable", vm.state.value.error)
        assertFalse(vm.state.value.checking)
        assertNull(vm.state.value.lastCheck)
    }

    @Test
    fun recallsCheckedTwiceStoresEachCampaignOnce() = runTest {
        val e = recallsEnv()
        e.store.recalls.value = emptyList()
        val fetched = Recall(
            id = "24V1", vehicleId = SeedData.SQ5_ID, campaignNumber = "24V1", title = "Airbag",
            recallSource = com.writes.garage.core.model.RecallSource.NHTSA_API,
        )
        val gateway = object : FunctionsGateway by DemoFunctionsGateway(e.store) {
            override suspend fun lookupRecalls(vehicleId: String, vin: String) = listOf(fetched)
        }
        val vm = RecallsViewModel(gateway, e.vehicles, e.recalls, SeedData.SQ5_ID) { e.now }
        vm.check()
        assertEquals(1, vm.state.value.recalls.size)
        assertNotNull(vm.state.value.lastCheck)
        vm.check()
        assertEquals(1, e.store.recalls.value.size)
        assertNull(vm.state.value.error)
    }

    @Test
    fun recallsSaveFailureSurfacesAnError() = runTest {
        val e = recallsEnv()
        val failingRepo = object : com.writes.garage.core.data.RecallRepository by e.recalls {
            override suspend fun upsert(item: Recall): Recall = throw boom
        }
        val vm = RecallsViewModel(DemoFunctionsGateway(e.store), e.vehicles, failingRepo, SeedData.SQ5_ID) { e.now }
        assertTrue(vm.addManual("Seat belt", "", "", ""))
        assertEquals("backend unavailable", vm.state.value.error)
    }

    // ---- Vehicle edit

    @Test
    fun vehicleSaveFailureShowsTheMessageClearsSavingAndAllowsARetry() = runTest {
        val env = DemoEnv()
        val vehicles = FailingVehicles(env.vehicles).apply { addFailure = boom }
        val vm = com.writes.garage.feature.garage.VehicleEditViewModel(vehicles, env.purchases, null, ZoneOffset.UTC)
        vm.edit("make", "Mazda")
        vm.edit("model", "Miata")
        vm.edit("odometer", "100")
        var done = 0
        vm.save { done++ }
        assertEquals(0, done)
        assertEquals("backend unavailable", vm.state.value.formError)
        assertFalse(vm.state.value.saving)
        assertEquals(2, env.store.vehicles.value.size)

        vehicles.addFailure = null
        vm.save { done++ }
        assertEquals(1, done)
        assertEquals(3, env.store.vehicles.value.size)
    }

    @Test
    fun vehicleEditUpdateFailureKeepsTheFormOpen() = runTest {
        val env = DemoEnv()
        val vehicles = FailingVehicles(env.vehicles).apply { updateFailure = boom }
        val vm = com.writes.garage.feature.garage.VehicleEditViewModel(vehicles, env.purchases, SeedData.SQ5_ID, ZoneOffset.UTC)
        vm.edit("nickname", "Renamed")
        var done = false
        vm.save { done = true }
        assertFalse(done)
        assertEquals("backend unavailable", vm.state.value.formError)
        assertEquals("Daily SQ5", env.store.vehicles.value.first { it.id == SeedData.SQ5_ID }.nickname)
    }
}
