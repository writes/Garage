package com.writes.garage.feature

import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.data.WearSync
import com.writes.garage.core.data.demo.DemoFunctionsGateway
import com.writes.garage.core.data.demo.DemoProfileRepository
import com.writes.garage.core.data.demo.DemoStorageRepository
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.data.firebase.GatewayException
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.WearItemType
import com.writes.garage.core.review.InMemoryReviewStateStore
import com.writes.garage.core.review.ReviewPromptCoordinator
import com.writes.garage.feature.entry.EntryEditViewModel
import kotlinx.coroutines.flow.first
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

class EntryImportAttachmentTest {
    @get:Rule val main = MainDispatcherRule()

    private class Rig(
        val env: DemoEnv = DemoEnv().also { it.store.activeVehicleId.value = SeedData.SQ5_ID },
        val storage: StorageRepository = DemoStorageRepository(env.store),
        gatewayOf: (FunctionsGateway) -> FunctionsGateway = { it },
        val canAttach: Boolean = true,
        vehicleId: String? = SeedData.SQ5_ID,
        entryId: String? = null,
    ) {
        val profile = DemoProfileRepository(env.store)
        val reviewStore = InMemoryReviewStateStore()
        val reviews = ReviewPromptCoordinator(reviewStore, "1.0") { env.now }
        val vm = EntryEditViewModel(
            env.entries, env.vehicles, vehicleId, entryId, ZoneOffset.UTC, today = { LocalDate.of(2026, 1, 1) },
            wear = WearSync(env.wear), storage = storage, canAttach = { canAttach },
            profile = profile, functions = gatewayOf(DemoFunctionsGateway(env.store)), reviews = reviews,
        )
    }

    private fun fill(vm: EntryEditViewModel) {
        vm.setType(EntryType.MAINTENANCE)
        vm.setOdometer("83000")
        vm.setDetail("item", "air_filter")
    }

    // ---------------- oil analysis import ----------------

    @Test
    fun importPrefillsTheFormForReview() = runTest {
        val r = Rig(gatewayOf = { real ->
            object : FunctionsGateway by real {
                override suspend fun parseOilAnalysis(pdfBase64: String) =
                    mapOf("labName" to "Blackstone", "iron" to 12.0, "copper" to 0, "viscosity" to "14 cSt", "milesOnOil" to 3_000.0)
            }
        })
        r.vm.setType(EntryType.OIL_ANALYSIS)
        r.vm.importOilAnalysis("content://lab.pdf")
        val s = r.vm.state.value
        assertEquals("Blackstone", s.details["labName"])
        assertEquals("12", s.details["iron"])
        assertEquals("0", s.details["copper"])
        assertEquals("3000", s.details["milesOnOil"])
        assertTrue(s.importNotice!!.startsWith("Imported 5 fields"))
        assertFalse(s.importing)
        // nothing was saved
        assertTrue(r.env.store.entries.value.none { it.entryType == EntryType.OIL_ANALYSIS && it.details["labName"] == "Blackstone" })
        // the import counts as a review moment
        assertEquals(2, r.reviewStore.load().score)
    }

    @Test
    fun importIsGatedOnAiConsentAndResumesAfterGrant() = runTest {
        val r = Rig()
        r.profile.setAiConsent(false)
        r.vm.setType(EntryType.OIL_ANALYSIS)
        r.vm.importOilAnalysis("content://lab.pdf")
        assertTrue(r.vm.state.value.needsAiConsent)
        assertNull(r.vm.state.value.importNotice)
        r.vm.dismissImportConsent()
        assertFalse(r.vm.state.value.needsAiConsent)

        r.vm.importOilAnalysis("content://lab.pdf")
        r.vm.grantImportConsent()
        assertTrue(r.env.store.profile.value.hasAiConsent)
        assertNotNull(r.vm.state.value.importNotice) // the pending PDF is imported once consent is given
    }

    @Test
    fun importRejectsNonPdfsBeforeCallingTheServer() = runTest {
        var called = false
        val storage = object : StorageRepository by DemoStorageRepository(DemoEnv().store) {
            override suspend fun readBytes(localUri: String, maxBytes: Int) = "not a pdf".toByteArray()
        }
        val r = Rig(storage = storage, gatewayOf = { real ->
            object : FunctionsGateway by real {
                override suspend fun parseOilAnalysis(pdfBase64: String): Map<String, Any?> {
                    called = true
                    return emptyMap()
                }
            }
        })
        r.vm.setType(EntryType.OIL_ANALYSIS)
        r.vm.importOilAnalysis("content://x")
        assertFalse(called)
        assertEquals("Choose a valid PDF.", r.vm.state.value.formError)
    }

    @Test
    fun importQuotaExhaustionRoutesToThePaywallOrExplainsTheDailyLimit() = runTest {
        fun rig(kind: GatewayException.Kind) = Rig(gatewayOf = { real ->
            object : FunctionsGateway by real {
                override suspend fun parseOilAnalysis(pdfBase64: String): Map<String, Any?> = throw GatewayException(kind, "quota")
            }
        }).also { it.vm.setType(EntryType.OIL_ANALYSIS); it.vm.importOilAnalysis("content://x") }

        val free = rig(GatewayException.Kind.OIL_FREE_LIFETIME_EXHAUSTED).vm.state.value
        assertTrue(free.needsUpgrade)
        val pro = rig(GatewayException.Kind.OIL_DAILY_EXHAUSTED).vm.state.value
        assertFalse(pro.needsUpgrade)
        assertTrue(pro.formError!!.contains("today"))
        val junk = Rig(gatewayOf = { real ->
            object : FunctionsGateway by real {
                override suspend fun parseOilAnalysis(pdfBase64: String) = mapOf("labRecommendation" to "x")
            }
        }).also { it.vm.setType(EntryType.OIL_ANALYSIS); it.vm.importOilAnalysis("content://x") }.vm.state.value
        assertTrue(junk.formError!!.contains("doesn't look like"))
    }

    @Test
    fun importOnlyAppliesToTheOilAnalysisForm() = runTest {
        var called = false
        val r = Rig(gatewayOf = { real ->
            object : FunctionsGateway by real {
                override suspend fun parseOilAnalysis(pdfBase64: String): Map<String, Any?> {
                    called = true
                    return mapOf("labName" to "x")
                }
            }
        })
        r.vm.setType(EntryType.FUEL)
        r.vm.importOilAnalysis("content://x")
        assertFalse(called)
    }

    // ---------------- attachments ----------------

    @Test
    fun pendingAttachmentsUploadUnderTheEntryIdAndLandOnTheSavedEntry() = runTest {
        val env = DemoEnv().also { it.store.activeVehicleId.value = SeedData.SQ5_ID }
        val folders = mutableListOf<String?>()
        val storage = object : StorageRepository by DemoStorageRepository(env.store) {
            override suspend fun uploadAttachment(vehicleId: String, localUri: String, contentType: String, entryId: String?): String {
                folders += entryId
                return "users/u/entry-attachments/$vehicleId/$entryId/${folders.size}.jpg"
            }
        }
        val r = Rig(env = env, storage = storage)
        fill(r.vm)
        r.vm.addAttachment("content://1", "image/jpeg", "one")
        r.vm.addAttachment("content://2", "application/pdf", "two.pdf")
        var done = false
        r.vm.save { done = true }
        assertTrue(done)
        val saved = env.store.entries.value.first { it.odometerReading == 83_000 }
        assertEquals(2, saved.attachmentPaths.size)
        assertEquals(setOf(saved.id), folders.toSet()) // both uploads share the saved entry's own id
        assertTrue(saved.attachmentPaths.all { it.contains("/${saved.id}/") })
    }

    @Test
    fun aFailedUploadSavesNothingAndRemovesWhatAlreadyLanded() = runTest {
        val env = DemoEnv().also { it.store.activeVehicleId.value = SeedData.SQ5_ID }
        val deleted = mutableListOf<String>()
        var n = 0
        val storage = object : StorageRepository by DemoStorageRepository(env.store) {
            override suspend fun uploadAttachment(vehicleId: String, localUri: String, contentType: String, entryId: String?): String {
                if (++n == 2) error("upload failed")
                return "landed-$n"
            }

            override suspend fun deleteAttachment(storagePath: String) {
                deleted += storagePath
            }
        }
        val r = Rig(env = env, storage = storage)
        fill(r.vm)
        val before = env.store.entries.value.size
        r.vm.addAttachment("content://1", "image/jpeg", "one")
        r.vm.addAttachment("content://2", "image/jpeg", "two")
        r.vm.save()
        assertEquals(before, env.store.entries.value.size)
        assertEquals(listOf("landed-1"), deleted)
        assertEquals("upload failed", r.vm.state.value.formError)
        assertEquals(2, r.vm.state.value.pendingAttachments.size) // the picks survive for a retry
        assertFalse(r.vm.state.value.saving)
    }

    @Test
    fun freeUsersCannotUploadEvenIfTheyQueueAFile() = runTest {
        val r = Rig(canAttach = false)
        fill(r.vm)
        r.vm.addAttachment("content://1", "image/jpeg", "one")
        val before = r.env.store.entries.value.size
        r.vm.save()
        assertEquals(before, r.env.store.entries.value.size)
        assertTrue(r.vm.state.value.formError!!.contains("Pro"))
    }

    @Test
    fun removingAnExistingAttachmentOnlyHitsStorageAfterTheSaveSucceeds() = runTest {
        val env = DemoEnv().also { it.store.activeVehicleId.value = SeedData.SQ5_ID }
        val seeded = env.entries.addEntry(
            com.writes.garage.TestFixtures.entry("", EntryType.MAINTENANCE, odo = 83_000, vehicleId = SeedData.SQ5_ID, details = mapOf("item" to "air_filter", "status" to "completed"))
                .copy(attachmentPaths = listOf("keep.jpg", "drop.jpg")),
        )
        val storage = DemoStorageRepository(env.store)
        val r = Rig(env = env, storage = storage, entryId = seeded.id)
        r.vm.removeExistingAttachment("drop.jpg")
        assertTrue(storage.deleted.isEmpty()) // backing out would destroy nothing
        r.vm.save()
        assertEquals(listOf("keep.jpg"), env.store.entries.value.first { it.id == seeded.id }.attachmentPaths)
        assertEquals(listOf("drop.jpg"), storage.deleted)
    }

    @Test
    fun onlyPhotosAndPdfsAndAtMostTenAreAccepted() = runTest {
        val r = Rig()
        r.vm.addAttachment("content://x", "text/plain", "x")
        assertTrue(r.vm.state.value.pendingAttachments.isEmpty())
        repeat(12) { r.vm.addAttachment("content://$it", "image/png", "p$it") }
        assertEquals(10, r.vm.state.value.pendingAttachments.size)
        r.vm.removePendingAttachment(0)
        assertEquals(9, r.vm.state.value.pendingAttachments.size)
    }

    // ---------------- wear + review moment ----------------

    @Test
    fun savingABrakeEntryWritesWearAndCountsAsAReviewMoment() = runTest {
        val r = Rig()
        r.vm.setType(EntryType.BRAKE)
        r.vm.setOdometer("83000")
        r.vm.setDetail("frontPadPct", "35")
        r.vm.save()
        val wear = r.env.store.wear.value
        assertEquals(WearItemType.FRONT_BRAKE_PADS, wear.single().wearItem)
        assertEquals(35.0, wear.single().valuePct!!, 0.0)
        assertEquals(1, r.reviewStore.load().score)
        assertEquals(1, r.env.entries.observeEntries(SeedData.SQ5_ID).first().count { it.odometerReading == 83_000 })
    }
}
