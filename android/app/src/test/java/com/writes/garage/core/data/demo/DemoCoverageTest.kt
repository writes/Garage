package com.writes.garage.core.data.demo

import com.writes.garage.core.data.AttachmentMissingException
import com.writes.garage.core.data.MediaFolder
import com.writes.garage.core.model.Entitlement
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

/** T16: the demo repositories/gateway are the app's whole backend in Demo mode, so their edges matter. */
class DemoCoverageTest {
    private val now = Instant.parse("2026-01-01T00:00:00Z")
    private fun store() = DemoStore(SeedData(now)) { now }

    // ---- auth / profile

    @Test
    fun authSignInAndOut() = runTest {
        val auth = DemoAuthRepository(store())
        assertNull(auth.currentUser.value)
        auth.signInDemo()
        assertTrue(auth.currentUser.value!!.isDemo)
        auth.signOut()
        assertNull(auth.currentUser.value)
        auth.signInWithGoogle("any-token") // demo accepts any token
        assertNotNull(auth.currentUser.value)
    }

    @Test
    fun profileConsentAndThemeWritesAreIndependent() = runTest {
        val s = store()
        val profile = DemoProfileRepository(s)
        assertTrue(profile.observeProfile().first()!!.hasAiConsent)
        profile.setAiConsent(false)
        assertFalse(profile.observeProfile().first()!!.hasAiConsent)
        profile.setAiConsent(true)
        assertEquals(now, profile.observeProfile().first()!!.aiConsentGrantedAt)

        profile.setThemeId("classic")
        assertEquals("classic", profile.observeProfile().first()!!.themeId)
        profile.setThemeId("  ")
        assertNull("a blank theme clears it", profile.observeProfile().first()!!.themeId)
        assertTrue("consent untouched by theme writes", profile.observeProfile().first()!!.hasAiConsent)

        profile.setAnalyticsOptOut(false)
        assertFalse(profile.observeProfile().first()!!.analyticsOptOut)
    }

    // ---- storage

    @Test
    fun storageReturnsDistinctPathsAndTracksDeletes() = runTest {
        val s = store()
        val storage = DemoStorageRepository(s)
        val a = storage.uploadAttachment("v1", "content://x", "image/jpeg", "e1")
        val b = storage.uploadAttachment("v1", "content://x", "image/jpeg", "e1")
        assertTrue(a != b)
        assertTrue(a.contains("/v1/"))
        val m = storage.uploadMedia("v1", "content://x", "image/jpeg", MediaFolder.GALLERY, null)
        assertTrue(m.contains("/v1/"))

        assertTrue(storage.downloadAttachment(a).isNotEmpty())
        storage.deleteAttachment(a)
        assertEquals(listOf(a), storage.deleted)
        try {
            storage.downloadAttachment(a)
            fail("a deleted attachment is missing")
        } catch (e: AttachmentMissingException) {
            assertTrue(storage.downloadAttachment(b).isNotEmpty())
        }
        assertTrue(String(storage.readBytes("content://anything", 1000)).startsWith("%PDF"))
        assertTrue(storage.readAsBase64("content://x", "image/jpeg").isNotEmpty())
    }

    // ---- ids

    @Test
    fun newIdIsUniqueEvenWithAFrozenClock() {
        val s = store()
        val ids = List(2_000) { s.newId("entry") }
        assertEquals(2_000, ids.toSet().size)
        assertTrue(ids.all { it.startsWith("entry-demo-") })
    }

    // ---- vehicle edge cases

    @Test
    fun settingAnUnknownOrDeletedVehicleActiveIsIgnored() = runTest {
        val s = store()
        val vehicles = DemoVehicleRepository(s)
        vehicles.setActiveVehicle(SeedData.SQ5_ID)
        vehicles.setActiveVehicle("nope")
        assertEquals(SeedData.SQ5_ID, vehicles.activeVehicleId.value)
        vehicles.deleteVehicle(SeedData.VIPER_ID) // soft delete
        vehicles.setActiveVehicle(SeedData.VIPER_ID)
        assertEquals("a tombstoned vehicle cannot become active", SeedData.SQ5_ID, vehicles.activeVehicleId.value)
    }

    @Test
    fun updatingATombstonedVehicleDoesNotResurrectIt() = runTest {
        val s = store()
        val vehicles = DemoVehicleRepository(s)
        val stale = s.vehicles.value.first { it.id == SeedData.VIPER_ID }
        vehicles.deleteVehicle(SeedData.VIPER_ID)
        vehicles.updateVehicle(stale.copy(currentOdometer = 99_999)) // a stale copy with deletedAt == null
        assertNull(vehicles.observeVehicle(SeedData.VIPER_ID).first())
        assertNotNull(s.vehicles.value.first { it.id == SeedData.VIPER_ID }.deletedAt)
        assertEquals(1, vehicles.observeVehicles().first().size)
    }

    @Test
    fun updatingAnUnknownVehicleChangesNothing() = runTest {
        val s = store()
        val vehicles = DemoVehicleRepository(s)
        val before = s.vehicles.value
        vehicles.updateVehicle(Vehicle("ghost", "u", "Ghost", "X", "Y", 2000))
        assertEquals(before, s.vehicles.value)
    }

    @Test
    fun updateStampsUpdatedAt() = runTest {
        val s = store()
        val vehicles = DemoVehicleRepository(s)
        vehicles.updateVehicle(s.vehicles.value.first { it.id == SeedData.SQ5_ID }.copy(nickname = "Renamed"))
        val v = s.vehicles.value.first { it.id == SeedData.SQ5_ID }
        assertEquals("Renamed", v.nickname)
        assertEquals(now, v.updatedAt)
    }

    // ---- gateway

    @Test
    fun unknownOrAlreadyUsedReceiptTokensAreRejected() = runTest {
        val s = store()
        val gateway = DemoFunctionsGateway(s)
        try {
            gateway.confirmReceiptScan("never-issued")
            fail("unknown token")
        } catch (e: IllegalStateException) {
            assertTrue(e.message!!.contains("token"))
        }
        val p = gateway.receiptQuickAdd(s.vehicles.value.first(), listOf("aW1n"))
        gateway.confirmReceiptScan(p.token)
        try {
            gateway.confirmReceiptScan(p.token)
            fail("double confirm")
        } catch (e: IllegalStateException) {
            // a token is single-use, like the server's reservation
        }
    }

    @Test
    fun freePlanQuotaIsFiveReceiptsAndTwentyScans_proIsTwentyAndEighty() = runTest {
        val s = store()
        val gateway = DemoFunctionsGateway(s)
        s.entitlement.value = Entitlement.FREE
        val free = gateway.receiptQuotaStatus()
        assertEquals(5, free.monthlyLimit)
        assertEquals(5, free.remaining)
        assertEquals(20, free.scanRemaining)
        assertFalse(free.isPro)
        s.entitlement.value = Entitlement(isPro = true)
        val pro = gateway.receiptQuotaStatus()
        assertEquals(20, pro.monthlyLimit)
        assertEquals(80, pro.scanRemaining)
        assertTrue(pro.isPro)
    }

    @Test
    fun confirmedScansUseUpTheAllowanceAndNeverGoNegative() = runTest {
        val s = store()
        s.entitlement.value = Entitlement.FREE
        val gateway = DemoFunctionsGateway(s)
        var last = gateway.receiptQuotaStatus()
        repeat(7) {
            val p = gateway.receiptQuickAdd(s.vehicles.value.first(), listOf("img$it"))
            last = gateway.confirmReceiptScan(p.token)
        }
        assertEquals(0, last.remaining)
    }

    @Test
    fun voiceKeywordsClassifyTheEntryType() = runTest {
        val s = store()
        val g = DemoFunctionsGateway(s)
        val v = s.vehicles.value.first()
        suspend fun type(text: String) = g.voiceQuickAdd(v, text).entryType
        assertEquals(EntryType.OIL_CHANGE, type("changed the oil"))
        assertEquals(EntryType.FUEL, type("gas 40"))
        assertEquals(EntryType.FUEL, type("filled up the tank"))
        assertEquals(EntryType.FUEL, type("fuel stop"))
        assertEquals(EntryType.BRAKE, type("new brake pads"))
        assertEquals(EntryType.TIRE, type("rotated the tires"))
        assertEquals(EntryType.MAINTENANCE, type("replaced the wipers"))
        // First match wins: "oil" outranks "fuel" in the same sentence.
        assertEquals(EntryType.OIL_CHANGE, type("oil and fuel filter"))
    }

    @Test
    fun voiceCostPicksThePriceNotAPartNumber() = runTest {
        assertEquals(40.0, DemoFunctionsGateway.spokenCost("gas 40"))
        assertEquals(90.0, DemoFunctionsGateway.spokenCost("oil change 5W-30 for 90"))
        assertEquals(48.5, DemoFunctionsGateway.spokenCost("filled 12 gallons for \$48.50"))
        assertEquals(300.0, DemoFunctionsGateway.spokenCost("brake pads 300"))
        assertEquals(129.99, DemoFunctionsGateway.spokenCost("paid 129.99 at the shop")!!, 1e-9)
        assertEquals(75.0, DemoFunctionsGateway.spokenCost("cost 75 total")!!, 0.0)
        assertEquals(20.0, DemoFunctionsGateway.spokenCost("rotated 4 tires \$20")!!, 0.0)
        assertNull(DemoFunctionsGateway.spokenCost("washed the car"))
        assertNull(DemoFunctionsGateway.spokenCost("5W-30"))
        val s = store()
        assertEquals(90.0, DemoFunctionsGateway(s).voiceQuickAdd(s.vehicles.value.first(), "oil change 5W-30 for 90").cost)
    }

    @Test
    fun recallLookupIsScopedToTheVehicle() = runTest {
        val s = store()
        val g = DemoFunctionsGateway(s)
        assertEquals(1, g.lookupRecalls(SeedData.SQ5_ID, "WA1CGAFP5FA012345").size)
        assertTrue(g.lookupRecalls(SeedData.VIPER_ID, "1B3JZ65Z08V200001").isEmpty())
        assertTrue(g.lookupRecalls("nobody", "x").isEmpty())
    }

    @Test
    fun deleteVehicleCleansUpEverythingUnderItAndMovesTheActiveVehicle() = runTest {
        val s = store()
        s.activeVehicleId.value = SeedData.SQ5_ID
        val g = DemoFunctionsGateway(s)
        assertTrue(s.reminders.value.any { it.vehicleId == SeedData.SQ5_ID })
        assertTrue(s.recalls.value.any { it.vehicleId == SeedData.SQ5_ID })
        assertTrue(s.warranties.value.any { it.vehicleId == SeedData.SQ5_ID })
        g.deleteVehicle(SeedData.SQ5_ID)
        assertTrue(s.vehicles.value.none { it.id == SeedData.SQ5_ID })
        assertTrue(s.entries.value.none { it.vehicleId == SeedData.SQ5_ID })
        assertTrue(s.reminders.value.none { it.vehicleId == SeedData.SQ5_ID })
        assertTrue(s.recalls.value.none { it.vehicleId == SeedData.SQ5_ID })
        assertTrue(s.warranties.value.none { it.vehicleId == SeedData.SQ5_ID })
        assertEquals("the active vehicle must not dangle", SeedData.VIPER_ID, s.activeVehicleId.value)
        // The other vehicle's data is untouched.
        assertTrue(s.entries.value.any { it.vehicleId == SeedData.VIPER_ID })
        assertTrue(s.reminders.value.any { it.vehicleId == SeedData.VIPER_ID })
    }

    @Test
    fun deletingTheLastVehicleLeavesNoActiveVehicle() = runTest {
        val s = store()
        val g = DemoFunctionsGateway(s)
        g.deleteVehicle(SeedData.VIPER_ID)
        g.deleteVehicle(SeedData.SQ5_ID)
        assertNull(s.activeVehicleId.value)
        assertTrue(s.vehicles.value.isEmpty())
    }

    @Test
    fun deleteAccountSignsTheDemoUserOutOfTheStore() = runTest {
        val s = store()
        s.user.value = com.writes.garage.core.model.AuthUser("u", null, null, true)
        DemoFunctionsGateway(s).deleteAccount()
        assertNull(s.user.value)
    }

    @Test
    fun oilAnalysisParsingReturnsCannedFields() = runTest {
        val out = DemoFunctionsGateway(store()).parseOilAnalysis("anything")
        assertEquals("Demo Lab", out["labName"])
        assertTrue(DemoFunctionsGateway(store()).experimentConfig().isEmpty())
    }
}
