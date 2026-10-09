package com.writes.garage.core.data.firebase

import com.writes.garage.core.model.DetailingRecord
import com.writes.garage.core.model.DetailingType
import com.writes.garage.core.model.GalleryPhoto
import com.writes.garage.core.model.GallerySection
import com.writes.garage.core.model.PartCategory
import com.writes.garage.core.model.PartCondition
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.RecallSource
import com.writes.garage.core.model.RecallStatus
import com.writes.garage.core.model.SparePart
import com.writes.garage.core.model.Warranty
import com.writes.garage.core.model.WarrantyType
import com.writes.garage.core.model.WearItemType
import com.writes.garage.core.model.WearSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class RecordMappersTest {
    private val t = Instant.parse("2026-03-01T12:00:00Z")

    @Test
    fun galleryRoundTripAndWireNames() {
        val p = GalleryPhoto("g1", "v1", "Front", "cap", "users/u/vehicles/v1/gallery/a.jpg", t, false, 3, GallerySection.WHEEL, "BBS", "LM", "19", "Gold", "295/30")
        val m = RecordMappers.galleryToMap(p)
        assertEquals("wheel", m["section"])
        assertEquals(false, m["includeInExport"])
        assertEquals(p, RecordMappers.galleryFromMap("g1", "v1", m))
        assertNull(RecordMappers.galleryFromMap("g", "v", mapOf("title" to "no path")))
    }

    @Test
    fun warrantyRoundTrip() {
        val w = Warranty(
            "w1", "v1", WarrantyType.EXTENDED, 48, 50_000, 72, 100_000, 84, 60, t, "Prov", "Plan", t, t, 120_000, 100.0, "C-1", "555",
            "desc", "excl", "doc", t, "n", t,
        )
        assertEquals(w, RecordMappers.warrantyFromMap("w1", "v1", RecordMappers.warrantyToMap(w)))
        assertNull(RecordMappers.warrantyFromMap("w", "v", mapOf("warrantyType" to "factory"))) // no startDate
    }

    @Test
    fun partRoundTripKeepsConsumedState() {
        val p = SparePart("p1", "v1", "Pads", PartCategory.BRAKES, "G-LOC", "R12", 4, 55.5, "Shop", t, "Shelf 2", PartCondition.USED, "ph", "rc", true, "e1", "n")
        assertEquals(p, RecordMappers.partFromMap("p1", "v1", RecordMappers.partToMap(p)))
        assertEquals(PartCategory.OTHER, RecordMappers.partFromMap("p", "v", mapOf("name" to "x", "category" to "weird"))!!.category)
    }

    @Test
    fun detailingRoundTripUsesTheSnakeCaseType() {
        val d = DetailingRecord("d1", "v1", t, DetailingType.PAINT_CORRECTION, "Correction", "Pro", "Polish", "2-stage", "hood", 2, t, "wash weekly", 900.0, "n", listOf("a"))
        val m = RecordMappers.detailingToMap(d)
        assertEquals("paint_correction", m["serviceType"])
        assertEquals(d, RecordMappers.detailingFromMap("d1", "v1", m))
    }

    @Test
    fun recallRoundTripAndTolerantReads() {
        val r = Recall("r1", "v1", "15V-1", "Fuel pump", "d", "FUEL", t, RecallStatus.COMPLETED, t, "Dealer", 82_000, RecallSource.NHTSA_API, "DO NOT DRIVE", t)
        assertEquals(r, RecordMappers.recallFromMap("r1", "v1", RecordMappers.recallToMap(r)))
        val loose = RecordMappers.recallFromMap("r", "v", mapOf("title" to "x", "status" to "nonsense"))!!
        assertEquals(RecallStatus.OUTSTANDING, loose.status)
        assertEquals(RecallSource.MANUAL, loose.recallSource)
    }

    @Test
    fun wearRoundTripSkipsUnknownItems() {
        val w = WearSnapshot("e1-front_tires", "v1", "e1", WearItemType.FRONT_TIRES, 50.0, "6/32", 10_000, t, t)
        val m = RecordMappers.wearToMap(w)
        assertEquals("front_tires", m["wearItem"])
        assertEquals(w, RecordMappers.wearFromMap(w.id, "v1", m))
        assertNull(RecordMappers.wearFromMap("x", "v", mapOf("wearItem" to "flux_capacitor", "recordedAt" to t)))
    }

    @Test
    fun optionalsAreExplicitNullsSoAMergeWriteCanClearThem() {
        val m = RecordMappers.partToMap(SparePart("p", "v", "Pads"))
        assertTrue(m.containsKey("brand") && m["brand"] == null)
        // createdAt is never nulled (server/system field)
        assertTrue(!RecordMappers.recallToMap(Recall("r", "v", title = "t")).containsKey("createdAt"))
    }
}
