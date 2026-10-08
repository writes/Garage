package com.writes.garage.feature

import com.writes.garage.TestFixtures
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.model.EntryType
import com.writes.garage.feature.stats.StatsViewModel
import com.writes.garage.feature.stats.computeStats
import com.writes.garage.feature.stats.parseLapTime
import com.writes.garage.feature.stats.trackDaySummary
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class StatsMoreTest {
    @get:Rule val main = MainDispatcherRule()

    @Test
    fun lapTimesParse() {
        assertEquals(94.821, parseLapTime("1:34.821")!!, 0.0001)
        assertEquals(94.2, parseLapTime(" 94.2 ")!!, 0.0001)
        assertNull(parseLapTime("fast"))
        assertNull(parseLapTime(null))
        assertNull(parseLapTime("0"))
    }

    @Test
    fun trackDaySummaryAggregates() {
        val entries = listOf(
            TestFixtures.entry("t1", EntryType.TRACK_DAY, cost = 400.0, details = mapOf("venueName" to "Willow", "bestLapTime" to "1:34.821", "numberOfLaps" to 24, "heatCyclesAdded" to 1)),
            TestFixtures.entry("t2", EntryType.TRACK_DAY, cost = 300.0, details = mapOf("venueName" to "Buttonwillow", "bestLapTime" to "2:01.5", "numberOfLaps" to 18.0, "heatCyclesAdded" to 2)),
            TestFixtures.entry("t3", EntryType.TRACK_DAY, cost = 100.0, details = mapOf("venueName" to "Willow")),
            TestFixtures.entry("x", EntryType.OIL_CHANGE, cost = 50.0),
        )
        val t = trackDaySummary(entries)!!
        assertEquals(3, t.events)
        assertEquals(800.0, t.totalCost, 0.001)
        assertEquals(42, t.totalLaps)
        assertEquals(3, t.heatCycles)
        assertEquals(listOf("Willow", "Buttonwillow"), t.venues)
        assertEquals("1:34.821", t.bestLapLabel)
        assertEquals("Willow", t.bestLapVenue)
        assertNull(trackDaySummary(entries.filter { it.entryType != EntryType.TRACK_DAY }))
    }

    @Test
    fun ownershipSummaryAndPurchasePrice() {
        val entries = listOf(
            TestFixtures.entry("a", cost = 100.0, odo = 10_000, daysAgo = 400),
            TestFixtures.entry("b", cost = 300.0, odo = 14_000, daysAgo = 10),
        )
        val s = computeStats("Car", entries, purchasePrice = 20_000.0, now = TestFixtures.NOW)
        assertEquals(400.0, s.totalCost, 0.001)
        assertEquals(20_400.0, s.totalCostOfOwnership, 0.001)
        assertEquals(0.1, s.summary!!.costPerMile!!, 0.0001)
        assertNull(computeStats("Car", emptyList()).summary)
        assertEquals(400.0, computeStats("Car", entries).totalCostOfOwnership, 0.001)
    }

    @Test
    fun mpgSeriesIsOldestFirstAndFallsBackToDerivedMpg() {
        val entries = listOf(
            TestFixtures.entry("f3", EntryType.FUEL, daysAgo = 5, odo = 1_600, details = mapOf("gallons" to 10.0, "calculatedMPG" to 28.0)),
            TestFixtures.entry("f1", EntryType.FUEL, daysAgo = 25, odo = 1_000, details = mapOf("gallons" to 10.0)),
            TestFixtures.entry("f2", EntryType.FUEL, daysAgo = 15, odo = 1_300, details = mapOf("gallons" to 10.0)),
        )
        val s = computeStats("Car", entries)
        // f1 has no previous fill; f2 derived (300 mi / 10 gal); f3 uses its STORED 28.0 (derived would be 30.0).
        assertEquals(listOf(30.0, 28.0), s.mpgSeries.map { it.mpg })
        assertEquals(listOf("f2", "f3").map { id -> entries.first { it.id == id }.entryDate }, s.mpgSeries.map { it.date })
        // Weighted over the same two fills: (300 + 28*10) mi / 20 gal.
        assertEquals(29.0, s.averageMpg!!, 1e-9)
    }

    // ---- T5: venues, derived-fill average, tie-break

    @Test
    fun venuesAreDeduplicatedCaseInsensitivelyAfterTrimmingKeepingTheFirstSpelling() {
        val entries = listOf(
            TestFixtures.entry("t1", EntryType.TRACK_DAY, daysAgo = 3, details = mapOf("venueName" to "Willow")),
            TestFixtures.entry("t2", EntryType.TRACK_DAY, daysAgo = 2, details = mapOf("venueName" to " willow ")),
            TestFixtures.entry("t3", EntryType.TRACK_DAY, daysAgo = 1, details = mapOf("venueName" to "WILLOW"), shop = "Other"),
            TestFixtures.entry("t4", EntryType.TRACK_DAY, daysAgo = 1, details = mapOf("venueName" to "  ")),
        )
        val t = trackDaySummary(entries)!!
        assertEquals(listOf("Willow"), t.venues)
        assertEquals(4, t.events)
    }

    @Test
    fun averageMpgIsMilesOverGallonsForFillsWithOnlyGallonsAndOdometer() {
        // Receipt/voice fills carry no stored calculatedMPG. Tanks: 160 mi / 4 gal (40 mpg), 400 mi / 20 gal (20 mpg).
        val entries = listOf(
            TestFixtures.entry("a", EntryType.FUEL, daysAgo = 30, odo = 1_000, details = mapOf("gallons" to 10.0)),
            TestFixtures.entry("b", EntryType.FUEL, daysAgo = 20, odo = 1_160, details = mapOf("gallons" to 4.0)),
            TestFixtures.entry("c", EntryType.FUEL, daysAgo = 10, odo = 1_560, details = mapOf("gallons" to 20.0)),
        )
        val avg = computeStats("Car", entries).averageMpg!!
        assertEquals(560.0 / 24.0, avg, 1e-9)
        assertTrue("never the mean of means (30.0)", Math.abs(avg - 30.0) > 1.0)
    }

    @Test
    fun averageAndSeriesUseTheSameSetOfFills() {
        val entries = listOf(
            TestFixtures.entry("a", EntryType.FUEL, daysAgo = 40, odo = 1_000, details = mapOf("gallons" to 10.0)),
            TestFixtures.entry("b", EntryType.FUEL, daysAgo = 30, odo = 1_200, details = mapOf("gallons" to 10.0)), // derived 20
            TestFixtures.entry("c", EntryType.FUEL, daysAgo = 20, odo = 1_500, details = mapOf("gallons" to 10.0, "calculatedMPG" to 40.0)), // stored
        )
        val s = computeStats("Car", entries)
        assertEquals(listOf(20.0, 40.0), s.mpgSeries.map { it.mpg })
        assertEquals("(200 + 400) mi / 20 gal", 30.0, s.averageMpg!!, 1e-9)
    }

    @Test
    fun noGallonsAnywhereMeansNoAverageRatherThanAMeanOfMeans() {
        val entries = listOf(
            TestFixtures.entry("a", EntryType.FUEL, daysAgo = 2, odo = 1_100, details = mapOf("calculatedMPG" to 10.0)),
            TestFixtures.entry("b", EntryType.FUEL, daysAgo = 1, odo = 1_200, details = mapOf("calculatedMPG" to 30.0)),
        )
        val s = computeStats("Car", entries)
        assertEquals(2, s.mpgSeries.size)
        assertNull(s.averageMpg)
    }

    @Test
    fun bestLapTieGoesToTheMostRecentDayRegardlessOfListOrder() {
        val old = TestFixtures.entry("old", EntryType.TRACK_DAY, daysAgo = 30, details = mapOf("venueName" to "Sonoma", "bestLapTime" to "1:40.000"))
        val recent = TestFixtures.entry("recent", EntryType.TRACK_DAY, daysAgo = 2, details = mapOf("venueName" to "Thunderhill", "bestLapTime" to "1:40.0"))
        val slower = TestFixtures.entry("slow", EntryType.TRACK_DAY, daysAgo = 1, details = mapOf("venueName" to "Laguna", "bestLapTime" to "1:41"))
        for (order in listOf(listOf(old, recent, slower), listOf(slower, recent, old), listOf(recent, slower, old))) {
            val t = trackDaySummary(order)!!
            assertEquals(100.0, t.bestLapSeconds!!, 1e-9)
            assertEquals("Thunderhill", t.bestLapVenue)
        }
    }

    @Test
    fun viewModelFollowsTheActiveVehicle() = runTest {
        val env = DemoEnv()
        val vm = StatsViewModel(env.vehicles, env.entries) { env.now }
        keepHot(vm.state)
        assertEquals("Viper ACR", vm.state.value.vehicleName)
        assertNotNull(vm.state.value.trackDay)
        env.vehicles.setActiveVehicle(SeedData.SQ5_ID)
        assertEquals("Daily SQ5", vm.state.value.vehicleName)
        assertNull(vm.state.value.trackDay)
        assertTrue(vm.state.value.mpgSeries.size >= 4)
        assertTrue(vm.state.value.costByType.isNotEmpty())
    }
}
