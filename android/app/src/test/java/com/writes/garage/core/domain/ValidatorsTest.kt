package com.writes.garage.core.domain

import com.writes.garage.TestFixtures.NOW
import com.writes.garage.TestFixtures.daysAgo
import com.writes.garage.TestFixtures.entry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ValidatorsTest {
    @Test
    fun vinRules() {
        assertTrue(Validators.isValidVin("WA1CGAFP5FA012345"))
        assertTrue(Validators.isValidVin("  wa1cgafp5fa012345 "))
        assertFalse("too short", Validators.isValidVin("WA1CGAFP5FA01234"))
        assertFalse("too long", Validators.isValidVin("WA1CGAFP5FA0123456"))
        assertFalse("I", Validators.isValidVin("WA1CGAFP5FA01234I"))
        assertFalse("O", Validators.isValidVin("WA1CGAFP5FA01234O"))
        assertFalse("Q", Validators.isValidVin("WA1CGAFP5FA01234Q"))
        assertFalse("symbol", Validators.isValidVin("WA1CGAFP5FA0123-5"))
        assertFalse(Validators.isValidVin(null))
        assertEquals("ABC", Validators.normalizeVin(" abc "))
        assertNull(Validators.normalizeVin("  "))
    }

    @Test
    fun odometerParsing() {
        assertEquals(82_440, Validators.parseOdometer("82,440"))
        assertEquals(0, Validators.parseOdometer("0"))
        assertNull(Validators.parseOdometer("-5"))
        assertNull(Validators.parseOdometer("abc"))
        assertNull(Validators.parseOdometer("2000001"))
    }

    @Test
    fun odometerBoundsAndMonotonicWarnings() {
        val entries = listOf(
            entry("old", daysAgo = 100, odo = 40_000),
            entry("mid", daysAgo = 50, odo = 45_000),
            entry("new", daysAgo = 10, odo = 50_000),
            entry("unrecorded", daysAgo = 5, odo = 0), // zero is "not recorded": never pins a bound
        )
        val bounds = Validators.odometerBounds(entries, "v1", on = daysAgo(30))
        assertEquals(45_000, bounds.earlier?.reading)
        assertEquals(50_000, bounds.later?.reading)

        assertTrue(Validators.odometerWarnings(47_000, bounds).isEmpty())
        assertEquals(1, Validators.odometerWarnings(44_000, bounds).size)
        assertEquals(1, Validators.odometerWarnings(51_000, bounds).size)
        assertTrue("unrecorded reading never warns", Validators.odometerWarnings(0, bounds).isEmpty())
    }

    @Test
    fun editingAnEntryExcludesItselfFromItsOwnBounds() {
        val entries = listOf(entry("a", daysAgo = 10, odo = 1_000), entry("b", daysAgo = 5, odo = 2_000))
        val bounds = Validators.odometerBounds(entries, "v1", on = daysAgo(5), excludingEntryId = "b")
        assertEquals(1_000, bounds.earlier?.reading)
        assertNull(bounds.later)
        assertNull(Validators.odometerBounds(entries, "other", NOW).earlier)
    }

    @Test
    fun vehicleLimitPolicy() {
        assertTrue(VehicleLimitPolicy.canAddVehicle(0, isPro = false))
        assertFalse(VehicleLimitPolicy.canAddVehicle(1, isPro = false))
        assertTrue(VehicleLimitPolicy.canAddVehicle(4, isPro = true))
        assertFalse(VehicleLimitPolicy.canAddVehicle(5, isPro = true))
        assertEquals(1, VehicleLimitPolicy.limitFor(false))
        assertEquals(5, VehicleLimitPolicy.limitFor(true))
    }

    @Test
    fun formatters() {
        assertEquals("\$1,234.50", Formatters.currency(1234.5))
        assertEquals("-", Formatters.currency(null))
        assertEquals("82,440 mi", Formatters.odometer(82_440))
        assertEquals("27.5 mpg", Formatters.mpg(27.46))
        assertEquals("\$0.42/mi", Formatters.costPerMile(0.4166))
        assertEquals("12%", Formatters.percent(12.3))
        assertEquals("Jun 1, 2026", Formatters.date(NOW, java.time.ZoneOffset.UTC))
    }

    // ---- T19 edge cases

    @Test
    fun parseOdometerBoundariesAndOddInput() {
        assertNull(Validators.parseOdometer(""))
        assertNull(Validators.parseOdometer("   "))
        assertNull(Validators.parseOdometer(","))
        assertEquals(0, Validators.parseOdometer("0"))
        assertEquals(2_000_000, Validators.parseOdometer("2000000"))
        assertEquals(2_000_000, Validators.parseOdometer("2,000,000"))
        assertNull(Validators.parseOdometer("2000001"))
        assertNull(Validators.parseOdometer("-1"))
        assertNull(Validators.parseOdometer("1e5"))
        assertNull(Validators.parseOdometer("1.5"))
        assertNull(Validators.parseOdometer("12 mi"))
        assertNull(Validators.parseOdometer("99999999999999")) // overflow is a null, not an exception
        assertEquals(1_000, Validators.parseOdometer(" 1 000 "))
        // Pinned, deliberate: a leading plus and non-ASCII digits are accepted (the input filter allows them too).
        assertEquals(5, Validators.parseOdometer("+5"))
        assertEquals(34, Validators.parseOdometer("\u0663\u0664"))
    }

    @Test
    fun aReadingEqualToEitherBoundIsAccepted() {
        val entries = listOf(entry("lo", daysAgo = 50, odo = 45_000), entry("hi", daysAgo = 10, odo = 50_000))
        val bounds = Validators.odometerBounds(entries, "v1", on = daysAgo(30))
        assertTrue(Validators.odometerWarnings(45_000, bounds).isEmpty())
        assertTrue(Validators.odometerWarnings(50_000, bounds).isEmpty())
        assertEquals(1, Validators.odometerWarnings(44_999, bounds).size)
        assertEquals(1, Validators.odometerWarnings(50_001, bounds).size)
    }

    @Test
    fun anEntryAtExactlyTheSameInstantCountsAsEarlier() {
        val same = entry("same", daysAgo = 30, odo = 46_000)
        val later = entry("later", daysAgo = 10, odo = 50_000)
        val bounds = Validators.odometerBounds(listOf(same, later), "v1", on = daysAgo(30))
        assertEquals(46_000, bounds.earlier?.reading)
        assertEquals(50_000, bounds.later?.reading)
    }

    @Test
    fun anUnrecordedNeighbourNeverPinsABound() {
        val entries = listOf(entry("zeroEarlier", daysAgo = 50, odo = 0), entry("zeroLater", daysAgo = 10, odo = 0))
        val bounds = Validators.odometerBounds(entries, "v1", on = daysAgo(30))
        assertNull(bounds.earlier)
        assertNull(bounds.later)
        assertTrue(Validators.odometerWarnings(1, bounds).isEmpty())
    }

    @Test
    fun theHighestEarlierAndLowestLaterReadingPinTheBounds() {
        val entries = listOf(
            entry("e1", daysAgo = 90, odo = 40_000), entry("e2", daysAgo = 60, odo = 44_000), entry("e3", daysAgo = 40, odo = 42_000),
            entry("l1", daysAgo = 10, odo = 49_000), entry("l2", daysAgo = 5, odo = 47_000),
        )
        val bounds = Validators.odometerBounds(entries, "v1", on = daysAgo(30))
        assertEquals(44_000, bounds.earlier?.reading)
        assertEquals(47_000, bounds.later?.reading)
        // Between the neighbours: no warning.
        assertTrue(Validators.odometerWarnings(45_500, bounds).isEmpty())
        // Both warnings can fire when the bounds themselves are inconsistent.
        val crossed = Validators.OdometerBounds(
            Validators.OdometerBoundary(50_000, daysAgo(40)), Validators.OdometerBoundary(40_000, daysAgo(10)),
        )
        assertEquals(2, Validators.odometerWarnings(45_000, crossed).size)
    }

    @Test
    fun warningTextNamesTheReadingAndTheDate() {
        val b = Validators.OdometerBounds(Validators.OdometerBoundary(82_440, NOW), null)
        val w = Validators.odometerWarnings(1_000, b).single()
        assertTrue(w, w.startsWith("Lower than the 82,440 mi recorded on "))
        val later = Validators.OdometerBounds(null, Validators.OdometerBoundary(90_000, NOW))
        assertTrue(Validators.odometerWarnings(95_000, later).single().contains("Higher than the 90,000 mi") )
    }
}
