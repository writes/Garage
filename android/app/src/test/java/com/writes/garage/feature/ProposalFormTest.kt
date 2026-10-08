package com.writes.garage.feature

import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.ReceiptProposal
import com.writes.garage.feature.shared.ProposalForm
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

class ProposalFormTest {
    private val proposal = ReceiptProposal(
        token = "t", vehicleId = "v1", entryType = EntryType.OIL_CHANGE,
        entryDate = Instant.parse("2026-03-04T08:00:00Z"), odometerReading = null, cost = 12.5,
        details = mapOf("brand" to "X", "oilGrade" to "5W-30", "quantityQuarts" to 5.0),
    )

    @Test
    fun fallsBackToVehicleOdometerAndFormatsMoney() {
        val f = ProposalForm.fromReceipt(proposal, 5000, ZoneOffset.UTC)
        assertEquals("5000", f.odometer)
        assertEquals("12.50", f.cost)
        assertEquals("2026-03-04", f.date.toString())
    }

    @Test
    fun validateAndParseLenientMoney() {
        val f = ProposalForm.fromReceipt(proposal, 5000, ZoneOffset.UTC)
        assertTrue(ProposalForm.validate(f).isEmpty())
        assertEquals(1234.5, ProposalForm.parseCost("\$1,234.50")!!, 0.0)
        assertEquals(setOf("cost"), ProposalForm.validate(f.copy(cost = "-3")).keys)
        assertTrue(ProposalForm.validate(f.copy(cost = "")).isEmpty())
    }

    @Test
    fun toEntryWritesIosDecodableOilDetails() {
        val p = proposal.copy(details = mapOf("brand" to "Mobil 1", "oilGrade" to "5W-30", "quantityQuarts" to 5.0))
        val f = ProposalForm.fromReceipt(p, 5000, ZoneOffset.UTC).copy(shop = "  ", isDiy = false)
        assertEquals("Mobil 1", f.details["oilBrand"])
        val e = ProposalForm.toEntry(f, "v1", listOf("p"), ZoneOffset.UTC)
        assertEquals("Mobil 1", e.details["oilBrand"])
        assertEquals("5W-30", e.details["oilGrade"])
        assertEquals(5.0, (e.details["quantityQuarts"] as Number).toDouble(), 0.0)
        assertTrue("server-only key leaked", "brand" !in e.details)
        assertEquals(listOf("p"), e.attachmentPaths)
        assertNull(e.shopName)
        assertNull(e.isDiy)
        assertEquals(Instant.parse("2026-03-04T12:00:00Z"), e.entryDate)
    }

    @Test
    fun requiredDetailFieldsBlockSave() {
        val f = ProposalForm.fromReceipt(proposal.copy(details = emptyMap()), 5000, ZoneOffset.UTC)
        val errors = ProposalForm.validate(f)
        assertEquals(setOf("detail:oilBrand", "detail:oilGrade", "detail:quantityQuarts"), errors.keys)
    }

    @Test
    fun switchingTypeReseedsFromServerFields() {
        val p = proposal.copy(entryType = EntryType.MAINTENANCE, details = mapOf("workItem" to "Cabin air filter", "nextDueOdometer" to 20000, "brand" to "X"))
        val f = ProposalForm.fromReceipt(p, 5000, ZoneOffset.UTC)
        assertEquals("cabin_air_filter", f.details["item"])
        assertEquals("20000", f.details["nextDueMileage"])
        val repair = ProposalForm.withType(f, EntryType.REPAIR)
        assertEquals("Cabin air filter", repair.details["title"])
        val e = ProposalForm.toEntry(repair, "v1", zone = ZoneOffset.UTC)
        assertEquals("Cabin air filter", e.details["title"])
        assertEquals(true, e.isResolved)
        assertTrue("item" !in e.details)
    }

    @Test
    fun fuelGetsTotalCostAndGrade() {
        val p = proposal.copy(entryType = EntryType.FUEL, details = emptyMap())
        val f = ProposalForm.fromReceipt(p, 5000, ZoneOffset.UTC).copy(details = mapOf("gallons" to "10", "pricePerGallon" to "4", "fuelGrade" to "premium_91"))
        val e = ProposalForm.toEntry(f, "v1", zone = ZoneOffset.UTC)
        assertEquals(12.5, e.details["totalCost"] as Double, 0.0)
        assertEquals("premium_91", e.details["fuelGrade"])
    }
}
