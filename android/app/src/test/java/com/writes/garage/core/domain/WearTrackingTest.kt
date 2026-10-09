package com.writes.garage.core.domain

import com.writes.garage.TestFixtures.NOW
import com.writes.garage.TestFixtures.daysAgo
import com.writes.garage.TestFixtures.entry
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.WearItemType
import com.writes.garage.core.model.WearSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WearTrackingTest {
    @Test
    fun treadPercentageUsesTheUsableRange() {
        assertEquals(100.0, WearSnapshotFactory.treadPercentage("10/32")!!, 0.001)
        assertEquals(100.0, WearSnapshotFactory.treadPercentage("12")!!, 0.001) // clamped
        assertEquals(0.0, WearSnapshotFactory.treadPercentage("2/32")!!, 0.001) // legal minimum = flush
        assertEquals(50.0, WearSnapshotFactory.treadPercentage("6/32")!!, 0.001)
        assertEquals(0.0, WearSnapshotFactory.treadPercentage("1")!!, 0.001)
        assertEquals(62.5, WearSnapshotFactory.treadPercentage("7")!!, 0.001)
    }

    @Test
    fun treadParsingRejectsGarbageAndAbsurdValues() {
        assertNull(WearSnapshotFactory.parseTread32nds("abc"))
        assertNull(WearSnapshotFactory.parseTread32nds("1e400"))
        assertNull(WearSnapshotFactory.parseTread32nds("-3"))
        assertNull(WearSnapshotFactory.parseTread32nds("500"))
        assertEquals(6.5, WearSnapshotFactory.parseTread32nds("6.5")!!, 0.0)
        assertEquals(6.0, WearSnapshotFactory.parseTread32nds(" 6 / 32")!!, 0.0)
    }

    @Test
    fun brakeEntryWritesOneSnapshotPerReadingAndClearsTheRest() {
        val e = entry("e1", EntryType.BRAKE, odo = 50_000, details = mapOf("frontPadPct" to 40.0, "rearRotorPct" to "120"))
        val w = WearSnapshotFactory.write(e, NOW)
        assertEquals(setOf("e1-front_brake_pads", "e1-rear_rotors"), w.snapshots.map { it.id }.toSet())
        assertEquals(40.0, w.snapshots.first { it.wearItem == WearItemType.FRONT_BRAKE_PADS }.valuePct!!, 0.0)
        assertEquals(100.0, w.snapshots.first { it.wearItem == WearItemType.REAR_ROTORS }.valuePct!!, 0.0) // clamped
        assertEquals("40%", w.snapshots.first { it.wearItem == WearItemType.FRONT_BRAKE_PADS }.valueRaw)
        assertEquals(setOf("e1-rear_brake_pads", "e1-front_rotors"), w.clearedIds.toSet())
        assertTrue(w.snapshots.all { it.odometerReading == 50_000 && it.entryId == "e1" && it.vehicleId == "v1" })
    }

    @Test
    fun tireEntryCollapsesCornersToTheWorseOne() {
        val e = entry(
            "t1", EntryType.TIRE, odo = 10_000,
            details = mapOf("treadDepthFL" to "8/32", "treadDepthFR" to "4/32", "treadDepthRL" to "7", "treadDepthRR" to ""),
        )
        val w = WearSnapshotFactory.write(e, NOW)
        val front = w.snapshots.first { it.wearItem == WearItemType.FRONT_TIRES }
        assertEquals(25.0, front.valuePct!!, 0.001)
        assertEquals("4/32", front.valueRaw)
        val rear = w.snapshots.first { it.wearItem == WearItemType.REAR_TIRES }
        assertEquals(62.5, rear.valuePct!!, 0.001)
        assertTrue(w.clearedIds.isEmpty())
    }

    @Test
    fun otherEntryTypesProduceNothing() {
        val w = WearSnapshotFactory.write(entry("f", EntryType.FUEL), NOW)
        assertTrue(w.snapshots.isEmpty() && w.clearedIds.isEmpty())
    }

    private fun snap(item: WearItemType, pct: Double, odo: Int, days: Long, id: String = "$item-$odo") =
        WearSnapshot(id, "v1", null, item, pct, null, odo, daysAgo(days))

    @Test
    fun projectionNeedsTwoCredibleReadings() {
        val item = WearItemType.FRONT_BRAKE_PADS
        assertNull(WearProjection.milesToReplacement(item, listOf(snap(item, 60.0, 1_000, 100))))
        // 80% -> 60% over 4,000 mi = 0.005 %/mi -> 12,000 mi left
        val two = listOf(snap(item, 80.0, 10_000, 200), snap(item, 60.0, 14_000, 10))
        assertEquals(12_000, WearProjection.milesToReplacement(item, two))
        // part replaced between readings (percentage went UP)
        assertNull(WearProjection.milesToReplacement(item, listOf(snap(item, 30.0, 10_000, 200), snap(item, 90.0, 14_000, 10))))
        // span under the minimum
        assertNull(WearProjection.milesToReplacement(item, listOf(snap(item, 80.0, 10_000, 20), snap(item, 70.0, 10_100, 10))))
        // fresh part
        assertNull(WearProjection.milesToReplacement(item, listOf(snap(item, 100.0, 10_000, 20), snap(item, 99.0, 14_000, 10))))
    }

    @Test
    fun twoSignificantFiguresRounds() {
        assertEquals(4_200, WearProjection.twoSignificantFigures(4_183))
        assertEquals(1_000, WearProjection.twoSignificantFigures(996))
        assertEquals(99, WearProjection.twoSignificantFigures(99))
    }

    @Test
    fun latestItemsPicksNewestPerItemInEnumOrder() {
        val a = WearItemType.FRONT_BRAKE_PADS
        val t = WearItemType.FRONT_TIRES
        val items = WearProjection.latestItems(
            listOf(snap(t, 70.0, 5_000, 90), snap(a, 80.0, 1_000, 100), snap(a, 55.0, 4_000, 10)),
        )
        assertEquals(listOf(a, t), items.map { it.type })
        assertEquals(55.0, items.first().percentage, 0.0)
    }

    @Test
    fun tireAgeSpeaksOnlyAfterFiveYearsOfTheLatestNewInstall() {
        val old = entry("a", EntryType.TIRE, daysAgo = 365L * 6, details = mapOf("actionType" to "new_install"))
        val young = entry("b", EntryType.TIRE, daysAgo = 365L * 2, details = mapOf("actionType" to "new_install"))
        val rotation = entry("c", EntryType.TIRE, daysAgo = 10, details = mapOf("actionType" to "rotation"))
        assertNotNull(TireAgeAdvisor.yearsSinceNewInstall(listOf(old, rotation), NOW))
        assertTrue(TireAgeAdvisor.yearsSinceNewInstall(listOf(old), NOW)!! >= 5.0)
        assertNull(TireAgeAdvisor.yearsSinceNewInstall(listOf(old, young), NOW)) // latest install wins: understate, never overstate
        assertNull(TireAgeAdvisor.yearsSinceNewInstall(emptyList(), NOW))
    }
}
