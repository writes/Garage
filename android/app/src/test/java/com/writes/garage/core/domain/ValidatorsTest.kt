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
}
