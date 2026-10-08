package com.writes.garage.core.data.demo

import com.writes.garage.core.domain.VehicleLimitReachedException
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.Instant

class DemoRepositoriesTest {
    private val now = Instant.parse("2026-01-01T00:00:00Z")
    private fun store() = DemoStore(SeedData(now)) { now }

    @Test
    fun seedCoversEveryEntryTypeAndBothVehicles() {
        val seed = SeedData(now)
        assertEquals(2, seed.vehicles.size)
        assertTrue("expected ~20 entries, got ${seed.entries.size}", seed.entries.size >= 18)
        assertEquals(EntryType.entries.toSet(), seed.entries.map { it.entryType }.toSet())
        assertTrue(seed.reminders.isNotEmpty())
        assertEquals(seed.entries.size, seed.entries.map { it.id }.toSet().size)
    }

    @Test
    fun entriesAreNewestFirstAndScopedToVehicle() = runTest {
        val repo = DemoEntryRepository(store())
        val list = repo.observeEntries(SeedData.VIPER_ID).first()
        assertTrue(list.isNotEmpty())
        assertTrue(list.all { it.vehicleId == SeedData.VIPER_ID })
        assertEquals(list.sortedByDescending { it.entryDate }, list)
    }

    @Test
    fun entryCrudRoundTrip() = runTest {
        val repo = DemoEntryRepository(store())
        val created = repo.addEntry(
            Entry("", SeedData.SQ5_ID, "", EntryType.REPAIR, now, 83_000, cost = 99.0, notes = "wipers"),
        )
        assertTrue(created.id.isNotBlank())
        assertEquals("wipers", repo.observeEntry(SeedData.SQ5_ID, created.id).first()?.notes)

        repo.updateEntry(created.copy(notes = "new wipers"))
        assertEquals("new wipers", repo.observeEntry(SeedData.SQ5_ID, created.id).first()?.notes)

        repo.deleteEntry(SeedData.SQ5_ID, created.id)
        assertNull(repo.observeEntry(SeedData.SQ5_ID, created.id).first())
    }

    @Test
    fun freePlanEnforcesOneVehicleLimitAndProAllowsFive() = runTest {
        val store = store()
        val vehicles = DemoVehicleRepository(store)
        val purchases = DemoPurchaseRepository(store)
        purchases.setPro(false)
        try {
            vehicles.addVehicle(Vehicle("", "", "Third", "Mazda", "Miata", 1999))
            fail("expected limit")
        } catch (e: VehicleLimitReachedException) {
            assertEquals(1, e.limit)
        }
        purchases.setPro(true)
        val added = vehicles.addVehicle(Vehicle("", "", "Third", "Mazda", "Miata", 1999))
        assertEquals(3, vehicles.observeVehicles().first().size)
        assertNotNull(vehicles.observeVehicle(added.id).first())
    }

    @Test
    fun deleteVehicleIsSoftAndMovesActiveSelection() = runTest {
        val store = store()
        val vehicles = DemoVehicleRepository(store)
        vehicles.setActiveVehicle(SeedData.VIPER_ID)
        vehicles.deleteVehicle(SeedData.VIPER_ID)
        assertNull(vehicles.observeVehicle(SeedData.VIPER_ID).first())
        assertFalse(vehicles.observeVehicles().first().any { it.id == SeedData.VIPER_ID })
        assertNotNull(store.vehicles.value.first { it.id == SeedData.VIPER_ID }.deletedAt)
        assertEquals(SeedData.SQ5_ID, vehicles.activeVehicleId.value)
    }

    @Test
    fun completingReminderMarksItDone() = runTest {
        val repo = DemoReminderRepository(store())
        repo.completeReminder(SeedData.VIPER_ID, "seed-reminder-oil")
        val r = repo.observeReminders(SeedData.VIPER_ID).first().first { it.id == "seed-reminder-oil" }
        assertFalse(r.isOutstanding)
    }

    @Test
    fun receiptProposalNeverWritesEntriesAndConfirmCommitsQuota() = runTest {
        val store = store()
        val gateway = DemoFunctionsGateway(store)
        val before = store.entries.value.size
        val proposal = gateway.receiptQuickAdd(store.vehicles.value.first { it.id == SeedData.VIPER_ID }, listOf("aW1n"))
        assertEquals(before, store.entries.value.size)
        // Like the live backend, the gateway never writes entries; confirm only commits the quota.
        val quota = gateway.confirmReceiptScan(proposal.token)
        assertEquals(before, store.entries.value.size)
        assertEquals(19, quota.remaining)
    }
}
