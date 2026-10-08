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
        assertEquals(11, entries.size)
        // Independently summed from the seed: 74.22+71.80+76.50+72.10+129+240+1150+4+520+129+0.
        assertEquals(2_466.62, stats.totalCost, 0.001)
        // Σ(mpg*gallons)/Σgallons over the four seeded fills = 1419.47 mi / 73.0 gal.
        assertEquals(1_419.47 / 73.0, stats.averageMpg!!, 1e-6)
        assertEquals(EntryType.REPAIR, stats.costByType.first().first)
    }

    @Test
    fun noFuelMpgMeansNull() {
        val entries = seed.entries.filter { it.entryType != EntryType.FUEL }
        assertNull(computeStats("x", entries).averageMpg)
    }
}
