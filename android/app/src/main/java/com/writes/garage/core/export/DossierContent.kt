package com.writes.garage.core.export

import com.writes.garage.core.domain.Formatters
import com.writes.garage.core.domain.OwnershipCostCalculator
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.RecallStatus
import com.writes.garage.core.model.Vehicle
import java.time.Instant
import java.time.ZoneId

enum class DossierLineStyle { TITLE, HEADING, BODY, CAPTION }

data class DossierLine(val style: DossierLineStyle, val text: String)

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
            e.shopName?.takeIf { it.isNotBlank() }?.let { parts += it.trim() }
            if (e.isDiy == true) parts += "DIY"
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
