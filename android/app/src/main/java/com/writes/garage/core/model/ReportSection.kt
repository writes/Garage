package com.writes.garage.core.model

/** The sections of the resale PDF dossier (iOS `ReportSection`, same order and titles). */
enum class ReportSection(val title: String) {
    VEHICLE_INFO("Vehicle info & specs"),
    PHOTO_GALLERY("Photo gallery"),
    MAINTENANCE_HISTORY("Maintenance history"),
    OIL_HISTORY("Oil changes & analysis"),
    TRACK_DAYS("Track day log"),
    TIRE_HISTORY("Tire history"),
    BRAKE_HISTORY("Brake history"),
    ALIGNMENT_RECORDS("Alignment records"),
    UPGRADES("Upgrade / modification log"),
    DETAILING("Detailing history"),
    SPARE_PARTS("Spare parts on hand"),
    WEAR_SUMMARY("Wear item summary"),
    COST_SUMMARY("Cost summary"),
    RECEIPTS("Receipts & invoices"),
    WARRANTIES("Warranty information"),
    RECALLS("Recall history");

    /** Entry types a per-type history section lists; empty for sections that are not entry histories. */
    val entryTypes: Set<EntryType>
        get() = when (this) {
            MAINTENANCE_HISTORY -> setOf(EntryType.MAINTENANCE, EntryType.REPAIR, EntryType.DME_REPORT)
            OIL_HISTORY -> setOf(EntryType.OIL_CHANGE, EntryType.OIL_CONSUMPTION, EntryType.OIL_ANALYSIS)
            TRACK_DAYS -> setOf(EntryType.TRACK_DAY)
            TIRE_HISTORY -> setOf(EntryType.TIRE)
            BRAKE_HISTORY -> setOf(EntryType.BRAKE)
            ALIGNMENT_RECORDS -> setOf(EntryType.ALIGNMENT)
            UPGRADES -> setOf(EntryType.UPGRADE)
            else -> emptySet()
        }
}
