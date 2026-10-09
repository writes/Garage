package com.writes.garage.core.domain

import com.writes.garage.core.model.DetailingType
import com.writes.garage.core.model.GalleryPhoto
import com.writes.garage.core.model.GallerySection
import com.writes.garage.core.model.PartCategory
import com.writes.garage.core.model.SparePart
import com.writes.garage.core.model.Warranty
import com.writes.garage.core.model.WarrantyType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

class RecordFormsTest {
    private val utc = ZoneOffset.UTC

    @Test
    fun warrantyBuildsAndRoundTrips() {
        val s = WarrantyFormState(
            type = WarrantyType.EXTENDED, provider = " Acme ", startDate = LocalDate.of(2026, 1, 1), endDate = LocalDate.of(2029, 1, 1),
            powertrainMonths = "60", powertrainMiles = "100,000".filter(Char::isDigit), deductible = "\$100.50", contractNumber = "C-1",
        )
        val (w, errors) = WarrantyForm.build(s, "v1", null, utc)
        assertTrue(errors.isEmpty())
        w!!
        assertEquals("Acme", w.providerName)
        assertEquals(60, w.powertrainTermMonths)
        assertEquals(100.5, w.deductible!!, 0.0)
        assertEquals(Instant.parse("2029-01-01T12:00:00Z"), w.expirationDate)
        val back = WarrantyForm.from(w, utc)
        assertEquals(s.endDate, back.endDate)
        assertEquals("60", back.powertrainMonths)
    }

    @Test
    fun warrantyRejectsBadNumbersAndBackwardsDates() {
        val (w, e) = WarrantyForm.build(
            WarrantyFormState(startDate = LocalDate.of(2026, 5, 1), endDate = LocalDate.of(2026, 4, 1), basicMonths = "x", deductible = "-1"),
            "v1", null, utc,
        )
        assertNull(w)
        assertEquals(setOf("basicMonths", "deductible", WarrantyForm.END_DATE), e.keys)
    }

    @Test
    fun warrantyIsActiveUntilItsEndDate() {
        val w = Warranty("w", "v1", startDate = Instant.parse("2025-01-01T00:00:00Z"), expirationDate = Instant.parse("2026-06-01T00:00:00Z"))
        assertTrue(w.isActive(Instant.parse("2026-01-01T00:00:00Z")))
        assertFalse(w.isActive(Instant.parse("2026-07-01T00:00:00Z")))
        assertFalse(Warranty("w", "v1", startDate = Instant.EPOCH).isActive(Instant.now())) // no end date = nothing to claim
    }

    @Test
    fun partRequiresNameAndQuantityAndValuesStockOnHand() {
        val (none, e) = PartForm.build(PartFormState(name = " ", quantity = ""), "v1", null, utc)
        assertNull(none)
        assertEquals(setOf(PartForm.NAME, PartForm.QUANTITY), e.keys)
        val (p, ok) = PartForm.build(PartFormState(name = "Brake pads", quantity = "2", unitCost = "\$45.5", category = PartCategory.BRAKES), "v1", null, utc)
        assertTrue(ok.isEmpty())
        assertEquals(2, p!!.quantity)
        assertEquals(45.5, p.unitCost!!, 0.0)
        val parts = listOf(p, SparePart("x", "v1", "Used up", quantity = 5, unitCost = 100.0, isConsumed = true))
        assertEquals(91.0, PartForm.onHandValue(parts), 0.0)
        assertEquals(listOf("Brake pads", "Used up"), PartForm.ordered(parts.reversed()).map { it.name })
    }

    @Test
    fun detailingRequiresTitleAndCapsLayers() {
        val (none, e) = DetailingForm.build(DetailingFormState(title = "", layers = "99"), "v1", null, utc)
        assertNull(none)
        assertEquals(setOf(DetailingForm.TITLE, DetailingForm.LAYERS), e.keys)
        val (r, ok) = DetailingForm.build(
            DetailingFormState(title = " Ceramic ", type = DetailingType.CERAMIC, layers = "2", cost = "1,200", warrantyExpiration = LocalDate.of(2031, 1, 1)),
            "v1", null, utc,
        )
        assertTrue(ok.isEmpty())
        assertEquals(2, r!!.layers)
        assertEquals(1200.0, r.cost!!, 0.0)
        assertNotNull(r.warrantyExpiration)
    }

    @Test
    fun galleryWheelFieldsAreDroppedForMainPhotos() {
        val base = GalleryPhoto("g", "v1", "t", storagePath = "p")
        val wheel = GalleryForm.apply(GalleryFormState(section = GallerySection.WHEEL, title = "Set A", wheelBrand = "BBS", tireCombo = "295/30"), base, utc)
        assertEquals("BBS", wheel.wheelBrand)
        assertEquals("295/30", wheel.tireComboAtTimeOfPhoto)
        val main = GalleryForm.apply(GalleryFormState(section = GallerySection.MAIN, title = "Front", wheelBrand = "BBS"), wheel, utc)
        assertNull(main.wheelBrand)
        assertEquals(mapOf(GalleryForm.TITLE to "Required"), GalleryForm.validate(GalleryFormState(title = " ")))
    }

    @Test
    fun galleryReorderSwapsNeighboursAndRenumbers() {
        fun p(id: String, order: Int) = GalleryPhoto(id, "v1", id, storagePath = id, displayOrder = order)
        val items = listOf(p("a", 4), p("b", 9), p("c", 12))
        assertEquals(listOf("b", "a", "c"), GalleryForm.reorder(items, 1, -1).map { it.id })
        assertEquals(listOf(0, 1, 2), GalleryForm.reorder(items, 1, -1).map { it.displayOrder })
        assertEquals(listOf("a", "b", "c"), GalleryForm.reorder(items, 0, -1).map { it.id }) // already first
        assertEquals(13, GalleryForm.nextOrder(items))
    }
}
