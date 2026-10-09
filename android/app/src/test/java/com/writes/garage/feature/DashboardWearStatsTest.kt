package com.writes.garage.feature

import com.writes.garage.core.data.AnalyticsSink
import com.writes.garage.core.data.demo.DemoAuthRepository
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.data.firebase.FunctionsMappers
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.RecallStatus
import com.writes.garage.core.model.WearItemType
import com.writes.garage.core.model.WearSnapshot
import com.writes.garage.feature.auth.AuthViewModel
import com.writes.garage.feature.dashboard.DashboardViewModel
import com.writes.garage.feature.settings.PaywallViewModel
import com.writes.garage.feature.stats.wearSeries
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.Duration

class DashboardWearStatsTest {
    @get:Rule val main = MainDispatcherRule()

    private fun env() = DemoEnv().also { it.store.activeVehicleId.value = SeedData.SQ5_ID }

    private fun dashboard(e: DemoEnv) = DashboardViewModel(e.vehicles, e.entries, e.reminders, e.recalls, e.warranties, e.wear) { e.now }

    @Test
    fun badgesReflectRecallsAndWarranty() = runTest {
        val e = env()
        val vm = dashboard(e)
        keepHot(vm.state)
        val s = vm.state.value
        assertEquals(1, s.openRecalls) // the seeded SQ5 recall
        assertTrue(s.underWarranty) // the seeded extended warranty
        assertTrue(s.urgentRecalls.isEmpty())

        val notes = FunctionsMappers.recallNotes(null, parkIt = true, parkOutside = false)
        e.recalls.upsert(Recall("", SeedData.SQ5_ID, "99V-1", "Brakes", status = RecallStatus.OUTSTANDING, notes = notes))
        assertEquals(2, vm.state.value.openRecalls)
        assertEquals(1, vm.state.value.urgentRecalls.size)

        e.store.warranties.value = e.store.warranties.value.map { it.copy(expirationDate = e.now.minus(Duration.ofDays(1)), coverageEnd = e.now.minus(Duration.ofDays(1))) }
        assertFalse(vm.state.value.underWarranty)
    }

    @Test
    fun wearItemsTireAgeAndFuelNoticeFeedTheDashboard() = runTest {
        val e = env()
        e.store.wear.value = listOf(
            WearSnapshot("a", SeedData.SQ5_ID, null, WearItemType.FRONT_BRAKE_PADS, 80.0, null, 10_000, e.now.minus(Duration.ofDays(200))),
            WearSnapshot("b", SeedData.SQ5_ID, null, WearItemType.FRONT_BRAKE_PADS, 60.0, null, 14_000, e.now.minus(Duration.ofDays(10))),
        )
        e.entries.addEntry(
            com.writes.garage.TestFixtures.entry("", EntryType.TIRE, vehicleId = SeedData.SQ5_ID, details = mapOf("actionType" to "new_install"))
                .copy(entryDate = e.now.minus(Duration.ofDays(365L * 6))),
        )
        val vm = dashboard(e)
        keepHot(vm.state)
        val s = vm.state.value
        assertEquals(60.0, s.wearItems.single().percentage, 0.0)
        assertEquals(12_000, s.wearItems.single().milesToReplacement)
        assertTrue(s.tireAgeYears!! >= 5.0)
        assertNull(s.fuelDrop) // not enough fill-ups for a verdict
    }

    @Test
    fun wearSeriesNeedsTwoReadingsPerItemOldestFirst() {
        fun w(item: WearItemType, pct: Double, days: Long) =
            WearSnapshot("$item$days", "v", null, item, pct, null, 0, java.time.Instant.EPOCH.plus(Duration.ofDays(days)))
        val series = wearSeries(
            listOf(w(WearItemType.FRONT_TIRES, 40.0, 30), w(WearItemType.FRONT_TIRES, 80.0, 1), w(WearItemType.REAR_TIRES, 50.0, 5)),
        )
        assertEquals(1, series.size)
        assertEquals(listOf(80.0, 40.0), series.single().points)
    }

    @Test
    fun quotaMappingCarriesCreditsFields() {
        val q = FunctionsMappers.parseQuota(
            mapOf("confirmedRemaining" to 0, "confirmedAllowance" to 5, "creditsRemaining" to 0, "creditsDeficit" to 4, "creditsPurchasingEnabled" to true),
        )
        assertEquals(4, q.creditsDeficit)
        assertTrue(q.creditsPurchasingEnabled)
        assertFalse(FunctionsMappers.parseQuota(emptyMap()).creditsPurchasingEnabled)
    }

    @Test
    fun signInAndPaywallEmitEventsThroughTheSink() = runTest {
        val e = env()
        val names = mutableListOf<String>()
        val sink = object : AnalyticsSink {
            override fun log(event: String, params: Map<String, Any?>) {
                names += event
                assertEquals(1, params["schema_version"])
            }
            override fun setEnabled(enabled: Boolean) = Unit
        }
        val auth = object : com.writes.garage.core.data.AuthRepository by DemoAuthRepository(e.store) {
            override suspend fun signInWithGoogle(idToken: String) = if (idToken == "bad") error("no") else Unit
        }
        val vm = AuthViewModel(auth, isDemo = false, analytics = sink)
        vm.signInWithGoogle("good")
        vm.signInWithGoogle("bad")
        assertEquals(listOf("sign_in_completed", "sign_in_failed"), names)

        names.clear()
        val paywall = PaywallViewModel(e.purchases, sink)
        keepHot(paywall.state)
        paywall.purchase("annual")
        assertEquals(listOf("paywall_viewed", "purchase_completed"), names)
    }
}
