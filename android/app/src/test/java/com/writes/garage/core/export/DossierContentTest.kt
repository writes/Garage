package com.writes.garage.core.export

import com.writes.garage.TestFixtures.NOW
import com.writes.garage.TestFixtures.entry
import com.writes.garage.TestFixtures.vehicle
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.FuelType
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.RecallStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneOffset

class DossierContentTest {
    private val utc = ZoneOffset.UTC

    @Test
    fun vehicleIdentityLeadsAndOmitsMissingFields() {
        val lines = DossierContent.vehicleLines(vehicle().copy(vin = "WA1CGAFP5FA012345", fuelType = FuelType.PREMIUM_91), utc)
        assertEquals(DossierLine(DossierLineStyle.TITLE, "2015 Audi SQ5"), lines.first())
        val text = lines.map { it.text }
        assertTrue("Daily" in text)
        assertTrue("VIN: WA1CGAFP5FA012345" in text)
        assertTrue("Fuel: Premium 91" in text)
        assertFalse(text.any { it.startsWith("Plate") || it.startsWith("Color") })
    }

    @Test
    fun serviceHistoryIsNewestFirstAndStatesMileage() {
        val lines = DossierContent.serviceHistoryLines(
            listOf(
                entry("a", EntryType.OIL_CHANGE, daysAgo = 100, odo = 40_000, cost = 80.0, shop = "Joe"),
                entry("b", EntryType.BRAKE, daysAgo = 10, odo = 42_000, notes = "Front pads"),
            ),
            utc,
        )
        assertEquals("Service history", lines[0].text)
        assertTrue(lines[1].text.contains("Brake Service") && lines[1].text.contains("42,000 mi"))
        assertEquals("Front pads", lines[2].text)
        assertTrue(lines[3].text.contains("\$80.00") && lines[3].text.contains("Joe") && lines[3].text.contains("40,000 mi"))
    }

    @Test
    fun costSummaryOnlyWhenThereIsSpend() {
        assertTrue(DossierContent.costSummaryLines(emptyList(), NOW).isEmpty())
        val lines = DossierContent.costSummaryLines(
            listOf(entry("a", daysAgo = 400, odo = 1_000, cost = 100.0), entry("b", odo = 2_000, cost = 100.0)), NOW,
        ).map { it.text }
        assertTrue(lines.any { it.contains("\$200.00") })
        assertTrue(lines.any { it.startsWith("Cost per mile: \$0.20/mi") })
    }

    @Test
    fun recallsRenderStatus() {
        val lines = DossierContent.recallLines(
            listOf(Recall("r1", "v1", campaignNumber = "24V123", title = "Airbag", status = RecallStatus.OUTSTANDING)), utc,
        )
        assertEquals("24V123  |  Airbag  |  Outstanding", lines[1].text)
        assertTrue(DossierContent.recallLines(emptyList(), utc).isEmpty())
    }

    @Test
    fun buildEndsWithAProvenanceFooter() {
        val lines = DossierContent.build(vehicle(), listOf(entry("a", cost = 5.0, odo = 10)), now = NOW, zone = utc)
        assertEquals(DossierLineStyle.CAPTION, lines.last().style)
        assertTrue(lines.last().text.contains("Jun 1, 2026"))
    }
}
