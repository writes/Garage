package com.writes.garage.feature

import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.demo.DemoFunctionsGateway
import com.writes.garage.core.data.demo.DemoProfileRepository
import com.writes.garage.core.data.demo.DemoStorageRepository
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.data.firebase.GatewayException
import com.writes.garage.core.domain.OdometerFloor
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Vehicle
import com.writes.garage.feature.entry.EntryEditViewModel
import com.writes.garage.feature.receipt.PickedImage
import com.writes.garage.feature.receipt.ReceiptViewModel
import com.writes.garage.feature.voice.VoiceViewModel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneOffset

/** T9: receipt/voice/edit paths that only run for free users, failed uploads, and the odometer floor. */
class EntitlementAndOdometerPathsTest {
    @get:Rule val main = MainDispatcherRule()

    private val photo = listOf(PickedImage("content://demo/receipt.jpg"))

    private class CountingStorage(private val inner: StorageRepository, var failUploads: Int = 0) : StorageRepository by inner {
        var uploads = 0
        override suspend fun uploadAttachment(vehicleId: String, localUri: String, contentType: String, entryId: String?): String {
            uploads++
            if (failUploads-- > 0) error("upload failed")
            return inner.uploadAttachment(vehicleId, localUri, contentType, entryId)
        }
    }

    private fun receipt(env: DemoEnv, storage: StorageRepository, pro: Boolean, gateway: FunctionsGateway = DemoFunctionsGateway(env.store)) =
        ReceiptViewModel(
            env.vehicles, DemoProfileRepository(env.store), storage, gateway, env.entries, isPro = { pro }, zone = ZoneOffset.UTC,
        )

    private fun sq5Env() = DemoEnv().also { it.store.activeVehicleId.value = SeedData.SQ5_ID }

    // ---- receipt: free user

    @Test
    fun aFreeUserConfirmSavesWithoutAnyAttachmentAndNeverTouchesStorage() = runTest {
        val env = sq5Env()
        val storage = CountingStorage(DemoStorageRepository(env.store))
        val vm = receipt(env, storage, pro = false)
        vm.scan(photo)
        val before = env.store.entries.value.size
        vm.confirm()
        assertTrue(vm.state.value.saved)
        assertEquals(before + 1, env.store.entries.value.size)
        assertTrue(env.store.entries.value.last().attachmentPaths.isEmpty())
        assertEquals("a free user's receipt photo must not be uploaded", 0, storage.uploads)
    }

    @Test
    fun serverPrimacyAlsoBlocksUploadsForAProWhoseSubscriptionIsNotConfirmedYet() = runTest {
        val env = sq5Env()
        val storage = CountingStorage(DemoStorageRepository(env.store))
        val vm = ReceiptViewModel(
            env.vehicles, DemoProfileRepository(env.store), storage, DemoFunctionsGateway(env.store), env.entries,
            isPro = { true }, requireServerPro = true, zone = ZoneOffset.UTC,
        )
        vm.scan(photo)
        vm.confirm()
        assertTrue(vm.state.value.saved)
        assertEquals(0, storage.uploads)
        assertTrue(env.store.entries.value.last().attachmentPaths.isEmpty())
    }

    // ---- receipt: upload failure

    @Test
    fun anUploadFailureBeforeSaveAddsNoEntryAndARetrySucceeds() = runTest {
        val env = sq5Env()
        val storage = CountingStorage(DemoStorageRepository(env.store), failUploads = 1)
        val vm = receipt(env, storage, pro = true)
        vm.scan(photo)
        val before = env.store.entries.value.size
        vm.confirm()
        var s = vm.state.value
        assertEquals("upload failed", s.error)
        assertFalse(s.entrySaved)
        assertFalse(s.saved)
        assertFalse(s.busy)
        assertEquals("no entry may exist when the upload failed", before, env.store.entries.value.size)

        vm.confirm() // retry
        s = vm.state.value
        assertTrue(s.saved)
        assertNull(s.error)
        assertEquals(before + 1, env.store.entries.value.size)
        assertEquals(1, env.store.entries.value.last().attachmentPaths.size)
        assertEquals(2, storage.uploads)
    }

    // ---- receipt: server outcomes route (T8)

    private fun failingScan(kind: GatewayException.Kind, resetAt: String? = null): (DemoEnv) -> FunctionsGateway = { env ->
        val real = DemoFunctionsGateway(env.store)
        object : FunctionsGateway by real {
            override suspend fun receiptQuickAdd(vehicle: Vehicle, imagesBase64: List<String>, pdfBase64: String?) =
                throw GatewayException(kind, "server said $kind", resetAt)
        }
    }

    @Test
    fun freeLifetimeExhaustionOnScanRoutesToThePaywall() = runTest {
        val env = sq5Env()
        val vm = receipt(env, DemoStorageRepository(env.store), pro = false, gateway = failingScan(GatewayException.Kind.FREE_LIFETIME_EXHAUSTED)(env))
        vm.scan(photo)
        val s = vm.state.value
        assertTrue(s.needsUpgrade)
        assertFalse(s.error!!.contains("server said"))
        assertFalse(s.busy)
        vm.upgradeHandled()
        assertFalse(vm.state.value.needsUpgrade)
    }

    @Test
    fun proRequiredOnScanAlsoRoutesToThePaywall() = runTest {
        val env = sq5Env()
        val vm = receipt(env, DemoStorageRepository(env.store), pro = false, gateway = failingScan(GatewayException.Kind.PRO_REQUIRED)(env))
        vm.scan(photo)
        assertTrue(vm.state.value.needsUpgrade)
    }

    @Test
    fun proMonthExhaustionExplainsTheResetAndDoesNotNudgeTheSubscription() = runTest {
        val env = sq5Env()
        val vm = receipt(
            env, DemoStorageRepository(env.store), pro = true,
            gateway = failingScan(GatewayException.Kind.PRO_MONTH_EXHAUSTED, "2026-08-01T00:00:00Z")(env),
        )
        vm.scan(photo)
        val s = vm.state.value
        assertFalse(s.needsUpgrade)
        assertTrue(s.error!!, s.error!!.contains("this month") && s.error!!.contains("2026-08-01"))
    }

    @Test
    fun notAReceiptGetsFriendlyCopyAndOtherErrorsKeepTheirMessage() = runTest {
        val env = sq5Env()
        val vm = receipt(env, DemoStorageRepository(env.store), pro = true, gateway = failingScan(GatewayException.Kind.NOT_A_RECEIPT)(env))
        vm.scan(photo)
        assertTrue(vm.state.value.error!!.contains("doesn't look like a receipt"))
        assertFalse(vm.state.value.needsUpgrade)

        val env2 = sq5Env()
        val vm2 = receipt(env2, DemoStorageRepository(env2.store), pro = true, gateway = failingScan(GatewayException.Kind.UNAVAILABLE)(env2))
        vm2.scan(photo)
        assertEquals("server said UNAVAILABLE", vm2.state.value.error)
    }

    @Test
    fun anExhaustedConfirmIsFinalNotARetryPrompt() = runTest {
        val env = sq5Env()
        val real = DemoFunctionsGateway(env.store)
        val gateway = object : FunctionsGateway by real {
            override suspend fun confirmReceiptScan(token: String) =
                throw GatewayException(GatewayException.Kind.FREE_LIFETIME_EXHAUSTED, "confirm exhausted")
        }
        val vm = receipt(env, DemoStorageRepository(env.store), pro = false, gateway = gateway)
        vm.scan(photo)
        vm.confirm()
        val s = vm.state.value
        assertTrue(s.needsUpgrade)
        assertFalse("retry copy would loop the user", s.error!!.contains("Tap Confirm to retry"))
    }

    // ---- voice: odometer only moves forward

    @Test
    fun voiceConfirmRaisesTheVehicleOdometerButNeverLowersIt() = runTest {
        val env = DemoEnv() // active vehicle = Viper at 18,240
        val vm = VoiceViewModel(env.vehicles, DemoProfileRepository(env.store), DemoFunctionsGateway(env.store), env.entries, ZoneOffset.UTC)
        fun odo() = env.store.vehicles.value.first { it.id == SeedData.VIPER_ID }.currentOdometer

        vm.setTranscript("brake pads 90")
        vm.interpret()
        vm.updateForm(vm.state.value.form!!.copy(odometer = "20000"))
        vm.confirm()
        assertTrue(vm.state.value.error ?: "saved", vm.state.value.saved)
        assertEquals(20_000, odo())

        vm.recordAnother()
        vm.setTranscript("brake pads 100")
        vm.interpret()
        vm.updateForm(vm.state.value.form!!.copy(odometer = "15000"))
        vm.confirm()
        assertTrue(vm.state.value.saved)
        assertEquals("a lower reading must not lower the declared odometer", 20_000, odo())
    }

    // ---- entry edit: odometer correction (iOS VehicleOdometerFloorTests)

    private fun edit(env: DemoEnv, vehicleId: String, entryId: String) = EntryEditViewModel(
        env.entries, env.vehicles, vehicleId, entryId, ZoneOffset.UTC, today = { LocalDate.of(2026, 1, 1) },
    )

    @Test
    fun editingTheNewestEntryDownwardLowersTheVehicleToTheNextHighestReading() = runTest {
        val env = sq5Env()
        val newest = env.entries.addEntry(
            com.writes.garage.TestFixtures.entry("", EntryType.OIL_CHANGE, odo = 90_000, vehicleId = SeedData.SQ5_ID, details = mapOf("oilBrand" to "x", "oilGrade" to "y", "quantityQuarts" to 5.0)),
        )
        env.vehicles.updateVehicle(env.store.vehicles.value.first { it.id == SeedData.SQ5_ID }.copy(currentOdometer = 90_000))
        val vm = edit(env, SeedData.SQ5_ID, newest.id)
        vm.setOdometer("83000") // typo corrected: 90,000 -> 83,000; next highest other entry is 82,440
        vm.save()
        assertEquals(83_000, env.store.vehicles.value.first { it.id == SeedData.SQ5_ID }.currentOdometer)
    }

    @Test
    fun editingDownwardStillRespectsOtherEntries() = runTest {
        val env = sq5Env()
        val newest = env.entries.addEntry(
            com.writes.garage.TestFixtures.entry("", EntryType.OIL_CHANGE, odo = 90_000, vehicleId = SeedData.SQ5_ID, details = mapOf("oilBrand" to "x", "oilGrade" to "y", "quantityQuarts" to 5.0)),
        )
        env.vehicles.updateVehicle(env.store.vehicles.value.first { it.id == SeedData.SQ5_ID }.copy(currentOdometer = 90_000))
        val vm = edit(env, SeedData.SQ5_ID, newest.id)
        vm.setOdometer("70000") // below the other entries' max (82,440): the vehicle follows the other entries
        vm.save()
        assertEquals(82_440, env.store.vehicles.value.first { it.id == SeedData.SQ5_ID }.currentOdometer)
    }

    @Test
    fun editingTheNotesOfAnEntryDoesNotMoveTheDeclaredOdometer() = runTest {
        val env = sq5Env()
        env.vehicles.updateVehicle(env.store.vehicles.value.first { it.id == SeedData.SQ5_ID }.copy(currentOdometer = 85_000))
        val vm = edit(env, SeedData.SQ5_ID, "seed-sq5-fuel")
        vm.update { copy(notes = "just a note") }
        vm.save()
        assertEquals(85_000, env.store.vehicles.value.first { it.id == SeedData.SQ5_ID }.currentOdometer)
    }

    @Test
    fun aVehicleUpdateFailureNeverFailsTheEntrySave() = runTest {
        val env = sq5Env()
        val vehicles = object : VehicleRepository by env.vehicles {
            override suspend fun updateVehicle(vehicle: Vehicle) = error("offline")
        }
        val vm = EntryEditViewModel(env.entries, vehicles, SeedData.SQ5_ID, null, ZoneOffset.UTC, today = { LocalDate.of(2026, 1, 1) })
        vm.setType(EntryType.OIL_CHANGE)
        vm.setOdometer("83000")
        vm.setDetail("oilBrand", "x")
        vm.setDetail("oilGrade", "y")
        vm.setDetail("quantityQuarts", "5")
        var done = false
        vm.save { done = true }
        assertTrue("onDone must still fire", done)
        assertTrue(env.store.entries.value.any { it.odometerReading == 83_000 })
        assertNull(vm.state.value.formError)
        assertEquals(82_440, env.vehicles.observeVehicle(SeedData.SQ5_ID).first()!!.currentOdometer)
    }

    // ---- pure rule

    @Test
    fun odometerFloorMatchesTheIosTable() {
        // new entries
        assertEquals(85_000, OdometerFloor.resulting(85_000, 84_500, null, isEditing = false))
        assertEquals(91_200, OdometerFloor.resulting(85_000, 91_200, null, isEditing = false))
        assertEquals(85_000, OdometerFloor.resulting(85_000, 84_800, 84_500, isEditing = false))
        assertEquals(99_000, OdometerFloor.resulting(85_000, 84_800, 99_000, isEditing = false))
        // edits that change the reading follow it
        assertEquals(100_000, OdometerFloor.resulting(200_000, 100_000, null, isEditing = true, previousReading = 200_000))
        assertEquals(150_000, OdometerFloor.resulting(200_000, 100_000, 150_000, isEditing = true, previousReading = 200_000))
        // an edit that leaves the reading alone never lowers
        assertEquals(200_000, OdometerFloor.resulting(200_000, 100_000, 150_000, isEditing = true, previousReading = 100_000))
        // invariant: never behind the saved entry
        for (declared in listOf(0, 50_000, 120_000)) for (reading in listOf(0, 60_000, 130_000)) for (editing in listOf(true, false)) {
            assertTrue(OdometerFloor.resulting(declared, reading, null, editing, previousReading = null) >= reading)
        }
    }
}
