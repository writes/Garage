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
import com.writes.garage.core.data.firebase.FirestoreMappers.bool
import com.writes.garage.core.data.firebase.FirestoreMappers.double
import com.writes.garage.core.data.firebase.FirestoreMappers.instant
import com.writes.garage.core.data.firebase.FirestoreMappers.int
import com.writes.garage.core.data.firebase.FirestoreMappers.string
import java.time.Instant

/**
 * Pure Firestore maps for the per-vehicle record collections. Field names match the iOS `Codable` encoding.
 * Every optional is written as an explicit null so a merge-write can clear it (the repository turns top-level
 * nulls into `FieldValue.delete()`); `createdAt` is never nulled.
 */
object RecordMappers {
    private fun base(id: String, vehicleId: String) = LinkedHashMap<String, Any?>().apply {
        this["id"] = id
        this["vehicleId"] = vehicleId
    }

    // ---- gallery ----
    fun galleryToMap(p: GalleryPhoto): Map<String, Any?> = base(p.id, p.vehicleId).apply {
        this["title"] = p.title
        this["caption"] = p.caption
        this["storagePath"] = p.storagePath
        this["shotDate"] = p.shotDate
        this["includeInExport"] = p.includeInExport
        this["displayOrder"] = p.displayOrder
        this["section"] = p.section.wire
        this["wheelBrand"] = p.wheelBrand
        this["wheelModel"] = p.wheelModel
        this["wheelSize"] = p.wheelSize
        this["wheelFinish"] = p.wheelFinish
        this["tireComboAtTimeOfPhoto"] = p.tireComboAtTimeOfPhoto
    }

    fun galleryFromMap(docId: String, vehicleId: String, m: Map<String, Any?>): GalleryPhoto? {
        val path = string(m["storagePath"]) ?: return null
        return GalleryPhoto(
            id = docId, vehicleId = string(m["vehicleId"]) ?: vehicleId, title = string(m["title"]).orEmpty(),
            caption = string(m["caption"]), storagePath = path, shotDate = instant(m["shotDate"]),
            includeInExport = bool(m["includeInExport"]) ?: true, displayOrder = int(m["displayOrder"]) ?: 0,
            section = GallerySection.fromWire(string(m["section"])), wheelBrand = string(m["wheelBrand"]),
            wheelModel = string(m["wheelModel"]), wheelSize = string(m["wheelSize"]),
            wheelFinish = string(m["wheelFinish"]), tireComboAtTimeOfPhoto = string(m["tireComboAtTimeOfPhoto"]),
        )
    }

    // ---- warranties ----
    fun warrantyToMap(w: Warranty): Map<String, Any?> = base(w.id, w.vehicleId).apply {
        this["warrantyType"] = w.warrantyType.wire
        this["basicTermMonths"] = w.basicTermMonths
        this["basicTermMiles"] = w.basicTermMiles
        this["powertrainTermMonths"] = w.powertrainTermMonths
        this["powertrainTermMiles"] = w.powertrainTermMiles
        this["corrosionTermMonths"] = w.corrosionTermMonths
        this["roadsideTermMonths"] = w.roadsideTermMonths
        this["expirationDate"] = w.expirationDate
        this["providerName"] = w.providerName
        this["planName"] = w.planName
        this["coverageStart"] = w.coverageStart
        this["coverageEnd"] = w.coverageEnd
        this["mileageLimit"] = w.mileageLimit
        this["deductible"] = w.deductible
        this["contractNumber"] = w.contractNumber
        this["providerPhone"] = w.providerPhone
        this["coverageDescription"] = w.coverageDescription
        this["exclusions"] = w.exclusions
        this["documentPath"] = w.documentPath
        this["startDate"] = w.startDate
        this["notes"] = w.notes
        if (w.createdAt != null) this["createdAt"] = w.createdAt
    }

    fun warrantyFromMap(docId: String, vehicleId: String, m: Map<String, Any?>): Warranty? {
        val start = instant(m["startDate"]) ?: return null
        return Warranty(
            id = docId, vehicleId = string(m["vehicleId"]) ?: vehicleId,
            warrantyType = WarrantyType.fromWire(string(m["warrantyType"])),
            basicTermMonths = int(m["basicTermMonths"]), basicTermMiles = int(m["basicTermMiles"]),
            powertrainTermMonths = int(m["powertrainTermMonths"]), powertrainTermMiles = int(m["powertrainTermMiles"]),
            corrosionTermMonths = int(m["corrosionTermMonths"]), roadsideTermMonths = int(m["roadsideTermMonths"]),
            expirationDate = instant(m["expirationDate"]), providerName = string(m["providerName"]),
            planName = string(m["planName"]), coverageStart = instant(m["coverageStart"]),
            coverageEnd = instant(m["coverageEnd"]), mileageLimit = int(m["mileageLimit"]),
            deductible = double(m["deductible"]), contractNumber = string(m["contractNumber"]),
            providerPhone = string(m["providerPhone"]), coverageDescription = string(m["coverageDescription"]),
            exclusions = string(m["exclusions"]), documentPath = string(m["documentPath"]), startDate = start,
            notes = string(m["notes"]), createdAt = instant(m["createdAt"]),
        )
    }

    // ---- spare parts ----
    fun partToMap(p: SparePart): Map<String, Any?> = base(p.id, p.vehicleId).apply {
        this["name"] = p.name
        this["category"] = p.category.wire
        this["brand"] = p.brand
        this["partNumber"] = p.partNumber
        this["quantity"] = p.quantity
        this["unitCost"] = p.unitCost
        this["wherePurchased"] = p.wherePurchased
        this["purchaseDate"] = p.purchaseDate
        this["storageLocation"] = p.storageLocation
        this["condition"] = p.condition.wire
        this["photoStoragePath"] = p.photoStoragePath
        this["receiptStoragePath"] = p.receiptStoragePath
        this["isConsumed"] = p.isConsumed
        this["consumedAtEntryId"] = p.consumedAtEntryId
        this["notes"] = p.notes
    }

    fun partFromMap(docId: String, vehicleId: String, m: Map<String, Any?>): SparePart? {
        val name = string(m["name"]) ?: return null
        return SparePart(
            id = docId, vehicleId = string(m["vehicleId"]) ?: vehicleId, name = name,
            category = PartCategory.fromWire(string(m["category"])), brand = string(m["brand"]),
            partNumber = string(m["partNumber"]), quantity = int(m["quantity"]) ?: 1,
            unitCost = double(m["unitCost"]), wherePurchased = string(m["wherePurchased"]),
            purchaseDate = instant(m["purchaseDate"]), storageLocation = string(m["storageLocation"]),
            condition = PartCondition.fromWire(string(m["condition"])), photoStoragePath = string(m["photoStoragePath"]),
            receiptStoragePath = string(m["receiptStoragePath"]), isConsumed = bool(m["isConsumed"]) ?: false,
            consumedAtEntryId = string(m["consumedAtEntryId"]), notes = string(m["notes"]),
        )
    }

    // ---- detailing ----
    fun detailingToMap(d: DetailingRecord): Map<String, Any?> = base(d.id, d.vehicleId).apply {
        this["serviceDate"] = d.serviceDate
        this["serviceType"] = d.serviceType.wire
        this["title"] = d.title
        this["providerName"] = d.providerName
        this["productName"] = d.productName
        this["correctionType"] = d.correctionType
        this["coverageArea"] = d.coverageArea
        this["layers"] = d.layers
        this["warrantyExpiration"] = d.warrantyExpiration
        this["maintenanceScheduleNotes"] = d.maintenanceScheduleNotes
        this["cost"] = d.cost
        this["notes"] = d.notes
        this["attachmentPaths"] = d.attachmentPaths
    }

    fun detailingFromMap(docId: String, vehicleId: String, m: Map<String, Any?>): DetailingRecord? {
        val date = instant(m["serviceDate"]) ?: return null
        return DetailingRecord(
            id = docId, vehicleId = string(m["vehicleId"]) ?: vehicleId, serviceDate = date,
            serviceType = DetailingType.fromWire(string(m["serviceType"])), title = string(m["title"]).orEmpty(),
            providerName = string(m["providerName"]), productName = string(m["productName"]),
            correctionType = string(m["correctionType"]), coverageArea = string(m["coverageArea"]),
            layers = int(m["layers"]), warrantyExpiration = instant(m["warrantyExpiration"]),
            maintenanceScheduleNotes = string(m["maintenanceScheduleNotes"]), cost = double(m["cost"]),
            notes = string(m["notes"]),
            attachmentPaths = (m["attachmentPaths"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList(),
        )
    }

    // ---- recalls ----
    fun recallToMap(r: Recall): Map<String, Any?> = base(r.id, r.vehicleId).apply {
        this["campaignNumber"] = r.campaignNumber
        this["title"] = r.title
        this["description"] = r.description
        this["componentAffected"] = r.componentAffected
        this["dateAnnounced"] = r.dateAnnounced
        this["status"] = r.status.wire
        this["completedDate"] = r.completedDate
        this["completedShop"] = r.completedShop
        this["completedOdometer"] = r.completedOdometer
        this["recallSource"] = r.recallSource.wire
        this["notes"] = r.notes
        if (r.createdAt != null) this["createdAt"] = r.createdAt
    }

    fun recallFromMap(docId: String, vehicleId: String, m: Map<String, Any?>): Recall? {
        val title = string(m["title"]) ?: return null
        return Recall(
            id = docId, vehicleId = string(m["vehicleId"]) ?: vehicleId, campaignNumber = string(m["campaignNumber"]),
            title = title, description = string(m["description"]), componentAffected = string(m["componentAffected"]),
            dateAnnounced = instant(m["dateAnnounced"]),
            status = RecallStatus.entries.firstOrNull { it.wire == string(m["status"]) } ?: RecallStatus.OUTSTANDING,
            completedDate = instant(m["completedDate"]), completedShop = string(m["completedShop"]),
            completedOdometer = int(m["completedOdometer"]),
            recallSource = RecallSource.entries.firstOrNull { it.wire == string(m["recallSource"]) } ?: RecallSource.MANUAL,
            notes = string(m["notes"]), createdAt = instant(m["createdAt"]),
        )
    }

    // ---- wear snapshots ----
    fun wearToMap(w: WearSnapshot): Map<String, Any?> = base(w.id, w.vehicleId).apply {
        this["entryId"] = w.entryId
        this["wearItem"] = w.wearItem.wire
        this["valuePct"] = w.valuePct
        this["valueRaw"] = w.valueRaw
        this["odometerReading"] = w.odometerReading
        this["recordedAt"] = w.recordedAt
        if (w.createdAt != null) this["createdAt"] = w.createdAt
    }

    fun wearFromMap(docId: String, vehicleId: String, m: Map<String, Any?>): WearSnapshot? {
        val item = WearItemType.fromWire(string(m["wearItem"])) ?: return null
        val at: Instant = instant(m["recordedAt"]) ?: return null
        return WearSnapshot(
            id = docId, vehicleId = string(m["vehicleId"]) ?: vehicleId, entryId = string(m["entryId"]),
            wearItem = item, valuePct = double(m["valuePct"]), valueRaw = string(m["valueRaw"]),
            odometerReading = int(m["odometerReading"]) ?: 0, recordedAt = at, createdAt = instant(m["createdAt"]),
        )
    }
}
