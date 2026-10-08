package com.writes.garage.feature

import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.model.EntryType
import com.writes.garage.feature.stats.computeStats
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class StatsTest {
    private val seed = SeedData(Instant.parse("2026-01-01T00:00:00Z"))

    @Test
    fun totalsAndMpgForSq5() {
        val entries = seed.entries.filter { it.vehicleId == SeedData.SQ5_ID }
        val stats = computeStats("SQ5", entries)
        assertEquals(entries.sumOf { it.cost ?: 0.0 }, stats.totalCost, 0.001)
        assertNotNull(stats.averageMpg)
        assertEquals(EntryType.REPAIR, stats.costByType.first().first)
    }

    @Test
    fun noFuelMpgMeansNull() {
        val entries = seed.entries.filter { it.entryType != EntryType.FUEL }
        assertNull(computeStats("x", entries).averageMpg)
    }
}
