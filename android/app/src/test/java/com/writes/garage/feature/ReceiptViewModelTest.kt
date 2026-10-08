package com.writes.garage.feature

import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.demo.DemoFunctionsGateway
import com.writes.garage.core.data.demo.DemoProfileRepository
import com.writes.garage.core.data.demo.DemoStorageRepository
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.ReceiptQuota
import com.writes.garage.feature.receipt.PickedImage
import com.writes.garage.feature.receipt.ReceiptViewModel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import com.writes.garage.feature.shared.ProposalForm
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneOffset

class ReceiptViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val photo = listOf(PickedImage("content://demo/receipt.jpg"))

    private class Harness(gatewayWrap: ((FunctionsGateway) -> FunctionsGateway)? = null) {
        val env = DemoEnv().also { it.store.activeVehicleId.value = SeedData.SQ5_ID }
        val profile = DemoProfileRepository(env.store)
        val storage = DemoStorageRepository(env.store)
        val gateway: FunctionsGateway = DemoFunctionsGateway(env.store).let { gatewayWrap?.invoke(it) ?: it }
        val vm = ReceiptViewModel(env.vehicles, profile, storage, gateway, env.entries, isPro = { true }, zone = ZoneOffset.UTC)
        fun entryCount() = env.store.entries.value.size
    }

    @Test
    fun consentGateBlocksScanUntilGranted_thenResumes() = runTest {
        val h = Harness()
        h.profile.setAiConsent(false)
        assertFalse(h.vm.state.value.hasConsent)

        h.vm.scan(photo)
        assertTrue(h.vm.state.value.needsConsent)
        assertNull(h.vm.state.value.proposal)

        h.vm.grantConsent()
        val s = h.vm.state.value
        assertFalse(s.needsConsent)
        assertTrue(h.profile.observeProfile().first()!!.hasAiConsent)
        assertNotNull("pending scan resumes after consent", s.proposal)
    }

    @Test
    fun dismissingConsentDropsThePendingScan() = runTest {
        val h = Harness()
        h.profile.setAiConsent(false)
        h.vm.scan(photo)
        h.vm.dismissConsent()
        assertFalse(h.vm.state.value.needsConsent)
        assertNull(h.vm.state.value.proposal)
        assertFalse(h.vm.requireConsent())
        assertTrue(h.vm.state.value.needsConsent)
    }

    @Test
    fun scanLoadsQuotaAndProposal_butWritesNothing() = runTest {
        val h = Harness()
        val before = h.entryCount()
        assertNotNull(h.vm.state.value.quota)

        h.vm.scan(photo)
        val s = h.vm.state.value
        assertEquals(EntryType.OIL_CHANGE, s.proposal!!.entryType)
        assertEquals("89.95", s.form!!.cost)
        assertEquals("Demo Quick Lube", s.form!!.shop)
        assertEquals(before, h.entryCount())
    }

    @Test
    fun confirmSavesEditedEntryWithAttachment_thenCommitsQuota() = runTest {
        val h = Harness()
        h.vm.scan(photo)
        val quotaBefore = h.vm.state.value.quota!!
        h.vm.updateForm(h.vm.state.value.form!!.copy(cost = "100.50", shop = "My Shop", notes = "edited"))
        h.vm.confirm()

        val s = h.vm.state.value
        assertTrue(s.saved)
        assertNull(s.proposal)
        val saved = h.env.store.entries.value.last()
        assertEquals(100.5, saved.cost!!, 0.0)
        assertEquals("My Shop", saved.shopName)
        assertEquals("edited", saved.notes)
        assertEquals(LocalDate.of(2026, 1, 1), saved.entryDate.atZone(ZoneOffset.UTC).toLocalDate())
        assertEquals(1, saved.attachmentPaths.size)
        assertEquals("Mobil 1", saved.details["oilBrand"])
        assertEquals("5W-30", saved.details["oilGrade"])
        assertTrue(s.quota!!.remaining < quotaBefore.remaining + 1)
    }

    @Test
    fun invalidFormBlocksConfirm() = runTest {
        val h = Harness()
        h.vm.scan(photo)
        val before = h.entryCount()
        h.vm.updateForm(h.vm.state.value.form!!.copy(cost = "abc", odometer = ""))
        h.vm.confirm()
        val s = h.vm.state.value
        assertEquals(before, h.entryCount())
        assertEquals(setOf("cost", "odometer"), s.form!!.errors.keys)
        assertNotNull(s.proposal)
    }

    @Test
    fun changingTypeDropsAiDetails() = runTest {
        val h = Harness()
        h.vm.scan(photo)
        h.vm.updateForm(ProposalForm.withType(h.vm.state.value.form!!, EntryType.REPAIR).let { it.copy(details = it.details + ("title" to "Water pump")) })
        h.vm.confirm()
        val saved = h.env.store.entries.value.last()
        assertEquals(EntryType.REPAIR, saved.entryType)
        assertEquals("Water pump", saved.details["title"])
        assertFalse(saved.details.containsKey("oilBrand"))
    }

    @Test
    fun discardWritesNothing() = runTest {
        val h = Harness()
        val before = h.entryCount()
        h.vm.scan(photo)
        h.vm.discard()
        assertNull(h.vm.state.value.proposal)
        assertEquals(before, h.entryCount())
    }

    @Test
    fun savedEntryAdvancesOdometerOnlyForward() = runTest {
        val h = Harness()
        h.vm.scan(photo)
        h.vm.updateForm(h.vm.state.value.form!!.copy(odometer = "90000"))
        h.vm.confirm()
        assertEquals(90_000, h.env.vehicles.observeVehicle(SeedData.SQ5_ID).first()!!.currentOdometer)
    }

    @Test
    fun confirmRetryAfterQuotaFailureDoesNotDuplicateTheEntry() = runTest {
        var failures = 1
        val h = Harness { real ->
            object : FunctionsGateway by real {
                override suspend fun confirmReceiptScan(token: String): ReceiptQuota {
                    if (failures-- > 0) error("network down")
                    return real.confirmReceiptScan(token)
                }
            }
        }
        h.vm.scan(photo)
        val before = h.entryCount()
        h.vm.confirm()
        assertTrue(h.vm.state.value.entrySaved)
        assertFalse(h.vm.state.value.saved)
        assertEquals(before + 1, h.entryCount())

        h.vm.confirm() // retry only commits the quota
        assertTrue(h.vm.state.value.saved)
        assertEquals(before + 1, h.entryCount())
    }

    @Test
    fun exhaustedQuotaBlocksScan() = runTest {
        val h = Harness { real ->
            object : FunctionsGateway by real {
                override suspend fun receiptQuotaStatus() = ReceiptQuota(remaining = 0, monthlyLimit = 5)
            }
        }
        assertTrue(h.vm.state.value.quotaExhausted)
        h.vm.scan(photo)
        assertNull(h.vm.state.value.proposal)
        assertNotNull(h.vm.state.value.error)
    }

    @Test
    fun scanFailureSurfacesError() = runTest {
        val h = Harness { real ->
            object : FunctionsGateway by real {
                override suspend fun receiptQuickAdd(
                    vehicle: com.writes.garage.core.model.Vehicle,
                    imagesBase64: List<String>,
                    pdfBase64: String?,
                ) = error("Receipt couldn't be read")
            }
        }
        h.vm.scan(photo)
        assertEquals("Receipt couldn't be read", h.vm.state.value.error)
        assertFalse(h.vm.state.value.busy)
    }
}
