package com.writes.garage.core.domain

import com.writes.garage.TestFixtures.NOW
import com.writes.garage.TestFixtures.entry
import com.writes.garage.core.model.EntryType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class OwnershipCostCalculatorTest {
    @Test
    fun noCostedEntriesMeansNoSummary() {
        assertNull(OwnershipCostCalculator.summary(emptyList(), NOW))
        assertNull(OwnershipCostCalculator.summary(listOf(entry("a", cost = 0.0), entry("b", cost = null)), NOW))
    }

    @Test
    fun singleEntryHasTotalButNoRatios() {
        val s = OwnershipCostCalculator.summary(listOf(entry("a", odo = 50_000, cost = 100.0)), NOW)!!
        assertEquals(100.0, s.totalCost, 0.0)
        assertEquals(0, s.milesCovered)
        assertNull(s.costPerMile)
        assertNull(s.costPerMonth)
    }

    @Test
    fun costPerMileUsesEveryEntrysOdometerNotJustCostedOnes() {
        val entries = listOf(
            entry("a", daysAgo = 400, odo = 40_000, cost = 300.0),
            entry("b", daysAgo = 200, odo = 45_000, cost = null), // free warranty repair still proves the miles
            entry("c", daysAgo = 0, odo = 50_000, cost = 200.0),
        )
        val s = OwnershipCostCalculator.summary(entries, NOW)!!
        assertEquals(500.0, s.totalCost, 0.0)
        assertEquals(10_000, s.milesCovered)
        assertEquals(0.05, s.costPerMile!!, 1e-9)
    }

    @Test
    fun costPerMonthNeedsAtLeastAMonthOfHistory() {
        val short = OwnershipCostCalculator.summary(listOf(entry("a", daysAgo = 10, cost = 50.0), entry("b", cost = 50.0)), NOW)!!
        assertNull(short.costPerMonth)
        val long = OwnershipCostCalculator.summary(
            listOf(entry("a", daysAgo = 304, cost = 500.0), entry("b", daysAgo = 0, cost = 500.0)), NOW,
        )!!
        assertNotNull(long.costPerMonth)
        assertEquals(1000.0 / long.monthsCovered, long.costPerMonth!!, 1e-9)
    }

    @Test
    fun sameOdometerNeverDividesByZero() {
        val s = OwnershipCostCalculator.summary(
            listOf(entry("a", odo = 1000, cost = 10.0), entry("b", odo = 1000, cost = 10.0)), NOW,
        )!!
        assertNull(s.costPerMile)
    }

    @Test
    fun costByTypeSortsDescendingAndDropsZero() {
        val r = OwnershipCostCalculator.costByType(
            listOf(
                entry("a", EntryType.FUEL, cost = 40.0), entry("b", EntryType.REPAIR, cost = 500.0),
                entry("c", EntryType.FUEL, cost = 45.0), entry("d", EntryType.TIRE, cost = 0.0),
            ),
        )
        assertEquals(listOf(EntryType.REPAIR to 500.0, EntryType.FUEL to 85.0), r)
    }

    @Test
    fun aMissingOdometerReadingIsIgnoredWhenMeasuringMiles() {
        val s = OwnershipCostCalculator.summary(
            listOf(
                entry("a", daysAgo = 300, odo = 0, cost = 10.0), entry("b", daysAgo = 200, odo = 50_000, cost = 10.0),
                entry("c", daysAgo = 0, odo = 50_500, cost = 10.0),
            ),
            NOW,
        )!!
        assertEquals(500, s.milesCovered)
        assertEquals(30.0 / 500, s.costPerMile!!, 1e-9)
    }

    @Test
    fun onlyZeroOdometersMeansZeroMilesAndNoRatio() {
        val s = OwnershipCostCalculator.summary(listOf(entry("a", odo = 0, cost = 10.0), entry("b", odo = 0, cost = 20.0)), NOW)!!
        assertEquals(0, s.milesCovered)
        assertNull(s.costPerMile)
    }

    @Test
    fun equalTotalsKeepAFixedOrderWhateverTheInputOrder() {
        val a = entry("a", EntryType.TIRE, cost = 100.0)
        val b = entry("b", EntryType.FUEL, cost = 100.0)
        val c = entry("c", EntryType.REPAIR, cost = 250.0)
        val one = OwnershipCostCalculator.costByType(listOf(a, b, c))
        val two = OwnershipCostCalculator.costByType(listOf(b, c, a))
        assertEquals(one, two)
        assertEquals(EntryType.REPAIR, one.first().first)
        assertEquals(setOf(EntryType.TIRE, EntryType.FUEL), one.drop(1).map { it.first }.toSet())
    }

    @Test
    fun negativeCostsAreIgnored() {
        assertNull(OwnershipCostCalculator.summary(listOf(entry("a", cost = -5.0)), NOW))
        assertEquals(emptyList<Any>(), OwnershipCostCalculator.costByType(listOf(entry("a", EntryType.FUEL, cost = -5.0))))
    }
}
