package com.writes.garage.core.domain

import com.writes.garage.TestFixtures.entry
import com.writes.garage.core.model.EntryType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FuelEconomyTest {
    private fun fill(id: String, daysAgo: Long, odo: Int, gallons: Double, mpg: Double? = null) = entry(
        id, EntryType.FUEL, daysAgo = daysAgo, odo = odo,
        details = buildMap {
            put("gallons", gallons)
            if (mpg != null) put("calculatedMPG", mpg)
        },
    )

    @Test
    fun calculatedMpgGuardsBadInput() {
        assertEquals(25.0, FuelEconomy.calculatedMpg(10_300, 10_000, 12.0)!!, 1e-9)
        assertNull(FuelEconomy.calculatedMpg(10_000, 10_000, 12.0))
        assertNull(FuelEconomy.calculatedMpg(9_900, 10_000, 12.0))
        assertNull(FuelEconomy.calculatedMpg(10_300, 10_000, 0.0))
    }

    @Test
    fun mpgBetweenFillsMeasuresAgainstThePreviousFillByOdometer() {
        val entries = listOf(
            fill("c", 0, 10_600, 12.0),
            fill("a", 20, 10_000, 10.0),
            fill("b", 10, 10_300, 12.0),
            entry("x", EntryType.OIL_CHANGE, odo = 10_200),
        )
        val mpg = FuelEconomy.mpgBetweenFills(entries)
        assertEquals(setOf("b", "c"), mpg.keys) // the first fill has no baseline
        assertEquals(25.0, mpg.getValue("b"), 1e-9)
        assertEquals(25.0, mpg.getValue("c"), 1e-9)
    }

    @Test
    fun fillWithoutGallonsIsSkipped() {
        val entries = listOf(fill("a", 20, 10_000, 10.0), entry("b", EntryType.FUEL, daysAgo = 10, odo = 10_300))
        assertEquals(emptyMap<String, Double>(), FuelEconomy.mpgBetweenFills(entries))
    }

    @Test
    fun weightedAverageIsMilesOverGallonsNotMeanOfMeans() {
        // 4 gal @ 40 mpg = 160 mi, 20 gal @ 20 mpg = 400 mi -> 560 / 24 = 23.33 (the mean of means would be 30)
        val avg = FuelEconomy.weightedAverageMpg(listOf(fill("a", 2, 1, 4.0, 40.0), fill("b", 1, 2, 20.0, 20.0)))!!
        assertEquals(560.0 / 24.0, avg, 1e-9)
    }

    @Test
    fun degradationNeedsFullBaselineAndAMaterialDrop() {
        val healthy = (1..10).map { fill("h$it", (it * 7).toLong(), it, 10.0, 25.0) }
        assertNull(FuelEconomy.degradation(healthy))

        // newest three at 15 mpg vs 25 before: baseline (10 tanks) = (7*25+3*15)/10 = 22 -> drop 31.8%
        val dropped = (1..10).map { fill("d$it", (it * 7).toLong(), it, 10.0, if (it <= 3) 15.0 else 25.0) }
        val verdict = FuelEconomy.degradation(dropped)
        assertNotNull(verdict)
        assertEquals(15.0, verdict!!.currentAvgMpg, 1e-9)
        assertEquals(22.0, verdict.baselineAvgMpg, 1e-9)
        assertEquals((22.0 - 15.0) / 22.0 * 100, verdict.dropPct, 1e-9)

        assertNull("only 9 tanks is not a baseline", FuelEconomy.degradation(dropped.take(9)))
    }

    // ---- advisor edge cases (T12)

    /** Tanks of 10 gal each, newest first, at the given stored MPGs. */
    private fun tanksNewestFirst(vararg mpgs: Double) = mpgs.mapIndexed { i, mpg -> fill("t%02d".format(i), (i + 1) * 7L, i + 1, 10.0, mpg) }

    private val sevenOlder = doubleArrayOf(21.0, 21.0, 21.0, 21.0, 21.0, 22.0, 22.0) // sums to 149

    @Test
    fun aDropOfExactlyFifteenPercentDoesNotFlagButJustMoreDoes() {
        // newest three at 17 mpg; baseline over ten tanks = (510 + 1490) / 100 = 20.0 -> drop is exactly 15.000%
        val exactly = tanksNewestFirst(17.0, 17.0, 17.0, *sevenOlder)
        assertNull(FuelEconomy.degradation(exactly))
        val more = tanksNewestFirst(16.9, 16.9, 16.9, *sevenOlder)
        val v = FuelEconomy.degradation(more)
        assertNotNull(v)
        assertEquals(16.9, v!!.currentAvgMpg, 1e-9)
        assertEquals(19.97, v.baselineAvgMpg, 1e-9)
        assertTrue(v.dropPct > FuelEconomy.DROP_THRESHOLD_PCT)
    }

    @Test
    fun theWindowIsChosenByDateNotByArrayOrder() {
        val dropped = tanksNewestFirst(15.0, 15.0, 15.0, *sevenOlder)
        val expected = FuelEconomy.degradation(dropped)!!
        repeat(10) { seed ->
            val v = FuelEconomy.degradation(dropped.shuffled(java.util.Random(seed.toLong())))!!
            assertEquals(expected.currentAvgMpg, v.currentAvgMpg, 1e-9)
            assertEquals(expected.baselineAvgMpg, v.baselineAvgMpg, 1e-9)
        }
        assertEquals(15.0, expected.currentAvgMpg, 1e-9)
    }

    @Test
    fun sameDayFillUpsResolveByIdSoTheVerdictIsStable() {
        // Two fills on the same day straddle the 3-tank recent window; the greater id ("z") is the newer one.
        val base = (1..8).map { fill("old$it", 10L + it, it, 10.0, 25.0) }
        val a = fill("a", 1, 100, 10.0, 25.0)
        val sameDayLow = fill("m", 2, 101, 10.0, 5.0)
        val sameDayHigh = fill("z", 2, 102, 10.0, 25.0)
        val all = base + a + sameDayLow + sameDayHigh // 11 tanks; recent window = a, z, m (z before m by id desc)
        val v = FuelEconomy.degradation(all)!!
        assertEquals((25.0 + 25.0 + 5.0) / 3, v.currentAvgMpg, 1e-9)
        for (seed in 0..9) assertEquals(v.currentAvgMpg, FuelEconomy.degradation(all.shuffled(java.util.Random(seed.toLong())))!!.currentAvgMpg, 1e-9)
    }

    @Test
    fun aTinyInefficientTankCannotManufactureADrop() {
        val normal = (1..9).map { fill("n$it", (it + 1) * 7L, it, 10.0, 25.0) }
        val tiny = fill("tiny", 1, 50, 0.1, 5.0)
        // simple mean of the newest three would be (5 + 25 + 25) / 3 = 18.3 (a 26% "drop"); weighted it is ~24.9.
        assertNull(FuelEconomy.degradation(normal + tiny))
    }

    @Test
    fun anImprovingTrendIsNull() {
        assertNull(FuelEconomy.degradation(tanksNewestFirst(35.0, 35.0, 35.0, *sevenOlder)))
    }

    @Test
    fun nonFuelAndZeroMpgEntriesAreExcluded() {
        val nine = (1..9).map { fill("f$it", it * 7L, it, 10.0, 25.0) }
        val oilWithMpg = entry("oil", EntryType.OIL_CHANGE, daysAgo = 1, odo = 99, details = mapOf("gallons" to 10.0, "calculatedMPG" to 25.0))
        val zeroMpg = fill("zero", 2, 9, 10.0, 0.0) // same odometer as f9: no derived figure either
        val noGallons = entry("ng", EntryType.FUEL, daysAgo = 3, odo = 10, details = mapOf("calculatedMPG" to 25.0))
        // Still only nine usable tanks: not a baseline.
        assertNull(FuelEconomy.degradation(nine + oilWithMpg + zeroMpg + noGallons))
        assertEquals(25.0, FuelEconomy.weightedAverageMpg(nine + oilWithMpg + zeroMpg + noGallons)!!, 1e-9)
    }

    @Test
    fun fillsWithAZeroOrMissingOdometerHaveNoDerivedMpg() {
        val entries = listOf(
            fill("a", 30, 10_000, 10.0),
            fill("b", 20, 0, 10.0), // odometer not recorded
            fill("c", 10, 10_300, 12.0),
        )
        // b is ignored entirely, so c is measured against a.
        val mpg = FuelEconomy.mpgBetweenFills(entries)
        assertEquals(setOf("c"), mpg.keys)
        assertEquals(25.0, mpg.getValue("c"), 1e-9)
    }

    @Test
    fun fillMpgsPrefersTheStoredFigureAndFallsBackToDerived() {
        val entries = listOf(
            fill("a", 30, 10_000, 10.0),
            fill("b", 20, 10_300, 10.0), // derived 30
            fill("c", 10, 10_500, 10.0, 22.0), // stored 22 (derived would be 20)
        )
        val f = FuelEconomy.fillMpgs(entries).associate { it.entryId to it.mpg }
        assertEquals(mapOf("b" to 30.0, "c" to 22.0), f)
    }
}
