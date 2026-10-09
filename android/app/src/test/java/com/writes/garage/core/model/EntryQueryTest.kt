package com.writes.garage.core.model

import com.writes.garage.TestFixtures.NOW
import com.writes.garage.TestFixtures.entry
import com.writes.garage.core.domain.EntrySearch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EntryQueryTest {
    private fun q(text: String = "", types: Set<EntryType> = emptySet(), start: java.time.Instant? = null, end: java.time.Instant? = null, vehicle: String = "v1") =
        EntryQuery(vehicle, types, text, start, end)

    private val tire = entry(
        "t", EntryType.TIRE, shop = "Tire Rack", notes = "Fresh set",
        details = mapOf(
            "actionType" to "new_install", "tireBrand" to "Michelin", "tireModel" to "Pilot Sport Cup 2",
            "heatCycles" to 3, "isStaggered" to true,
        ),
    )
    private val repair = entry(
        "r", EntryType.REPAIR, details = mapOf("title" to "Water pump + thermostat", "replacedParts" to listOf("Water pump", "Thermostat"), "status" to "resolved"),
    )

    @Test
    fun startAndEndBoundsAreInclusiveAtTheExactInstant() {
        val e = entry("e", daysAgo = 2)
        assertTrue(q(start = e.entryDate).matches(e))
        assertTrue(q(end = e.entryDate).matches(e))
        assertTrue(q(start = e.entryDate, end = e.entryDate).matches(e))
        assertFalse(q(start = e.entryDate.plusMillis(1)).matches(e))
        assertFalse(q(end = e.entryDate.minusMillis(1)).matches(e))
        assertTrue(q(start = e.entryDate.minusSeconds(60), end = NOW).matches(e))
    }

    @Test
    fun blankAndWhitespaceQueriesMatchEverything() {
        assertTrue(q("").matches(tire))
        assertTrue(q("   ").matches(tire))
        assertTrue(q("\t\n").matches(repair))
    }

    @Test
    fun anotherVehicleIsExcluded() {
        assertFalse(q(vehicle = "other").matches(tire))
        assertTrue(q(vehicle = "v1").matches(tire))
    }

    @Test
    fun typeFilterIsAdditive() {
        assertTrue(q(types = setOf(EntryType.TIRE, EntryType.BRAKE)).matches(tire))
        assertFalse(q(types = setOf(EntryType.BRAKE)).matches(tire))
    }

    @Test
    fun searchMatchesDetailValues() {
        assertTrue(q("michelin").matches(tire))
        assertTrue(q("MICHELIN").matches(tire))
        assertTrue(q("pilot sport").matches(tire))
        assertTrue(q("water pump").matches(repair)) // title and the replaced-parts list
        assertTrue(q("thermostat").matches(repair))
        assertTrue(q("3").matches(tire)) // a numeric value
        assertFalse(q("continental").matches(tire))
    }

    @Test
    fun searchMatchesHumanizedFieldNames() {
        assertTrue(q("tire brand").matches(tire))
        assertTrue(q("heat cycles").matches(tire))
        assertTrue(q("replaced parts").matches(repair))
    }

    @Test
    fun choiceValuesMatchTheirHumanizedFormButNotTheStorageToken() {
        assertTrue(q("new install").matches(tire))
        assertFalse("storage token must not match", q("new_install").matches(tire))
    }

    @Test
    fun internalRepresentationTokensNeverMatch() {
        assertFalse(q("true").matches(tire)) // boolean storage value
        assertFalse(q("string").matches(tire))
        assertFalse(q("map").matches(repair))
        assertFalse(q("{").matches(repair))
    }

    @Test
    fun shopNotesAndTypeNameStillMatch() {
        assertTrue(q("rack").matches(tire))
        assertTrue(q("fresh").matches(tire))
        assertTrue(q("tire").matches(tire))
    }

    @Test
    fun humanizeKeyHandlesCamelCaseDotsAndUnderscores() {
        assertEquals("before specs front left camber", EntrySearch.humanizeKey("beforeSpecs.frontLeftCamber"))
        assertEquals("tread depth fl", EntrySearch.humanizeKey("treadDepthFL").let { it.replace("f l", "fl") })
        assertEquals("some key", EntrySearch.humanizeKey("some_key"))
    }

    @Test
    fun nestedDetailMapsAreSearched() {
        val align = entry("a", EntryType.ALIGNMENT, details = mapOf("afterSpecs" to mapOf("frontLeftCamber" to "-3.0")))
        assertTrue(q("-3.0").matches(align))
        assertTrue(q("front left camber").matches(align))
    }
}
