package com.writes.garage.core.model

/** Mirrors iOS `EntryType`; [wire] is the Firestore snake_case value. */
enum class EntryType(val wire: String, val displayName: String) {
    OIL_CHANGE("oil_change", "Oil Change"),
    OIL_CONSUMPTION("oil_consumption", "Oil Consumption"),
    OIL_ANALYSIS("oil_analysis", "Oil Analysis"),
    FUEL("fuel", "Fuel Fill-up"),
    TIRE("tire", "Tire Service"),
    BRAKE("brake", "Brake Service"),
    ALIGNMENT("alignment", "Wheel Alignment"),
    MAINTENANCE("maintenance", "Maintenance"),
    REPAIR("repair", "Repair"),
    TRACK_DAY("track_day", "Track Day"),
    UPGRADE("upgrade", "Upgrade"),
    DME_REPORT("dme_report", "DME Report");

    companion object {
        fun fromWire(value: String?): EntryType? = entries.firstOrNull { it.wire == value }
    }
}
