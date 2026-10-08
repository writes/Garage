package com.writes.garage.core.domain

import com.writes.garage.TestFixtures.entry
import com.writes.garage.core.model.EntryType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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
}
