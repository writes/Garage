package com.writes.garage.core.export

import com.writes.garage.core.domain.Formatters
import com.writes.garage.core.domain.OwnershipCostCalculator
import com.writes.garage.core.model.DetailingRecord
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.GalleryPhoto
import com.writes.garage.core.model.ReportSection
import com.writes.garage.core.model.SparePart
import com.writes.garage.core.model.Warranty
import com.writes.garage.core.model.WearSnapshot
import com.writes.garage.core.domain.WearProjection
import java.time.LocalDate
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.RecallStatus
import com.writes.garage.core.model.Vehicle
import java.time.Instant
import java.time.ZoneId

enum class DossierLineStyle { TITLE, HEADING, BODY, CAPTION, IMAGE }

/** One rendered line. [image] (encoded JPEG/PNG bytes) is set only for [DossierLineStyle.IMAGE]; [text] is its caption. */
data class DossierLine(val style: DossierLineStyle, val text: String, val image: ByteArray? = null) {
    override fun equals(other: Any?): Boolean =
        other is DossierLine && style == other.style && text == other.text && (image?.contentEquals(other.image) ?: (other.image == null))

    override fun hashCode(): Int = 31 * (31 * style.hashCode() + text.hashCode()) + (image?.contentHashCode() ?: 0)
}

/** What the dossier is built from and which parts of it. Empty record lists simply produce no section. */
data class DossierRequest(
    val vehicle: Vehicle,
    val entries: List<Entry>,
    val sections: Set<ReportSection> = ReportSection.entries.toSet(),
    /** Inclusive local-date bounds applied to entries and detailing records; null = open-ended. */
    val startDate: LocalDate? = null,
    val endDate: LocalDate? = null,
    val recalls: List<Recall> = emptyList(),
    val warranties: List<Warranty> = emptyList(),
    val parts: List<SparePart> = emptyList(),
    val detailing: List<DetailingRecord> = emptyList(),
    val gallery: List<GalleryPhoto> = emptyList(),
    val wear: List<WearSnapshot> = emptyList(),
    /** Encoded image bytes by Storage path, for the gallery photos that could be fetched. */
    val photoBytes: Map<String, ByteArray> = emptyMap(),
)

/**
 * The text of the resale dossier, split from [PdfExporter] so the content (the product) is testable without
 * Android. Optional vehicle fields are omitted rather than printed as "unknown".
 */
object DossierContent {
    fun vehicleLines(vehicle: Vehicle, zone: ZoneId = ZoneId.systemDefault()): List<DossierLine> {
        val lines = mutableListOf(
            DossierLine(DossierLineStyle.TITLE, "${vehicle.year} ${vehicle.make} ${vehicle.model}".trim()),
        )
        if (vehicle.nickname.isNotBlank() && vehicle.nickname != vehicle.model) {
            lines += DossierLine(DossierLineStyle.CAPTION, vehicle.nickname)
        }
        lines += DossierLine(DossierLineStyle.BODY, "Odometer: ${Formatters.odometer(vehicle.currentOdometer)}")
        vehicle.vin?.trim()?.takeIf { it.isNotEmpty() }?.let { lines += DossierLine(DossierLineStyle.BODY, "VIN: $it") }
        val details = listOf(
            "Color" to vehicle.color, "Plate" to vehicle.licensePlate, "Fuel" to vehicle.fuelType?.displayName,
            "Engine oil" to vehicle.engineOilType, "Tires (front)" to vehicle.tireSizeFront,
            "Tires (rear)" to vehicle.tireSizeRear,
        )
        for ((label, value) in details) {
            value?.trim()?.takeIf { it.isNotEmpty() }?.let { lines += DossierLine(DossierLineStyle.BODY, "$label: $it") }
        }
        vehicle.purchaseDate?.let {
            val at = vehicle.odometerAtPurchase?.let { m -> " at ${Formatters.odometer(m)}" }.orEmpty()
            lines += DossierLine(DossierLineStyle.BODY, "Owned since ${Formatters.date(it, zone)}$at")
        }
        return lines
    }

    fun costSummaryLines(entries: List<Entry>, now: Instant): List<DossierLine> {
        val s = OwnershipCostCalculator.summary(entries, now) ?: return emptyList()
        val lines = mutableListOf(
            DossierLine(DossierLineStyle.HEADING, "Cost summary"),
            DossierLine(DossierLineStyle.BODY, "Total recorded spend: ${Formatters.currency(s.totalCost)}"),
        )
        if (s.milesCovered > 0) {
            lines += DossierLine(DossierLineStyle.BODY, "Miles covered by the records: ${Formatters.odometer(s.milesCovered)}")
        }
        s.costPerMile?.let { lines += DossierLine(DossierLineStyle.BODY, "Cost per mile: ${Formatters.costPerMile(it)}") }
        s.costPerMonth?.let {
            lines += DossierLine(DossierLineStyle.BODY, "Cost per month: ${Formatters.currency(it)}")
        }
        return lines
    }

    /** Newest first; every service states its odometer (mileage at service is the evidence). */
    fun serviceHistoryLines(entries: List<Entry>, zone: ZoneId = ZoneId.systemDefault()): List<DossierLine> {
        if (entries.isEmpty()) return emptyList()
        val lines = mutableListOf(DossierLine(DossierLineStyle.HEADING, "Service history"))
        for (e in entries.sortedByDescending { it.entryDate }) {
            val parts = mutableListOf(Formatters.date(e.entryDate, zone), e.entryType.displayName)
            if (e.odometerReading > 0) parts += Formatters.odometer(e.odometerReading)
            e.cost?.takeIf { it > 0 }?.let { parts += Formatters.currency(it) }
            // Who did the work is part of the record's credibility: DIY is stated only when no shop is named (iOS parity),
            // otherwise a paid dossier could contradict itself ("Hatch Motorsport | DIY").
            val shop = e.shopName?.trim()?.takeIf { it.isNotEmpty() }
            if (shop != null) parts += shop else if (e.isDiy == true) parts += "DIY"
            lines += DossierLine(DossierLineStyle.BODY, parts.joinToString("  |  "))
            e.notes?.trim()?.takeIf { it.isNotEmpty() }?.let { lines += DossierLine(DossierLineStyle.CAPTION, it) }
        }
        return lines
    }

    fun recallLines(recalls: List<Recall>, zone: ZoneId = ZoneId.systemDefault()): List<DossierLine> {
        if (recalls.isEmpty()) return emptyList()
        val lines = mutableListOf(DossierLine(DossierLineStyle.HEADING, "Recalls"))
        for (r in recalls) {
            val status = when (r.status) {
                RecallStatus.OUTSTANDING -> "Outstanding"
                RecallStatus.COMPLETED -> "Completed" + (r.completedDate?.let { " ${Formatters.date(it, zone)}" } ?: "")
                RecallStatus.NOT_APPLICABLE -> "Not applicable"
            }
            val id = r.campaignNumber?.let { "$it  |  " }.orEmpty()
            lines += DossierLine(DossierLineStyle.BODY, "$id${r.title}  |  $status")
        }
        return lines
    }

    // ---------- sectioned report (iOS ReportSection parity) ----------

    /** Entries inside the inclusive local-date range. */
    fun inRange(entries: List<Entry>, start: LocalDate?, end: LocalDate?, zone: ZoneId): List<Entry> =
        entries.filter { e ->
            val d = e.entryDate.atZone(zone).toLocalDate()
            (start == null || !d.isBefore(start)) && (end == null || !d.isAfter(end))
        }

    /** A per-type history (or the receipts list) under [heading]; empty when there is nothing to say. */
    fun entryHistoryLines(heading: String, entries: List<Entry>, zone: ZoneId): List<DossierLine> {
        if (entries.isEmpty()) return emptyList()
        return listOf(DossierLine(DossierLineStyle.HEADING, heading)) + serviceHistoryLines(entries, zone).drop(1)
    }

    fun receiptLines(entries: List<Entry>, zone: ZoneId): List<DossierLine> {
        val withFiles = entries.filter { it.attachmentPaths.isNotEmpty() }.sortedByDescending { it.entryDate }
        if (withFiles.isEmpty()) return emptyList()
        val lines = mutableListOf(DossierLine(DossierLineStyle.HEADING, ReportSection.RECEIPTS.title))
        for (e in withFiles) {
            val n = e.attachmentPaths.size
            lines += DossierLine(
                DossierLineStyle.BODY,
                "${Formatters.date(e.entryDate, zone)}  |  ${e.entryType.displayName}  |  $n document${if (n == 1) "" else "s"} on file" +
                    (e.cost?.takeIf { it > 0 }?.let { "  |  ${Formatters.currency(it)}" } ?: ""),
            )
        }
        return lines
    }

    fun warrantyLines(warranties: List<Warranty>, now: Instant, zone: ZoneId): List<DossierLine> {
        if (warranties.isEmpty()) return emptyList()
        val lines = mutableListOf(DossierLine(DossierLineStyle.HEADING, ReportSection.WARRANTIES.title))
        for (w in warranties.sortedByDescending { it.startDate }) {
            val status = if (w.isActive(now)) "Active" else "Expired"
            val name = listOfNotNull(w.warrantyType.label, w.providerName, w.planName).joinToString("  |  ")
            lines += DossierLine(DossierLineStyle.BODY, "$name  |  $status")
            val terms = listOfNotNull(
                term("Basic", w.basicTermMonths, w.basicTermMiles), term("Powertrain", w.powertrainTermMonths, w.powertrainTermMiles),
                term("Corrosion", w.corrosionTermMonths, null), term("Roadside", w.roadsideTermMonths, null),
                w.mileageLimit?.let { "Limit ${Formatters.odometer(it)}" }, w.deductible?.let { "Deductible ${Formatters.currency(it)}" },
            )
            if (terms.isNotEmpty()) lines += DossierLine(DossierLineStyle.CAPTION, terms.joinToString(", "))
            val dates = listOfNotNull(
                "From ${Formatters.date(w.coverageStart ?: w.startDate, zone)}", w.endsAt?.let { "to ${Formatters.date(it, zone)}" },
            )
            lines += DossierLine(DossierLineStyle.CAPTION, dates.joinToString(" "))
            w.contractNumber?.takeIf { it.isNotBlank() }?.let { lines += DossierLine(DossierLineStyle.CAPTION, "Contract $it") }
        }
        return lines
    }

    private fun term(label: String, months: Int?, miles: Int?): String? {
        if (months == null && miles == null) return null
        return "$label " + listOfNotNull(months?.let { "$it mo" }, miles?.let { "${Formatters.odometer(it)}" }).joinToString(" / ")
    }

    fun detailingLines(records: List<DetailingRecord>, zone: ZoneId): List<DossierLine> {
        if (records.isEmpty()) return emptyList()
        val lines = mutableListOf(DossierLine(DossierLineStyle.HEADING, ReportSection.DETAILING.title))
        for (r in records.sortedByDescending { it.serviceDate }) {
            val parts = mutableListOf(Formatters.date(r.serviceDate, zone), r.serviceType.label, r.title)
            r.providerName?.takeIf { it.isNotBlank() }?.let { parts += it }
            r.cost?.takeIf { it > 0 }?.let { parts += Formatters.currency(it) }
            lines += DossierLine(DossierLineStyle.BODY, parts.joinToString("  |  "))
            val detail = listOfNotNull(
                r.productName, r.coverageArea, r.layers?.let { "$it layer${if (it == 1) "" else "s"}" },
                r.warrantyExpiration?.let { "Warranty to ${Formatters.date(it, zone)}" },
            )
            if (detail.isNotEmpty()) lines += DossierLine(DossierLineStyle.CAPTION, detail.joinToString(", "))
            r.maintenanceScheduleNotes?.takeIf { it.isNotBlank() }?.let { lines += DossierLine(DossierLineStyle.CAPTION, it.trim()) }
        }
        return lines
    }

    fun sparePartLines(parts: List<SparePart>): List<DossierLine> {
        val onHand = parts.filter { !it.isConsumed }
        if (onHand.isEmpty()) return emptyList()
        val lines = mutableListOf(DossierLine(DossierLineStyle.HEADING, ReportSection.SPARE_PARTS.title))
        for (p in onHand.sortedBy { it.name.lowercase() }) {
            val bits = mutableListOf("${p.quantity} x ${p.name}", p.category.label, p.condition.label)
            p.brand?.takeIf { it.isNotBlank() }?.let { bits += it }
            p.partNumber?.takeIf { it.isNotBlank() }?.let { bits += "P/N $it" }
            lines += DossierLine(DossierLineStyle.BODY, bits.joinToString("  |  "))
            p.storageLocation?.takeIf { it.isNotBlank() }?.let { lines += DossierLine(DossierLineStyle.CAPTION, "Stored: $it") }
        }
        return lines
    }

    fun wearLines(snapshots: List<WearSnapshot>): List<DossierLine> {
        val items = WearProjection.latestItems(snapshots)
        if (items.isEmpty()) return emptyList()
        return listOf(DossierLine(DossierLineStyle.HEADING, ReportSection.WEAR_SUMMARY.title)) + items.map {
            DossierLine(DossierLineStyle.BODY, "${it.type.label}: ${it.rawValue ?: "${Math.round(it.percentage)}%"} remaining (${Math.round(it.percentage)}%)")
        }
    }

    fun galleryLines(photos: List<GalleryPhoto>, bytes: Map<String, ByteArray>): List<DossierLine> {
        val included = photos.filter { it.includeInExport }.sortedWith(compareBy({ it.section.ordinal }, { it.displayOrder }))
        if (included.isEmpty()) return emptyList()
        val lines = mutableListOf(DossierLine(DossierLineStyle.HEADING, ReportSection.PHOTO_GALLERY.title))
        for (p in included) {
            val caption = listOfNotNull(
                p.title.takeIf { it.isNotBlank() }, p.caption,
                listOfNotNull(p.wheelBrand, p.wheelModel, p.wheelSize, p.wheelFinish).joinToString(" ").takeIf { it.isNotBlank() },
            ).joinToString(" - ")
            val img = bytes[p.storagePath]
            lines += if (img != null) DossierLine(DossierLineStyle.IMAGE, caption, img) else DossierLine(DossierLineStyle.BODY, caption.ifEmpty { "Photo" })
        }
        return lines
    }

    /** The configurable dossier: [DossierRequest.sections] chooses what appears; entries and detailing honour the date range. */
    fun buildReport(
        r: DossierRequest,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): List<DossierLine> {
        val entries = inRange(r.entries, r.startDate, r.endDate, zone)
        val detailing = r.detailing.filter { d ->
            val day = d.serviceDate.atZone(zone).toLocalDate()
            (r.startDate == null || !day.isBefore(r.startDate)) && (r.endDate == null || !day.isAfter(r.endDate))
        }
        return buildList {
            // The title block always leads; "Vehicle info & specs" controls the spec lines under it.
            if (ReportSection.VEHICLE_INFO in r.sections) addAll(vehicleLines(r.vehicle, zone))
            else add(DossierLine(DossierLineStyle.TITLE, "${r.vehicle.year} ${r.vehicle.make} ${r.vehicle.model}".trim()))
            if (r.startDate != null || r.endDate != null) {
                add(
                    DossierLine(
                        DossierLineStyle.CAPTION,
                        "Records from ${r.startDate?.toString() ?: "the beginning"} to ${r.endDate?.toString() ?: "today"}",
                    ),
                )
            }
            for (section in ReportSection.entries) {
                if (section !in r.sections || section == ReportSection.VEHICLE_INFO) continue
                addAll(
                    when (section) {
                        ReportSection.PHOTO_GALLERY -> galleryLines(r.gallery, r.photoBytes)
                        ReportSection.COST_SUMMARY -> costSummaryLines(entries, now)
                        ReportSection.RECEIPTS -> receiptLines(entries, zone)
                        ReportSection.DETAILING -> detailingLines(detailing, zone)
                        ReportSection.SPARE_PARTS -> sparePartLines(r.parts)
                        ReportSection.WEAR_SUMMARY -> wearLines(r.wear)
                        ReportSection.WARRANTIES -> warrantyLines(r.warranties, now, zone)
                        ReportSection.RECALLS -> recallLines(r.recalls, zone).let { l ->
                            if (l.isEmpty()) l else listOf(DossierLine(DossierLineStyle.HEADING, section.title)) + l.drop(1)
                        }
                        else -> entryHistoryLines(section.title, entries.filter { it.entryType in section.entryTypes }, zone)
                    },
                )
            }
            add(DossierLine(DossierLineStyle.CAPTION, "Generated ${Formatters.date(now, zone)} by Garage. Records are owner-entered."))
        }
    }

    fun build(
        vehicle: Vehicle,
        entries: List<Entry>,
        recalls: List<Recall> = emptyList(),
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): List<DossierLine> = buildList {
        addAll(vehicleLines(vehicle, zone))
        costSummaryLines(entries, now).takeIf { it.isNotEmpty() }?.let { addAll(it) }
        addAll(serviceHistoryLines(entries, zone))
        addAll(recallLines(recalls, zone))
        add(DossierLine(DossierLineStyle.CAPTION, "Generated ${Formatters.date(now, zone)} by Garage. Records are owner-entered."))
    }
}
