package com.writes.garage.core.export

import com.writes.garage.TestFixtures.NOW
import com.writes.garage.TestFixtures.entry
import com.writes.garage.TestFixtures.vehicle
import com.writes.garage.core.model.DetailingRecord
import com.writes.garage.core.model.DetailingType
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.GalleryPhoto
import com.writes.garage.core.model.GallerySection
import com.writes.garage.core.model.PartCategory
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.ReportSection
import com.writes.garage.core.model.SparePart
import com.writes.garage.core.model.Warranty
import com.writes.garage.core.model.WearItemType
import com.writes.garage.core.model.WearSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneOffset

class DossierReportTest {
    private val utc = ZoneOffset.UTC
    private val v = vehicle()

    private val entries = listOf(
        entry("oil", EntryType.OIL_CHANGE, daysAgo = 400, odo = 70_000, cost = 90.0),
        entry("brake", EntryType.BRAKE, daysAgo = 100, odo = 78_000, cost = 500.0),
        entry("tire", EntryType.TIRE, daysAgo = 50, odo = 80_000, cost = 800.0).copy(attachmentPaths = listOf("a.jpg", "b.pdf")),
        entry("fix", EntryType.REPAIR, daysAgo = 10, odo = 82_000, cost = 300.0, notes = "Water pump"),
        entry("fuel", EntryType.FUEL, daysAgo = 5, odo = 82_300, cost = 70.0),
    )

    private fun text(lines: List<DossierLine>) = lines.map { it.text }

    private fun report(sections: Set<ReportSection> = ReportSection.entries.toSet(), start: LocalDate? = null, end: LocalDate? = null, block: (DossierRequest) -> DossierRequest = { it }) =
        DossierContent.buildReport(block(DossierRequest(v, entries, sections, start, end)), NOW, utc)

    @Test
    fun sixteenSectionsInIosOrder() {
        assertEquals(16, ReportSection.entries.size)
        assertEquals("Vehicle info & specs", ReportSection.entries.first().title)
        assertEquals("Recall history", ReportSection.entries.last().title)
    }

    @Test
    fun perTypeSectionsListOnlyTheirOwnEntries() {
        val t = text(report())
        val brakeAt = t.indexOf("Brake history")
        assertTrue(brakeAt >= 0)
        assertTrue(t[brakeAt + 1].contains("Brake Service"))
        assertTrue(t.contains("Oil changes & analysis"))
        assertTrue(t.contains("Tire history"))
        assertTrue(t.contains("Maintenance history"))
        assertTrue(t.contains("Water pump"))
        assertFalse(t.contains("Alignment records")) // no such entries -> no empty section
        assertFalse(t.any { it.contains("Fuel") && it.contains("|") }) // fuel logs feed the cost summary only
    }

    @Test
    fun unselectedSectionsAreOmitted() {
        val t = text(report(setOf(ReportSection.BRAKE_HISTORY)))
        assertTrue(t.contains("Brake history"))
        assertFalse(t.contains("Tire history"))
        assertFalse(t.contains("Cost summary"))
        assertFalse(t.any { it.startsWith("Odometer:") }) // vehicle spec lines are the Vehicle info section
        assertEquals("2015 Audi SQ5", t.first()) // the title always leads
    }

    @Test
    fun dateRangeFiltersEntriesAndTheCostSummary() {
        val all = text(report(setOf(ReportSection.COST_SUMMARY, ReportSection.MAINTENANCE_HISTORY)))
        val ranged = text(report(setOf(ReportSection.COST_SUMMARY, ReportSection.MAINTENANCE_HISTORY), start = LocalDate.of(2026, 4, 1), end = null))
        assertTrue(all.any { it.contains("\$1,760.00") })
        assertTrue(ranged.first { it.startsWith("Records from") }.contains("2026-04-01"))
        assertTrue(ranged.any { it.contains("\$1,170.00") }) // 500 is older than the range? 100d ago = Feb: excluded
        assertFalse(ranged.any { it.contains("\$1,760.00") })
    }

    @Test
    fun receiptsSectionCountsDocumentsPerEntry() {
        val t = text(report(setOf(ReportSection.RECEIPTS)))
        assertTrue(t.contains("Receipts & invoices"))
        assertTrue(t.any { it.contains("Tire") && it.contains("2 documents on file") })
        assertFalse(text(report(setOf(ReportSection.RECEIPTS)) ).any { it.contains("Oil Change") })
    }

    @Test
    fun supplementSectionsRenderFromTheirRecords() {
        val r = DossierContent.buildReport(
            DossierRequest(
                v, entries,
                warranties = listOf(Warranty("w", "v1", providerName = "Acme", planName = "Plus", startDate = NOW.minusSeconds(86_400 * 30), expirationDate = NOW.plusSeconds(86_400 * 365), powertrainTermMonths = 60, powertrainTermMiles = 100_000, deductible = 100.0, contractNumber = "C-9")),
                parts = listOf(SparePart("p", "v1", "Brake pads", PartCategory.BRAKES, quantity = 2, partNumber = "BP-1", storageLocation = "Shelf"), SparePart("q", "v1", "Used up", isConsumed = true)),
                detailing = listOf(DetailingRecord("d", "v1", NOW.minusSeconds(86_400 * 5), DetailingType.CERAMIC, "Ceramic coat", "Pro Shop", "Gyeon", layers = 2, cost = 900.0)),
                wear = listOf(WearSnapshot("w1", "v1", "e", WearItemType.FRONT_BRAKE_PADS, 40.0, "40%", 1, NOW)),
                recalls = listOf(Recall("r", "v1", "15V-1", "Fuel pump")),
            ),
            NOW, utc,
        )
        val t = text(r)
        assertTrue(t.contains("Warranty information"))
        assertTrue(t.any { it.contains("Extended".takeIf { false } ?: "Factory") && it.contains("Acme") && it.contains("Active") })
        assertTrue(t.any { it.contains("Powertrain 60 mo") })
        assertTrue(t.contains("Contract C-9"))
        assertTrue(t.contains("Spare parts on hand"))
        assertTrue(t.any { it.startsWith("2 x Brake pads") && it.contains("P/N BP-1") })
        assertFalse(t.any { it.contains("Used up") }) // consumed parts are not "on hand"
        assertTrue(t.contains("Detailing history"))
        assertTrue(t.any { it.contains("Ceramic coating") && it.contains("Ceramic coat") })
        assertTrue(t.contains("Wear item summary"))
        assertTrue(t.any { it.startsWith("Front Brake Pads") })
        assertTrue(t.contains("Recall history"))
    }

    @Test
    fun galleryEmbedsFetchedPhotosAndFallsBackToACaption() {
        val photos = listOf(
            GalleryPhoto("a", "v1", "Front", storagePath = "pa", displayOrder = 1),
            GalleryPhoto("b", "v1", "Hidden", storagePath = "pb", includeInExport = false),
            GalleryPhoto("c", "v1", "Set A", storagePath = "pc", section = GallerySection.WHEEL, wheelBrand = "BBS", wheelSize = "19"),
        )
        val lines = DossierContent.galleryLines(photos, mapOf("pa" to byteArrayOf(1, 2, 3)))
        assertEquals("Photo gallery", lines.first().text)
        val front = lines.first { it.text.startsWith("Front") }
        assertEquals(DossierLineStyle.IMAGE, front.style)
        assertNotNull(front.image)
        assertTrue(lines.none { it.text.contains("Hidden") }) // excluded from export
        val wheel = lines.first { it.text.contains("Set A") }
        assertEquals(DossierLineStyle.BODY, wheel.style) // no bytes fetched -> caption only
        assertTrue(wheel.text.contains("BBS 19"))
    }

    @Test
    fun legacyBuildIsUnchanged() {
        val t = text(DossierContent.build(v, entries, now = NOW, zone = utc))
        assertTrue(t.contains("Service history"))
    }
}
