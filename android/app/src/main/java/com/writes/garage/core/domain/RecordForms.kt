package com.writes.garage.core.domain

import com.writes.garage.core.model.DetailingRecord
import com.writes.garage.core.model.DetailingType
import com.writes.garage.core.model.GalleryPhoto
import com.writes.garage.core.model.GallerySection
import com.writes.garage.core.model.PartCategory
import com.writes.garage.core.model.PartCondition
import com.writes.garage.core.model.SparePart
import com.writes.garage.core.model.Warranty
import com.writes.garage.core.model.WarrantyType
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Shared parsing for the record forms (blank = absent, junk = error). */
internal object FormParse {
    fun text(s: String): String? = s.trim().ifEmpty { null }

    /** Whole number in 0..max; null when blank. [errors] gets [key] when the text is present but invalid. */
    fun int(s: String, key: String, errors: MutableMap<String, String>, max: Int = 2_000_000, min: Int = 0): Int? {
        val t = s.trim().replace(",", "")
        if (t.isEmpty()) return null
        val v = t.toIntOrNull()
        if (v == null || v < min || v > max) {
            errors[key] = "Whole number from $min to $max"
            return null
        }
        return v
    }

    fun money(s: String, key: String, errors: MutableMap<String, String>): Double? {
        val t = s.filterNot { it == '$' || it == ',' || it.isWhitespace() }
        if (t.isEmpty()) return null
        val v = t.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 && it <= 10_000_000 }
        if (v == null) errors[key] = "Enter an amount, 0 or more"
        return v
    }

    fun instant(d: LocalDate?, zone: ZoneId): Instant? = d?.atTime(12, 0)?.atZone(zone)?.toInstant()

    fun date(i: Instant?, zone: ZoneId): LocalDate? = i?.atZone(zone)?.toLocalDate()
}

// ---------------------------------------------------------------- warranty

data class WarrantyFormState(
    val editingId: String? = null,
    val type: WarrantyType = WarrantyType.FACTORY,
    val provider: String = "",
    val plan: String = "",
    val startDate: LocalDate = LocalDate.now(),
    val endDate: LocalDate? = null,
    val basicMonths: String = "",
    val basicMiles: String = "",
    val powertrainMonths: String = "",
    val powertrainMiles: String = "",
    val corrosionMonths: String = "",
    val roadsideMonths: String = "",
    val mileageLimit: String = "",
    val deductible: String = "",
    val contractNumber: String = "",
    val providerPhone: String = "",
    val coverageDescription: String = "",
    val exclusions: String = "",
    val notes: String = "",
    val errors: Map<String, String> = emptyMap(),
)

object WarrantyForm {
    const val END_DATE = "endDate"

    fun from(w: Warranty, zone: ZoneId) = WarrantyFormState(
        editingId = w.id, type = w.warrantyType, provider = w.providerName.orEmpty(), plan = w.planName.orEmpty(),
        startDate = FormParse.date(w.coverageStart ?: w.startDate, zone) ?: LocalDate.now(),
        endDate = FormParse.date(w.endsAt, zone),
        basicMonths = w.basicTermMonths?.toString().orEmpty(), basicMiles = w.basicTermMiles?.toString().orEmpty(),
        powertrainMonths = w.powertrainTermMonths?.toString().orEmpty(), powertrainMiles = w.powertrainTermMiles?.toString().orEmpty(),
        corrosionMonths = w.corrosionTermMonths?.toString().orEmpty(), roadsideMonths = w.roadsideTermMonths?.toString().orEmpty(),
        mileageLimit = w.mileageLimit?.toString().orEmpty(), deductible = w.deductible?.let { "%.2f".format(it) }.orEmpty(),
        contractNumber = w.contractNumber.orEmpty(), providerPhone = w.providerPhone.orEmpty(),
        coverageDescription = w.coverageDescription.orEmpty(), exclusions = w.exclusions.orEmpty(), notes = w.notes.orEmpty(),
    )

    /** Either the validated warranty or the field errors. */
    fun build(s: WarrantyFormState, vehicleId: String, existing: Warranty?, zone: ZoneId): Pair<Warranty?, Map<String, String>> {
        val e = LinkedHashMap<String, String>()
        val bm = FormParse.int(s.basicMonths, "basicMonths", e, 600)
        val bmi = FormParse.int(s.basicMiles, "basicMiles", e)
        val pm = FormParse.int(s.powertrainMonths, "powertrainMonths", e, 600)
        val pmi = FormParse.int(s.powertrainMiles, "powertrainMiles", e)
        val cm = FormParse.int(s.corrosionMonths, "corrosionMonths", e, 600)
        val rm = FormParse.int(s.roadsideMonths, "roadsideMonths", e, 600)
        val limit = FormParse.int(s.mileageLimit, "mileageLimit", e)
        val ded = FormParse.money(s.deductible, "deductible", e)
        if (s.endDate != null && s.endDate.isBefore(s.startDate)) e[END_DATE] = "Ends before it starts"
        if (e.isNotEmpty()) return null to e
        val end = FormParse.instant(s.endDate, zone)
        val start = FormParse.instant(s.startDate, zone)!!
        val base = existing ?: Warranty(id = "", vehicleId = vehicleId, startDate = start)
        return base.copy(
            vehicleId = vehicleId, warrantyType = s.type, providerName = FormParse.text(s.provider), planName = FormParse.text(s.plan),
            startDate = start, coverageStart = start, coverageEnd = end, expirationDate = end,
            basicTermMonths = bm, basicTermMiles = bmi, powertrainTermMonths = pm, powertrainTermMiles = pmi,
            corrosionTermMonths = cm, roadsideTermMonths = rm, mileageLimit = limit, deductible = ded,
            contractNumber = FormParse.text(s.contractNumber), providerPhone = FormParse.text(s.providerPhone),
            coverageDescription = FormParse.text(s.coverageDescription), exclusions = FormParse.text(s.exclusions),
            notes = FormParse.text(s.notes),
        ) to emptyMap()
    }
}

// ---------------------------------------------------------------- spare parts

data class PartFormState(
    val editingId: String? = null,
    val name: String = "",
    val category: PartCategory = PartCategory.OTHER,
    val brand: String = "",
    val partNumber: String = "",
    val quantity: String = "1",
    val unitCost: String = "",
    val wherePurchased: String = "",
    val purchaseDate: LocalDate? = null,
    val storageLocation: String = "",
    val condition: PartCondition = PartCondition.NEW,
    val notes: String = "",
    val photoPath: String? = null,
    val receiptPath: String? = null,
    val isConsumed: Boolean = false,
    val consumedAtEntryId: String? = null,
    val errors: Map<String, String> = emptyMap(),
)

object PartForm {
    const val NAME = "name"
    const val QUANTITY = "quantity"
    const val UNIT_COST = "unitCost"

    fun from(p: SparePart, zone: ZoneId) = PartFormState(
        editingId = p.id, name = p.name, category = p.category, brand = p.brand.orEmpty(), partNumber = p.partNumber.orEmpty(),
        quantity = p.quantity.toString(), unitCost = p.unitCost?.let { "%.2f".format(it) }.orEmpty(),
        wherePurchased = p.wherePurchased.orEmpty(), purchaseDate = FormParse.date(p.purchaseDate, zone),
        storageLocation = p.storageLocation.orEmpty(), condition = p.condition, notes = p.notes.orEmpty(),
        photoPath = p.photoStoragePath, receiptPath = p.receiptStoragePath, isConsumed = p.isConsumed,
        consumedAtEntryId = p.consumedAtEntryId,
    )

    fun build(s: PartFormState, vehicleId: String, existing: SparePart?, zone: ZoneId): Pair<SparePart?, Map<String, String>> {
        val e = LinkedHashMap<String, String>()
        if (s.name.isBlank()) e[NAME] = "Required"
        val qty = FormParse.int(s.quantity, QUANTITY, e, max = 100_000, min = 0)
        if (s.quantity.isBlank()) e[QUANTITY] = "Required"
        val cost = FormParse.money(s.unitCost, UNIT_COST, e)
        if (e.isNotEmpty()) return null to e
        val base = existing ?: SparePart(id = "", vehicleId = vehicleId, name = "")
        return base.copy(
            vehicleId = vehicleId, name = s.name.trim(), category = s.category, brand = FormParse.text(s.brand),
            partNumber = FormParse.text(s.partNumber), quantity = qty ?: 1, unitCost = cost,
            wherePurchased = FormParse.text(s.wherePurchased), purchaseDate = FormParse.instant(s.purchaseDate, zone),
            storageLocation = FormParse.text(s.storageLocation), condition = s.condition,
            photoStoragePath = s.photoPath, receiptStoragePath = s.receiptPath, isConsumed = s.isConsumed,
            consumedAtEntryId = s.consumedAtEntryId, notes = FormParse.text(s.notes),
        ) to emptyMap()
    }

    /** Parts on hand, grouped for the list: not consumed first, then by name. */
    fun ordered(parts: List<SparePart>): List<SparePart> =
        parts.sortedWith(compareBy<SparePart> { it.isConsumed }.thenBy { it.name.lowercase() })

    /** Total value of parts still on hand (quantity x unit cost, where a cost is known). */
    fun onHandValue(parts: List<SparePart>): Double =
        parts.filter { !it.isConsumed }.sumOf { (it.unitCost ?: 0.0) * it.quantity }
}

// ---------------------------------------------------------------- detailing

data class DetailingFormState(
    val editingId: String? = null,
    val serviceDate: LocalDate = LocalDate.now(),
    val type: DetailingType = DetailingType.WASH,
    val title: String = "",
    val provider: String = "",
    val product: String = "",
    val correctionType: String = "",
    val coverageArea: String = "",
    val layers: String = "",
    val warrantyExpiration: LocalDate? = null,
    val maintenanceNotes: String = "",
    val cost: String = "",
    val notes: String = "",
    val attachmentPaths: List<String> = emptyList(),
    val errors: Map<String, String> = emptyMap(),
)

object DetailingForm {
    const val TITLE = "title"
    const val LAYERS = "layers"
    const val COST = "cost"

    fun from(r: DetailingRecord, zone: ZoneId) = DetailingFormState(
        editingId = r.id, serviceDate = FormParse.date(r.serviceDate, zone) ?: LocalDate.now(), type = r.serviceType, title = r.title,
        provider = r.providerName.orEmpty(), product = r.productName.orEmpty(), correctionType = r.correctionType.orEmpty(),
        coverageArea = r.coverageArea.orEmpty(), layers = r.layers?.toString().orEmpty(),
        warrantyExpiration = FormParse.date(r.warrantyExpiration, zone), maintenanceNotes = r.maintenanceScheduleNotes.orEmpty(),
        cost = r.cost?.let { "%.2f".format(it) }.orEmpty(), notes = r.notes.orEmpty(), attachmentPaths = r.attachmentPaths,
    )

    fun build(s: DetailingFormState, vehicleId: String, existing: DetailingRecord?, zone: ZoneId): Pair<DetailingRecord?, Map<String, String>> {
        val e = LinkedHashMap<String, String>()
        if (s.title.isBlank()) e[TITLE] = "Required"
        val layers = FormParse.int(s.layers, LAYERS, e, max = 20)
        val cost = FormParse.money(s.cost, COST, e)
        if (e.isNotEmpty()) return null to e
        val date = FormParse.instant(s.serviceDate, zone)!!
        val base = existing ?: DetailingRecord(id = "", vehicleId = vehicleId, serviceDate = date, title = "")
        return base.copy(
            vehicleId = vehicleId, serviceDate = date, serviceType = s.type, title = s.title.trim(),
            providerName = FormParse.text(s.provider), productName = FormParse.text(s.product),
            correctionType = FormParse.text(s.correctionType), coverageArea = FormParse.text(s.coverageArea), layers = layers,
            warrantyExpiration = FormParse.instant(s.warrantyExpiration, zone),
            maintenanceScheduleNotes = FormParse.text(s.maintenanceNotes), cost = cost, notes = FormParse.text(s.notes),
            attachmentPaths = s.attachmentPaths,
        ) to emptyMap()
    }
}

// ---------------------------------------------------------------- gallery

data class GalleryFormState(
    val editingId: String? = null,
    val section: GallerySection = GallerySection.MAIN,
    val title: String = "",
    val caption: String = "",
    val shotDate: LocalDate? = null,
    val includeInExport: Boolean = true,
    val wheelBrand: String = "",
    val wheelModel: String = "",
    val wheelSize: String = "",
    val wheelFinish: String = "",
    val tireCombo: String = "",
    val errors: Map<String, String> = emptyMap(),
)

object GalleryForm {
    const val TITLE = "title"

    fun from(p: GalleryPhoto, zone: ZoneId) = GalleryFormState(
        editingId = p.id, section = p.section, title = p.title, caption = p.caption.orEmpty(),
        shotDate = FormParse.date(p.shotDate, zone), includeInExport = p.includeInExport, wheelBrand = p.wheelBrand.orEmpty(),
        wheelModel = p.wheelModel.orEmpty(), wheelSize = p.wheelSize.orEmpty(), wheelFinish = p.wheelFinish.orEmpty(),
        tireCombo = p.tireComboAtTimeOfPhoto.orEmpty(),
    )

    fun validate(s: GalleryFormState): Map<String, String> =
        if (s.title.isBlank()) mapOf(TITLE to "Required") else emptyMap()

    /** Applies the form to [base] (a stored photo, or a fresh one carrying the just-uploaded [GalleryPhoto.storagePath]). */
    fun apply(s: GalleryFormState, base: GalleryPhoto, zone: ZoneId): GalleryPhoto {
        val wheel = s.section == GallerySection.WHEEL
        return base.copy(
            title = s.title.trim(), caption = FormParse.text(s.caption), shotDate = FormParse.instant(s.shotDate, zone),
            includeInExport = s.includeInExport, section = s.section,
            wheelBrand = if (wheel) FormParse.text(s.wheelBrand) else null, wheelModel = if (wheel) FormParse.text(s.wheelModel) else null,
            wheelSize = if (wheel) FormParse.text(s.wheelSize) else null, wheelFinish = if (wheel) FormParse.text(s.wheelFinish) else null,
            tireComboAtTimeOfPhoto = if (wheel) FormParse.text(s.tireCombo) else null,
        )
    }

    /** Swaps display order of the item at [index] with its neighbour ([delta] = -1 up, +1 down), renumbering 0..n-1. */
    fun reorder(items: List<GalleryPhoto>, index: Int, delta: Int): List<GalleryPhoto> {
        val sorted = items.sortedBy { it.displayOrder }.toMutableList()
        val target = index + delta
        if (index !in sorted.indices || target !in sorted.indices) return sorted.mapIndexed { i, p -> p.copy(displayOrder = i) }
        val tmp = sorted[index]
        sorted[index] = sorted[target]
        sorted[target] = tmp
        return sorted.mapIndexed { i, p -> p.copy(displayOrder = i) }
    }

    fun nextOrder(items: List<GalleryPhoto>): Int = (items.maxOfOrNull { it.displayOrder } ?: -1) + 1
}
