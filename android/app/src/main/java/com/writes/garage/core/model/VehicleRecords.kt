package com.writes.garage.core.model

import java.time.Instant

/** Gallery section (`main` photos vs `wheel` records). Wire values match iOS `GallerySection`. */
enum class GallerySection(val wire: String, val label: String) {
    MAIN("main", "Photos"),
    WHEEL("wheel", "Wheels");

    companion object {
        fun fromWire(v: String?): GallerySection = entries.firstOrNull { it.wire == v } ?: MAIN
    }
}

/** `vehicles/{id}/gallery/{id}` (iOS `GalleryPhoto`). */
data class GalleryPhoto(
    val id: String,
    val vehicleId: String,
    val title: String,
    val caption: String? = null,
    val storagePath: String,
    val shotDate: Instant? = null,
    val includeInExport: Boolean = true,
    val displayOrder: Int = 0,
    val section: GallerySection = GallerySection.MAIN,
    val wheelBrand: String? = null,
    val wheelModel: String? = null,
    val wheelSize: String? = null,
    val wheelFinish: String? = null,
    val tireComboAtTimeOfPhoto: String? = null,
)

enum class WarrantyType(val wire: String, val label: String) {
    FACTORY("factory", "Factory"),
    EXTENDED("extended", "Extended");

    companion object {
        fun fromWire(v: String?): WarrantyType = entries.firstOrNull { it.wire == v } ?: FACTORY
    }
}

/** `vehicles/{id}/warranties/{id}` (iOS `Warranty`). */
data class Warranty(
    val id: String,
    val vehicleId: String,
    val warrantyType: WarrantyType = WarrantyType.FACTORY,
    val basicTermMonths: Int? = null,
    val basicTermMiles: Int? = null,
    val powertrainTermMonths: Int? = null,
    val powertrainTermMiles: Int? = null,
    val corrosionTermMonths: Int? = null,
    val roadsideTermMonths: Int? = null,
    val expirationDate: Instant? = null,
    val providerName: String? = null,
    val planName: String? = null,
    val coverageStart: Instant? = null,
    val coverageEnd: Instant? = null,
    val mileageLimit: Int? = null,
    val deductible: Double? = null,
    val contractNumber: String? = null,
    val providerPhone: String? = null,
    val coverageDescription: String? = null,
    val exclusions: String? = null,
    val documentPath: String? = null,
    val startDate: Instant,
    val notes: String? = null,
    val createdAt: Instant? = null,
) {
    /** The date coverage ends: explicit expiration, else the coverage window end. */
    val endsAt: Instant? get() = expirationDate ?: coverageEnd

    fun isActive(now: Instant): Boolean = endsAt?.let { it > now } ?: false
}

enum class PartCategory(val wire: String, val label: String) {
    ENGINE("engine", "Engine"),
    SUSPENSION("suspension", "Suspension"),
    BRAKES("brakes", "Brakes"),
    BODY("body", "Body"),
    INTERIOR("interior", "Interior"),
    WHEELS("wheels", "Wheels"),
    OTHER("other", "Other");

    companion object {
        fun fromWire(v: String?): PartCategory = entries.firstOrNull { it.wire == v } ?: OTHER
    }
}

enum class PartCondition(val wire: String, val label: String) {
    NEW("new", "New"),
    USED("used", "Used"),
    REFURBISHED("refurbished", "Refurbished");

    companion object {
        fun fromWire(v: String?): PartCondition = entries.firstOrNull { it.wire == v } ?: NEW
    }
}

/** `vehicles/{id}/parts_inventory/{id}` (iOS `SparePart`). */
data class SparePart(
    val id: String,
    val vehicleId: String,
    val name: String,
    val category: PartCategory = PartCategory.OTHER,
    val brand: String? = null,
    val partNumber: String? = null,
    val quantity: Int = 1,
    val unitCost: Double? = null,
    val wherePurchased: String? = null,
    val purchaseDate: Instant? = null,
    val storageLocation: String? = null,
    val condition: PartCondition = PartCondition.NEW,
    val photoStoragePath: String? = null,
    val receiptStoragePath: String? = null,
    val isConsumed: Boolean = false,
    val consumedAtEntryId: String? = null,
    val notes: String? = null,
)

enum class DetailingType(val wire: String, val label: String) {
    WASH("wash", "Wash"),
    PAINT_CORRECTION("paint_correction", "Paint correction"),
    CERAMIC("ceramic", "Ceramic coating"),
    PPF("ppf", "Paint protection film"),
    INTERIOR("interior", "Interior"),
    COSMETIC_IMPROVEMENT("cosmetic_improvement", "Cosmetic improvement");

    companion object {
        fun fromWire(v: String?): DetailingType = entries.firstOrNull { it.wire == v } ?: WASH
    }
}

/** `vehicles/{id}/detailing/{id}` (iOS `DetailingRecord`). */
data class DetailingRecord(
    val id: String,
    val vehicleId: String,
    val serviceDate: Instant,
    val serviceType: DetailingType = DetailingType.WASH,
    val title: String,
    val providerName: String? = null,
    val productName: String? = null,
    val correctionType: String? = null,
    val coverageArea: String? = null,
    val layers: Int? = null,
    val warrantyExpiration: Instant? = null,
    val maintenanceScheduleNotes: String? = null,
    val cost: Double? = null,
    val notes: String? = null,
    val attachmentPaths: List<String> = emptyList(),
)

enum class WearItemType(val wire: String, val label: String) {
    FRONT_BRAKE_PADS("front_brake_pads", "Front Brake Pads"),
    REAR_BRAKE_PADS("rear_brake_pads", "Rear Brake Pads"),
    FRONT_ROTORS("front_rotors", "Front Rotors"),
    REAR_ROTORS("rear_rotors", "Rear Rotors"),
    CLUTCH("clutch", "Clutch"),
    FRONT_TIRES("front_tires", "Front Tires"),
    REAR_TIRES("rear_tires", "Rear Tires");

    companion object {
        fun fromWire(v: String?): WearItemType? = entries.firstOrNull { it.wire == v }
    }
}

/** `vehicles/{id}/wear_snapshots/{id}` (iOS `WearSnapshot`). [valuePct] is percent remaining. */
data class WearSnapshot(
    val id: String,
    val vehicleId: String,
    val entryId: String? = null,
    val wearItem: WearItemType,
    val valuePct: Double? = null,
    val valueRaw: String? = null,
    val odometerReading: Int = 0,
    val recordedAt: Instant,
    val createdAt: Instant? = null,
)
