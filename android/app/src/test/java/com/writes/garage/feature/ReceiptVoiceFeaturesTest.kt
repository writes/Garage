package com.writes.garage.feature

import com.writes.garage.core.data.AnalyticsSink
import com.writes.garage.core.data.CreditsOutcome
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.InMemoryCreditsMarkerStore
import com.writes.garage.core.data.PurchaseRepository
import com.writes.garage.core.data.ReceiptCreditsCoordinator
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.data.demo.DemoFunctionsGateway
import com.writes.garage.core.data.demo.DemoProfileRepository
import com.writes.garage.core.data.demo.DemoStorageRepository
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.data.firebase.GatewayException
import com.writes.garage.core.model.CreditsOffer
import com.writes.garage.core.model.CreditsPurchaseResult
import com.writes.garage.core.model.ReceiptQuota
import com.writes.garage.feature.receipt.CreditsState
import com.writes.garage.feature.receipt.PickedImage
import com.writes.garage.feature.receipt.ReceiptViewModel
import com.writes.garage.feature.voice.VoiceViewModel
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class ReceiptVoiceFeaturesTest {
    @get:Rule val main = MainDispatcherRule()

    private class Events : AnalyticsSink {
        val names = mutableListOf<String>()
        override fun log(event: String, params: Map<String, Any?>) {
            names += event
        }
        override fun setEnabled(enabled: Boolean) = Unit
    }

    // ---------------- voice ----------------

    private fun voice(env: DemoEnv, failWith: GatewayException?): VoiceViewModel {
        val gateway = object : FunctionsGateway by DemoFunctionsGateway(env.store) {
            override suspend fun voiceQuickAdd(vehicle: com.writes.garage.core.model.Vehicle, transcript: String) =
                failWith?.let { throw it } ?: DemoFunctionsGateway(env.store).voiceQuickAdd(vehicle, transcript)
        }
        return VoiceViewModel(env.vehicles, DemoProfileRepository(env.store), gateway, env.entries, ZoneOffset.UTC)
    }

    @Test
    fun proRequiredFromTheServerRoutesToThePaywall() = runTest {
        val vm = voice(DemoEnv(), GatewayException(GatewayException.Kind.PRO_REQUIRED, "Voice quick-add is a Pro feature."))
        vm.setTranscript("oil change 90")
        vm.interpret()
        assertTrue(vm.state.value.needsUpgrade)
        assertNull(vm.state.value.error) // not a raw permission-denied message
        vm.upgradeHandled()
        assertFalse(vm.state.value.needsUpgrade)
    }

    @Test
    fun dailyQuotaIsExplainedSeparatelyFromProRequired() = runTest {
        val vm = voice(DemoEnv(), GatewayException(GatewayException.Kind.VOICE_DAILY_EXHAUSTED, "Daily voice quota exceeded."))
        vm.setTranscript("oil change 90")
        vm.interpret()
        assertFalse(vm.state.value.needsUpgrade)
        assertTrue(vm.state.value.error!!.contains("today's voice entries"))
    }

    @Test
    fun voiceConfirmEmitsEventAndReviewMoment() = runTest {
        val env = DemoEnv()
        val events = Events()
        val store = com.writes.garage.core.review.InMemoryReviewStateStore()
        val vm = VoiceViewModel(
            env.vehicles, DemoProfileRepository(env.store), DemoFunctionsGateway(env.store), env.entries, ZoneOffset.UTC, events,
            com.writes.garage.core.review.ReviewPromptCoordinator(store, "1") { env.now },
        )
        vm.setTranscript("brake pads 300")
        vm.interpret()
        vm.confirm()
        assertTrue(vm.state.value.saved)
        assertEquals(listOf("voice_entry_confirmed"), events.names)
        assertEquals(1, store.load().score)
    }

    @Test
    fun classifierRoutesTheNewServerReasons() {
        val c = { code: String, reason: String ->
            com.writes.garage.core.data.firebase.FunctionsMappers.classifyError("op", code, "m", mapOf("reason" to reason)).kind
        }
        assertEquals(GatewayException.Kind.VOICE_DAILY_EXHAUSTED, c("RESOURCE_EXHAUSTED", "voice_daily_exhausted"))
        assertEquals(GatewayException.Kind.OIL_FREE_LIFETIME_EXHAUSTED, c("RESOURCE_EXHAUSTED", "free_lifetime_exhausted"))
        assertEquals(GatewayException.Kind.OIL_DAILY_EXHAUSTED, c("RESOURCE_EXHAUSTED", "pro_daily_exhausted"))
        assertEquals(GatewayException.Kind.PRO_REQUIRED, c("PERMISSION_DENIED", "pro_required"))
    }

    // ---------------- receipt ----------------

    private class Rig(
        wrapStorage: (StorageRepository) -> StorageRepository = { it },
        wrapGateway: (FunctionsGateway) -> FunctionsGateway = { it },
        val purchases: PurchaseRepository? = null,
        credits: ReceiptCreditsCoordinator? = null,
        requireServerPro: Boolean = false,
    ) {
        val env = DemoEnv().also { it.store.activeVehicleId.value = SeedData.SQ5_ID }
        val profile = DemoProfileRepository(env.store)
        val events = Events()
        val released = mutableListOf<String>()
        val gateway = wrapGateway(DemoFunctionsGateway(env.store))
        val vm = ReceiptViewModel(
            env.vehicles, profile, wrapStorage(DemoStorageRepository(env.store)), gateway, env.entries, isPro = { true },
            requireServerPro = requireServerPro, credits = credits, purchases = purchases, uid = { "debug-user" },
            analytics = events, releaseCapture = { released += it }, zone = ZoneOffset.UTC,
        )
    }

    @Test
    fun uploadedReceiptLivesUnderTheSavedEntrysOwnFolder() = runTest {
        val seen = mutableListOf<String?>()
        val rig = Rig(wrapStorage = { real ->
            object : StorageRepository by real {
                override suspend fun uploadAttachment(vehicleId: String, localUri: String, contentType: String, entryId: String?): String {
                    seen += entryId
                    return "users/u/entry-attachments/$vehicleId/$entryId/x.jpg"
                }
            }
        })
        rig.vm.scan(listOf(PickedImage("content://r.jpg")))
        rig.vm.confirm()
        val saved = rig.env.store.entries.value.last()
        assertEquals(listOf(saved.id), seen)
        assertEquals(listOf("users/u/entry-attachments/${SeedData.SQ5_ID}/${saved.id}/x.jpg"), saved.attachmentPaths)
        assertTrue("receipt_entry_confirmed" in rig.events.names)
    }

    @Test
    fun serverPrimacyBlocksUploadsWhenTheServerStillSaysFree() = runTest {
        var uploads = 0
        val rig = Rig(requireServerPro = true, wrapStorage = { real ->
            object : StorageRepository by real {
                override suspend fun uploadAttachment(vehicleId: String, localUri: String, contentType: String, entryId: String?): String {
                    uploads++
                    return "p"
                }
            }
        })
        // client RevenueCat says Pro, the server-written subscription does not (webhook lag): no upload, no dangling path
        assertFalse(rig.env.store.profile.value.serverIsPro)
        rig.vm.scan(listOf(PickedImage("content://r.jpg")))
        rig.vm.confirm()
        assertEquals(0, uploads)
        assertTrue(rig.env.store.entries.value.last().attachmentPaths.isEmpty())

        rig.env.store.profile.value = rig.env.store.profile.value.copy(serverIsPro = true)
        rig.vm.scanAnother()
        rig.vm.scan(listOf(PickedImage("content://r2.jpg")))
        rig.vm.confirm()
        assertEquals(1, uploads)
    }

    @Test
    fun pdfReceiptsAreScannedAsOnePdfAndPreflighted() = runTest {
        var pdf: String? = null
        var images: List<String> = emptyList()
        val rig = Rig(wrapGateway = { real ->
            object : FunctionsGateway by real {
                override suspend fun receiptQuickAdd(vehicle: com.writes.garage.core.model.Vehicle, imagesBase64: List<String>, pdfBase64: String?): com.writes.garage.core.model.ReceiptProposal {
                    pdf = pdfBase64
                    images = imagesBase64
                    return real.receiptQuickAdd(vehicle, imagesBase64, pdfBase64)
                }
            }
        })
        rig.vm.scan(listOf(PickedImage("content://r.pdf", "application/pdf")))
        assertNotNull(pdf)
        assertTrue(images.isEmpty())
        assertNotNull(rig.vm.state.value.proposal)
    }

    @Test
    fun mixedOrTooManyPicksAreRefusedLocally() = runTest {
        val rig = Rig()
        rig.vm.scan(listOf(PickedImage("content://a.pdf", "application/pdf"), PickedImage("content://b.jpg")))
        assertNull(rig.vm.state.value.proposal)
        assertTrue(rig.vm.state.value.error!!.contains("not both"))
        rig.vm.scan(List(3) { PickedImage("content://$it.jpg") })
        assertTrue(rig.vm.state.value.error!!.contains("up to 2"))
    }

    @Test
    fun aNonPdfOrOversizedFileNeverReachesTheServer() = runTest {
        var called = false
        val rig = Rig(
            wrapStorage = { real ->
                object : StorageRepository by real {
                    override suspend fun readBytes(localUri: String, maxBytes: Int) = "<html>".toByteArray()
                }
            },
            wrapGateway = { real ->
                object : FunctionsGateway by real {
                    override suspend fun receiptQuickAdd(vehicle: com.writes.garage.core.model.Vehicle, imagesBase64: List<String>, pdfBase64: String?): com.writes.garage.core.model.ReceiptProposal {
                        called = true
                        return real.receiptQuickAdd(vehicle, imagesBase64, pdfBase64)
                    }
                }
            },
        )
        rig.vm.scan(listOf(PickedImage("content://r.pdf", "application/pdf")))
        assertFalse(called)
        assertEquals("Choose a valid PDF.", rig.vm.state.value.error)
        assertEquals(listOf("content://r.pdf"), rig.released) // capture files are released on failure too
    }

    @Test
    fun captureFilesAreReleasedAfterConfirmAndDiscard() = runTest {
        val rig = Rig()
        rig.vm.scan(listOf(PickedImage("content://cap1.jpg")))
        rig.vm.confirm()
        assertEquals(listOf("content://cap1.jpg"), rig.released)
        rig.vm.scan(listOf(PickedImage("content://cap2.jpg")))
        rig.vm.discard()
        assertEquals(listOf("content://cap1.jpg", "content://cap2.jpg"), rig.released)
    }

    // ---------------- credits ----------------

    private class FakePurchases(
        val result: CreditsPurchaseResult,
        val offer: CreditsOffer? = CreditsOffer("pack", "\$0.99"),
        override var appUserID: String? = null,
        override var isAnonymous: Boolean = false,
        val onPurchase: () -> Unit = {},
    ) : PurchaseRepository by com.writes.garage.core.data.demo.DemoPurchaseRepository(com.writes.garage.core.data.demo.DemoStore()) {
        var purchaseCalls = 0
        override suspend fun receiptCreditsOffer() = offer
        override suspend fun purchaseReceiptCredits(): CreditsPurchaseResult {
            purchaseCalls++
            onPurchase()
            return result
        }
    }

    private fun gatewayWith(states: List<String?>, reconcile: String? = null, status: ReceiptQuota = ReceiptQuota(0, 5, creditsPurchasingEnabled = true)): FunctionsGateway {
        var i = 0
        return object : FunctionsGateway by DemoFunctionsGateway(com.writes.garage.core.data.demo.DemoStore()) {
            override suspend fun receiptQuotaStatus(transactionId: String?): ReceiptQuota =
                if (transactionId == null) status else status.copy(transactionState = states.getOrNull(i++))

            override suspend fun reconcileReceiptCreditPurchase(transactionId: String) = status.copy(transactionState = reconcile)
        }
    }

    private fun coordinator(purchases: PurchaseRepository, gateway: FunctionsGateway, markers: InMemoryCreditsMarkerStore = InMemoryCreditsMarkerStore()) =
        ReceiptCreditsCoordinator(purchases, gateway, markers, listOf(0L, 0L, 0L)) { }

    @Test
    fun grantArrivesAfterPollingAndTheMarkerIsResolved() = runTest {
        val markers = InMemoryCreditsMarkerStore()
        val c = coordinator(FakePurchases(CreditsPurchaseResult.Completed("GPA.1")), gatewayWith(listOf(null, "unknown", "granted")), markers)
        var waiting = false
        val outcome = c.purchase("u1") { waiting = true; assertEquals("GPA.1", markers.pending("u1")) }
        assertTrue(waiting)
        assertTrue(outcome is CreditsOutcome.Granted)
        assertNull(markers.pending("u1"))
    }

    @Test
    fun aMissedWebhookFallsBackToReconcileAndOtherwiseStaysResumable() = runTest {
        val markers = InMemoryCreditsMarkerStore()
        val viaReconcile = coordinator(FakePurchases(CreditsPurchaseResult.Completed("GPA.2")), gatewayWith(emptyList(), reconcile = "granted"), markers)
        assertTrue(viaReconcile.purchase("u1") is CreditsOutcome.Granted)

        val delayed = coordinator(FakePurchases(CreditsPurchaseResult.Completed("GPA.3")), gatewayWith(emptyList(), reconcile = "unknown"), markers)
        assertTrue(delayed.purchase("u1") is CreditsOutcome.Delayed)
        assertEquals("GPA.3", markers.pending("u1")) // money moved: never lost, never re-prompted
        // a later screen open resumes it for that uid only
        assertNull(delayed.resume("someone-else"))
        val resumed = coordinator(FakePurchases(CreditsPurchaseResult.Cancelled), gatewayWith(listOf("granted")), markers)
        assertTrue(resumed.resume("u1") is CreditsOutcome.Granted)
        assertNull(markers.pending("u1"))
    }

    @Test
    fun anAnonymousOrDivergentStoreIdentityRefusesBeforeAnyMoneyMoves() = runTest {
        val markers = InMemoryCreditsMarkerStore()
        val anon = FakePurchases(CreditsPurchaseResult.Completed("GPA.A"), appUserID = "\$RCAnonymousID:x", isAnonymous = true)
        assertEquals(CreditsOutcome.IdentityMismatch, coordinator(anon, gatewayWith(emptyList()), markers).purchase("u1"))
        assertEquals(0, anon.purchaseCalls)

        val other = FakePurchases(CreditsPurchaseResult.Completed("GPA.B"), appUserID = "someone-else")
        assertEquals(CreditsOutcome.IdentityMismatch, coordinator(other, gatewayWith(emptyList()), markers).purchase("u1"))
        assertEquals(0, other.purchaseCalls)
        assertNull(markers.pending("u1"))

        val bound = FakePurchases(CreditsPurchaseResult.Completed("GPA.C"), appUserID = "u1")
        assertTrue(coordinator(bound, gatewayWith(listOf("granted")), markers).purchase("u1") is CreditsOutcome.Granted)
        assertEquals(1, bound.purchaseCalls)
    }

    @Test
    fun identityChangingMidPurchaseKeepsTheMarkerUnderThePayingUid() = runTest {
        val markers = InMemoryCreditsMarkerStore()
        var current: String? = "u1"
        lateinit var p: FakePurchases
        p = FakePurchases(CreditsPurchaseResult.Completed("GPA.D"), appUserID = "u1", onPurchase = { current = "u2" })
        val c = ReceiptCreditsCoordinator(p, gatewayWith(listOf("granted")), markers, listOf(0L), currentUid = { current }) { }
        assertEquals(CreditsOutcome.IdentityChangedAfterPurchase, c.purchase("u1"))
        assertEquals("GPA.D", markers.pending("u1")) // recoverable by the account that paid
        assertNull(markers.pending("u2"))

        // RC identity drifting (e.g. a failed logIn falling back to anonymous) is caught the same way.
        val markers2 = InMemoryCreditsMarkerStore()
        lateinit var q: FakePurchases
        q = FakePurchases(CreditsPurchaseResult.Completed("GPA.E"), appUserID = "u1", onPurchase = { q.isAnonymous = true })
        assertEquals(CreditsOutcome.IdentityChangedAfterPurchase, coordinator(q, gatewayWith(emptyList()), markers2).purchase("u1"))
        assertEquals("GPA.E", markers2.pending("u1"))
    }

    @Test
    fun refundsCancelsPendingAndFailuresMapCleanly() = runTest {
        val refunded = coordinator(FakePurchases(CreditsPurchaseResult.Completed("GPA.4")), gatewayWith(listOf("refunded")))
        assertTrue(refunded.purchase("u") is CreditsOutcome.Refunded)
        assertEquals(CreditsOutcome.Cancelled, coordinator(FakePurchases(CreditsPurchaseResult.Cancelled), gatewayWith(emptyList())).purchase("u"))
        assertEquals(CreditsOutcome.Pending, coordinator(FakePurchases(CreditsPurchaseResult.Pending), gatewayWith(emptyList())).purchase("u"))
        assertEquals(CreditsOutcome.Unavailable, coordinator(FakePurchases(CreditsPurchaseResult.Unavailable), gatewayWith(emptyList())).purchase("u"))
        assertEquals(CreditsOutcome.Failed("boom"), coordinator(FakePurchases(CreditsPurchaseResult.Failed("boom")), gatewayWith(emptyList())).purchase("u"))
    }

    @Test
    fun thrownStatusErrorsAreRetryableNotMisses() = runTest {
        val flaky = object : FunctionsGateway by DemoFunctionsGateway(com.writes.garage.core.data.demo.DemoStore()) {
            var n = 0
            override suspend fun receiptQuotaStatus(transactionId: String?): ReceiptQuota {
                if (++n < 3) error("429")
                return ReceiptQuota(5, 5, transactionState = "granted")
            }
        }
        assertTrue(coordinator(FakePurchases(CreditsPurchaseResult.Completed("GPA.5")), flaky).purchase("u") is CreditsOutcome.Granted)
    }

    @Test
    fun offerShowsOnlyWhenExhaustedAndTheServerCapabilityIsOn() = runTest {
        val exhausted = ReceiptQuota(0, 5, creditsPurchasingEnabled = true, creditsDeficit = 3)
        val gateway = gatewayWith(emptyList(), status = exhausted)
        val rig = Rig(wrapGateway = { gateway }, purchases = FakePurchases(CreditsPurchaseResult.Cancelled))
        val s = rig.vm.state.value
        assertTrue(s.quotaExhausted)
        assertEquals("\$0.99", s.creditsOffer?.priceLabel) // the store's localized price
        assertTrue(s.showCreditsOffer)
        assertEquals(3, s.creditsDeficit)

        val off = Rig(wrapGateway = { gatewayWith(emptyList(), status = exhausted.copy(creditsPurchasingEnabled = false)) }, purchases = FakePurchases(CreditsPurchaseResult.Cancelled))
        assertFalse(off.vm.state.value.showCreditsOffer)
        assertEquals(0, off.vm.state.value.creditsDeficit) // refund-deficit copy only with the capability on

        val noProduct = Rig(wrapGateway = { gateway }, purchases = FakePurchases(CreditsPurchaseResult.Cancelled, offer = null))
        assertFalse(noProduct.vm.state.value.showCreditsOffer)
    }

    @Test
    fun buyingCreditsRefreshesTheQuotaAndSurfacesTheOutcome() = runTest {
        val exhausted = ReceiptQuota(0, 5, creditsPurchasingEnabled = true)
        val granted = exhausted.copy(creditBalance = 10, transactionState = "granted")
        val gateway = object : FunctionsGateway by DemoFunctionsGateway(com.writes.garage.core.data.demo.DemoStore()) {
            override suspend fun receiptQuotaStatus(transactionId: String?) = if (transactionId == null) exhausted else granted
        }
        val purchases = FakePurchases(CreditsPurchaseResult.Completed("GPA.9"))
        val rig = Rig(wrapGateway = { gateway }, purchases = purchases, credits = ReceiptCreditsCoordinator(purchases, gateway, InMemoryCreditsMarkerStore(), listOf(0L)) { })
        rig.vm.buyCredits()
        val s = rig.vm.state.value
        assertEquals(CreditsState.GRANTED, s.creditsState)
        assertEquals(10, s.quota!!.creditBalance)
        assertFalse(s.quotaExhausted)
        assertTrue("receipt_credits_grant_confirmed" in rig.events.names)
    }
}
