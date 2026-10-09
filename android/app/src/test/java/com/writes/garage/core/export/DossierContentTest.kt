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

    // ---- iOS DossierContentTests parity (T2)

    private fun historyLine(e: com.writes.garage.core.model.Entry) =
        DossierContent.serviceHistoryLines(listOf(e), utc)[1].text

    @Test
    fun diyIsStatedOnlyWhenNoShopWasNamed() {
        assertTrue(historyLine(entry("a", shop = null).copy(isDiy = true)).contains("DIY"))
        val withShop = historyLine(entry("a", shop = "Hatch").copy(isDiy = true))
        assertFalse(withShop, withShop.contains("DIY"))
        assertTrue(withShop.contains("Hatch"))
        // A whitespace-only shop is "no shop named", so DIY is stated.
        assertTrue(historyLine(entry("a", shop = "   ").copy(isDiy = true)).contains("DIY"))
        assertFalse(historyLine(entry("a", shop = null).copy(isDiy = false)).contains("DIY"))
    }

    @Test
    fun zeroOrMissingOdometerAndCostAreOmittedNotPrintedAsZero() {
        for (cost in listOf(null, 0.0)) {
            val line = historyLine(entry("a", odo = 0, cost = cost))
            assertFalse(line, line.contains("0 mi"))
            assertFalse(line, line.contains("\$0"))
        }
        // Only the date and the type remain.
        assertEquals(2, historyLine(entry("a", odo = 0, cost = null)).split("  |  ").size)
    }

    @Test
    fun nicknameEqualToModelPrintsNoCaption() {
        val lines = DossierContent.vehicleLines(vehicle().copy(nickname = "SQ5"), utc)
        assertTrue(lines.none { it.style == DossierLineStyle.CAPTION })
        val blank = DossierContent.vehicleLines(vehicle().copy(nickname = "  "), utc)
        assertTrue(blank.none { it.style == DossierLineStyle.CAPTION })
    }

    @Test
    fun purchaseDateAndOdometerGiveOwnedSinceLine() {
        val v = vehicle().copy(purchaseDate = java.time.Instant.parse("2020-03-15T12:00:00Z"), odometerAtPurchase = 12_000)
        val text = DossierContent.vehicleLines(v, utc).map { it.text }
        assertTrue(text.toString(), "Owned since Mar 15, 2020 at 12,000 mi" in text)
        val noOdo = DossierContent.vehicleLines(v.copy(odometerAtPurchase = null), utc).map { it.text }
        assertTrue("Owned since Mar 15, 2020" in noOdo)
        assertTrue(DossierContent.vehicleLines(vehicle(), utc).none { it.text.startsWith("Owned since") })
    }

    @Test
    fun blankVinIsOmitted() {
        assertTrue(DossierContent.vehicleLines(vehicle().copy(vin = "   "), utc).none { it.text.startsWith("VIN") })
        assertTrue(DossierContent.vehicleLines(vehicle().copy(vin = null), utc).none { it.text.startsWith("VIN") })
        // surrounding whitespace is trimmed
        assertTrue("VIN: ABC123" in DossierContent.vehicleLines(vehicle().copy(vin = " ABC123 "), utc).map { it.text })
    }

    @Test
    fun recallStatusesRenderIncludingCompletedDateAndCampaignLess() {
        val done = Recall(
            "r", "v1", campaignNumber = "24V1", title = "Airbag", status = RecallStatus.COMPLETED,
            completedDate = java.time.Instant.parse("2025-05-04T10:00:00Z"),
        )
        val doneNoDate = done.copy(id = "r2", completedDate = null)
        val na = Recall("r3", "v1", title = "Seat belt", status = RecallStatus.NOT_APPLICABLE)
        val lines = DossierContent.recallLines(listOf(done, doneNoDate, na), utc).map { it.text }
        assertEquals("24V1  |  Airbag  |  Completed May 4, 2025", lines[1])
        assertEquals("24V1  |  Airbag  |  Completed", lines[2])
        // No campaign number: no leading separator.
        assertEquals("Seat belt  |  Not applicable", lines[3])
    }

    @Test
    fun costSummaryWithNoMilesOrMonthsOmitsRatios() {
        val lines = DossierContent.costSummaryLines(listOf(entry("a", odo = 0, cost = 50.0)), NOW).map { it.text }
        assertTrue(lines.any { it.contains("\$50.00") })
        assertTrue(lines.none { it.startsWith("Cost per mile") || it.startsWith("Miles covered") })
    }

    @Test
    fun costSummaryAbsentWhenNothingHasACost() {
        assertTrue(DossierContent.costSummaryLines(listOf(entry("a"), entry("b", cost = 0.0)), NOW).isEmpty())
    }
}
