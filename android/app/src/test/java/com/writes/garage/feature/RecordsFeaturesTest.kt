package com.writes.garage.feature

import com.writes.garage.core.data.CascadingEntryRepository
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.WearSync
import com.writes.garage.core.data.demo.DemoFunctionsGateway
import com.writes.garage.core.data.demo.DemoStorageRepository
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.data.firebase.GatewayException
import com.writes.garage.core.domain.WearSnapshotFactory
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.GalleryPhoto
import com.writes.garage.core.model.GallerySection
import com.writes.garage.core.model.PartCategory
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.RecallSource
import com.writes.garage.core.model.RecallStatus
import com.writes.garage.core.model.WearItemType
import com.writes.garage.feature.entry.PendingAttachment
import com.writes.garage.feature.garage.DetailingViewModel
import com.writes.garage.feature.garage.GalleryViewModel
import com.writes.garage.feature.garage.GarageViewModel
import com.writes.garage.feature.garage.PartsViewModel
import com.writes.garage.feature.garage.RecallsViewModel
import com.writes.garage.feature.garage.WarrantiesViewModel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class RecordsFeaturesTest {
    @get:Rule val main = MainDispatcherRule()

    private val vin = "WA1CGAFP5FA012345"

    private fun env() = DemoEnv().also { e ->
        e.store.activeVehicleId.value = SeedData.SQ5_ID
        e.store.vehicles.value = e.store.vehicles.value.map { if (it.id == SeedData.SQ5_ID) it.copy(vin = vin) else it }
    }

    // ---------------- recalls ----------------

    private fun lookupReturning(env: DemoEnv, vararg recalls: Recall): FunctionsGateway =
        object : FunctionsGateway by DemoFunctionsGateway(env.store) {
            override suspend fun lookupRecalls(vehicleId: String, vin: String) = recalls.toList()
        }

    private fun nhtsa(campaign: String, notes: String? = null) = Recall(
        id = campaign, vehicleId = SeedData.SQ5_ID, campaignNumber = campaign, title = "Recall $campaign",
        status = RecallStatus.OUTSTANDING, recallSource = RecallSource.NHTSA_API, notes = notes,
    )

    @Test
    fun checkPersistsNewRecallsAndNeverResetsACompletedOne() = runTest {
        val e = env()
        e.store.recalls.value = emptyList()
        val gateway = lookupReturning(e, nhtsa("A1"), nhtsa("B2"))
        val vm = RecallsViewModel(gateway, e.vehicles, e.recalls, SeedData.SQ5_ID) { e.now }
        vm.check()
        assertEquals(setOf("A1", "B2"), vm.state.value.recalls.map { it.campaignNumber }.toSet())
        assertEquals("Checked 2015 Audi SQ5 - 2 recalls on file.", vm.state.value.lastCheck)

        val a1 = vm.state.value.recalls.first { it.campaignNumber == "A1" }
        vm.markCompleted(a1, "Dealer", "82,000".filter(Char::isDigit), e.now)
        vm.check() // a second lookup must not resurrect A1 as outstanding, nor duplicate rows
        val after = vm.state.value.recalls
        assertEquals(2, after.size)
        val done = after.first { it.campaignNumber == "A1" }
        assertEquals(RecallStatus.COMPLETED, done.status)
        assertEquals("Dealer", done.completedShop)
        assertEquals(82_000, done.completedOdometer)
        assertEquals(1, vm.state.value.outstandingCount)
    }

    @Test
    fun urgentAdvisoriesStayVisibleOnTheState() = runTest {
        val e = env()
        e.store.recalls.value = emptyList()
        val notes = com.writes.garage.core.data.firebase.FunctionsMappers.recallNotes("Remedy", parkIt = true, parkOutside = false)
        val vm = RecallsViewModel(lookupReturning(e, nhtsa("A1", notes)), e.vehicles, e.recalls, SeedData.SQ5_ID) { e.now }
        vm.check()
        assertEquals(1, vm.state.value.urgent.size)
        assertTrue(vm.state.value.recalls.single().notes!!.startsWith("DO NOT DRIVE"))
    }

    @Test
    fun checkNeedsAValidVinAndSurfacesUnrecognisedOnes() = runTest {
        val e = env()
        e.store.vehicles.value = e.store.vehicles.value.map { it.copy(vin = "short") }
        val vm = RecallsViewModel(DemoFunctionsGateway(e.store), e.vehicles, e.recalls, SeedData.SQ5_ID) { e.now }
        vm.check()
        assertTrue(vm.state.value.error!!.contains("17-character VIN"))

        e.store.vehicles.value = e.store.vehicles.value.map { it.copy(vin = vin) }
        val failing = object : FunctionsGateway by DemoFunctionsGateway(e.store) {
            override suspend fun lookupRecalls(vehicleId: String, vin: String): List<Recall> =
                throw GatewayException(GatewayException.Kind.VIN_NOT_RECOGNISED, "nf")
        }
        val vm2 = RecallsViewModel(failing, e.vehicles, e.recalls, SeedData.SQ5_ID) { e.now }
        vm2.check()
        assertTrue(vm2.state.value.error!!.contains("did not recognise"))
    }

    @Test
    fun manualAddReopenAndNotApplicable() = runTest {
        val e = env()
        e.store.recalls.value = emptyList()
        val vm = RecallsViewModel(DemoFunctionsGateway(e.store), e.vehicles, e.recalls, SeedData.SQ5_ID) { e.now }
        assertFalse(vm.addManual(" ", "", "", ""))
        assertTrue(vm.addManual("Seat belt", "X-1", "BELTS", "desc"))
        val r = vm.state.value.recalls.single()
        assertEquals(RecallSource.MANUAL, r.recallSource)
        vm.markNotApplicable(r)
        assertEquals(RecallStatus.NOT_APPLICABLE, vm.state.value.recalls.single().status)
        vm.reopen(vm.state.value.recalls.single())
        assertEquals(RecallStatus.OUTSTANDING, vm.state.value.recalls.single().status)
    }

    @Test
    fun garageBadgeCountsOpenRecallsPerVehicle() = runTest {
        val e = env()
        val vm = GarageViewModel(e.vehicles, e.purchases, e.recalls)
        keepHot(vm.state)
        assertEquals(1, vm.state.value.openRecalls[SeedData.SQ5_ID]) // the seeded SQ5 recall
        assertEquals(0, vm.state.value.openRecalls[SeedData.VIPER_ID])
    }

    // ---------------- warranties / parts / detailing ----------------

    @Test
    fun warrantiesCreateEditDelete() = runTest {
        val e = env()
        val vm = WarrantiesViewModel(e.warranties, SeedData.SQ5_ID, ZoneOffset.UTC) { e.now }
        vm.startNew()
        vm.update { copy(provider = "Acme", endDate = java.time.LocalDate.of(2030, 1, 1)) }
        vm.save()
        assertNull(vm.state.value.form)
        val created = vm.state.value.items.first { it.providerName == "Acme" }
        assertEquals(e.now, created.createdAt)
        assertNotNull(created.expirationDate)

        vm.startEdit(created)
        vm.update { copy(provider = "Acme 2") }
        vm.save()
        assertEquals(1, vm.state.value.items.count { it.providerName == "Acme 2" })
        assertEquals(0, vm.state.value.items.count { it.providerName == "Acme" })

        vm.delete(vm.state.value.items.first { it.providerName == "Acme 2" })
        assertTrue(vm.state.value.items.none { it.providerName?.startsWith("Acme") == true })
    }

    @Test
    fun invalidWarrantyKeepsTheFormOpenWithErrors() = runTest {
        val e = env()
        val vm = WarrantiesViewModel(e.warranties, SeedData.SQ5_ID, ZoneOffset.UTC) { e.now }
        vm.startNew()
        vm.update { copy(basicMonths = "x") }
        val before = vm.state.value.items.size
        vm.save()
        assertNotNull(vm.state.value.form)
        assertEquals("Whole number from 0 to 600", vm.state.value.form!!.errors["basicMonths"])
        assertEquals(before, vm.state.value.items.size)
    }

    @Test
    fun partsUploadMediaOnSaveUnderThePartIdAndMarkConsumed() = runTest {
        val e = env()
        val seen = mutableListOf<Pair<String?, com.writes.garage.core.data.MediaFolder>>()
        val storage = object : com.writes.garage.core.data.StorageRepository by DemoStorageRepository(e.store) {
            override suspend fun uploadMedia(vehicleId: String, localUri: String, contentType: String, folder: com.writes.garage.core.data.MediaFolder, ownerId: String?): String {
                seen += ownerId to folder
                return "users/u/vehicles/$vehicleId/${folder.segment}/$ownerId/f.jpg"
            }
        }
        val vm = PartsViewModel(e.parts, SeedData.SQ5_ID, storage, ZoneOffset.UTC)
        vm.startNew()
        vm.update { copy(name = "Pads", category = PartCategory.BRAKES, quantity = "2") }
        vm.pickPhoto(PendingAttachment("content://p", "image/jpeg", "Photo"))
        vm.pickReceipt(PendingAttachment("content://r", "application/pdf", "r.pdf"))
        vm.save()
        val part = vm.state.value.items.single()
        assertEquals(2, seen.size)
        assertTrue(seen.all { it.first == part.id })
        assertTrue(part.photoStoragePath!!.contains("/photos/"))
        assertTrue(part.receiptStoragePath!!.contains("/receipts/"))
        vm.markConsumed(part, true)
        assertTrue(vm.state.value.items.single().isConsumed)
    }

    @Test
    fun partsFailedUploadDoesNotSaveAndCleansUp() = runTest {
        val e = env()
        val deleted = mutableListOf<String>()
        val storage = object : com.writes.garage.core.data.StorageRepository by DemoStorageRepository(e.store) {
            override suspend fun uploadMedia(vehicleId: String, localUri: String, contentType: String, folder: com.writes.garage.core.data.MediaFolder, ownerId: String?): String =
                if (folder == com.writes.garage.core.data.MediaFolder.PHOTOS) "photo-path" else error("receipt upload failed")

            override suspend fun deleteAttachment(storagePath: String) {
                deleted += storagePath
            }
        }
        val vm = PartsViewModel(e.parts, SeedData.SQ5_ID, storage, ZoneOffset.UTC)
        vm.startNew()
        vm.update { copy(name = "Pads") }
        vm.pickPhoto(PendingAttachment("content://p", "image/jpeg", "Photo"))
        vm.pickReceipt(PendingAttachment("content://r", "image/jpeg", "r"))
        vm.save()
        assertTrue(vm.state.value.items.isEmpty())
        assertEquals("receipt upload failed", vm.state.value.error)
        assertEquals(listOf("photo-path"), deleted)
    }

    @Test
    fun detailingSavesNewestFirst() = runTest {
        val e = env()
        val vm = DetailingViewModel(e.detailing, SeedData.SQ5_ID, ZoneOffset.UTC)
        for ((title, date) in listOf("Old" to "2025-01-01", "New" to "2026-01-01")) {
            vm.startNew()
            vm.update { copy(title = title, serviceDate = java.time.LocalDate.parse(date)) }
            vm.save()
        }
        assertEquals(listOf("New", "Old"), vm.state.value.items.map { it.title })
    }

    // ---------------- gallery ----------------

    @Test
    fun galleryUploadsOnSaveOrdersAndSeparatesSections() = runTest {
        val e = env()
        val storage = DemoStorageRepository(e.store)
        val photos = GalleryViewModel(e.gallery, storage, SeedData.SQ5_ID, GallerySection.MAIN, ZoneOffset.UTC)
        val wheels = GalleryViewModel(e.gallery, storage, SeedData.SQ5_ID, GallerySection.WHEEL, ZoneOffset.UTC)

        photos.pick(PendingAttachment("content://a", "image/jpeg", "a"))
        photos.update { copy(title = "Front") }
        photos.save()
        photos.pick(PendingAttachment("content://b", "image/jpeg", "b"))
        photos.update { copy(title = "Rear") }
        photos.save()
        wheels.pick(PendingAttachment("content://w", "image/jpeg", "w"))
        wheels.update { copy(title = "Set A", wheelBrand = "BBS", includeInExport = false) }
        wheels.save()

        assertEquals(listOf("Front", "Rear"), photos.state.value.photos.map { it.title })
        assertEquals(listOf("Set A"), wheels.state.value.photos.map { it.title })
        assertEquals("BBS", wheels.state.value.photos.single().wheelBrand)
        assertFalse(wheels.state.value.photos.single().includeInExport)

        photos.move(photos.state.value.photos.last(), -1)
        assertEquals(listOf("Rear", "Front"), photos.state.value.photos.map { it.title })
        photos.toggleExport(photos.state.value.photos.first())
        assertFalse(photos.state.value.photos.first().includeInExport)
        photos.delete(photos.state.value.photos.first())
        assertEquals(listOf("Front"), photos.state.value.photos.map { it.title })
    }

    @Test
    fun galleryRejectsNonImagesAndRequiresATitle() = runTest {
        val e = env()
        val vm = GalleryViewModel(e.gallery, DemoStorageRepository(e.store), SeedData.SQ5_ID, GallerySection.MAIN, ZoneOffset.UTC)
        vm.pick(PendingAttachment("content://x", "application/pdf", "x"))
        assertNull(vm.state.value.form)
        assertNotNull(vm.state.value.error)
        vm.pick(PendingAttachment("content://x", "image/png", "x"))
        vm.save()
        assertNotNull(vm.state.value.form) // no title
        assertTrue(e.store.gallery.value.isEmpty())
    }

    @Test
    fun galleryFailedSaveRemovesTheUploadedFile() = runTest {
        val e = env()
        val deleted = mutableListOf<String>()
        val storage = object : com.writes.garage.core.data.StorageRepository by DemoStorageRepository(e.store) {
            override suspend fun uploadMedia(vehicleId: String, localUri: String, contentType: String, folder: com.writes.garage.core.data.MediaFolder, ownerId: String?) = "uploaded/x.jpg"

            override suspend fun deleteAttachment(storagePath: String) {
                deleted += storagePath
            }
        }
        val failingRepo = object : com.writes.garage.core.data.GalleryRepository {
            override fun observe(vehicleId: String) = e.gallery.observe(vehicleId)

            override suspend fun upsert(item: GalleryPhoto): GalleryPhoto = error("write failed")

            override suspend fun delete(vehicleId: String, id: String) = Unit
        }
        val vm = GalleryViewModel(failingRepo, storage, SeedData.SQ5_ID, GallerySection.MAIN, ZoneOffset.UTC)
        vm.pick(PendingAttachment("content://a", "image/jpeg", "a"))
        vm.update { copy(title = "T") }
        vm.save()
        assertEquals(listOf("uploaded/x.jpg"), deleted)
        assertEquals("write failed", vm.state.value.error)
    }

    // ---------------- wear + cascade ----------------

    @Test
    fun brakeEntrySavesWriteWearAndEditingClearsDroppedReadings() = runTest {
        val e = env()
        val sync = WearSync(e.wear)
        val saved = e.entries.addEntry(
            com.writes.garage.TestFixtures.entry("", EntryType.BRAKE, odo = 83_000, vehicleId = SeedData.SQ5_ID, details = mapOf("frontPadPct" to 40.0, "rearPadPct" to 70.0)),
        )
        sync.sync(saved, isEdit = false)
        assertEquals(setOf(WearItemType.FRONT_BRAKE_PADS, WearItemType.REAR_BRAKE_PADS), e.store.wear.value.map { it.wearItem }.toSet())
        // edit: the rear reading is emptied -> its snapshot must go; the front one is overwritten (same id), not duplicated
        sync.sync(saved.copy(details = mapOf("frontPadPct" to 35.0)), isEdit = true)
        val wear = e.store.wear.value
        assertEquals(1, wear.size)
        assertEquals(35.0, wear.single().valuePct!!, 0.0)
        assertEquals(WearSnapshotFactory.snapshotId(saved.id, WearItemType.FRONT_BRAKE_PADS), wear.single().id)
        // editing it into a non-wear type removes everything
        sync.sync(saved.copy(entryType = EntryType.MAINTENANCE), isEdit = true)
        assertTrue(e.store.wear.value.isEmpty())
    }

    @Test
    fun deletingAnEntryCascadesToItsAttachmentsAndWearSnapshots() = runTest {
        val e = env()
        val storage = DemoStorageRepository(e.store)
        val repo = CascadingEntryRepository(e.entries, storage, e.wear)
        val entry = e.entries.addEntry(
            com.writes.garage.TestFixtures.entry("", EntryType.TIRE, vehicleId = SeedData.SQ5_ID, details = mapOf("treadDepthFL" to "6/32"))
                .copy(attachmentPaths = listOf("users/u/entry-attachments/v/e/a.jpg", "users/u/entry-attachments/v/e/b.pdf")),
        )
        WearSync(e.wear).sync(entry, isEdit = false)
        assertEquals(1, e.store.wear.value.size)

        repo.deleteEntry(SeedData.SQ5_ID, entry.id)

        assertNull(e.entries.observeEntry(SeedData.SQ5_ID, entry.id).first())
        assertEquals(listOf("users/u/entry-attachments/v/e/a.jpg", "users/u/entry-attachments/v/e/b.pdf"), storage.deleted)
        assertTrue(e.store.wear.value.isEmpty())
    }

    @Test
    fun aFailedStorageCleanupNeverBlocksTheDeletion() = runTest {
        val e = env()
        val failures = mutableListOf<Throwable>()
        val storage = object : com.writes.garage.core.data.StorageRepository by DemoStorageRepository(e.store) {
            override suspend fun deleteAttachment(storagePath: String) = error("offline")
        }
        val repo = CascadingEntryRepository(e.entries, storage, e.wear) { failures += it }
        val entry = e.entries.addEntry(
            com.writes.garage.TestFixtures.entry("", EntryType.OIL_CHANGE, vehicleId = SeedData.SQ5_ID).copy(attachmentPaths = listOf("p1")),
        )
        repo.deleteEntry(SeedData.SQ5_ID, entry.id)
        assertNull(e.entries.observeEntry(SeedData.SQ5_ID, entry.id).first())
        assertEquals(1, failures.size)
    }
}
