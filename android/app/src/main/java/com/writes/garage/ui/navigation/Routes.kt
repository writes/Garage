package com.writes.garage.ui.navigation

/** Route table for every screen. Tab roots are top-level; the rest are pushed on top. */
object Routes {
    const val DASHBOARD = "dashboard"
    const val LOG = "log"
    const val GARAGE = "garage"
    const val STATS = "stats"
    const val SETTINGS = "settings"

    const val ARG_VEHICLE_ID = "vehicleId"
    const val ARG_ENTRY_ID = "entryId"

    const val ENTRY_DETAIL = "log/{$ARG_VEHICLE_ID}/{$ARG_ENTRY_ID}"
    const val ENTRY_EDIT = "entry/edit?$ARG_VEHICLE_ID={$ARG_VEHICLE_ID}&$ARG_ENTRY_ID={$ARG_ENTRY_ID}"
    const val VEHICLE_EDIT = "garage/edit?$ARG_VEHICLE_ID={$ARG_VEHICLE_ID}"
    const val RECALLS = "garage/recalls/{$ARG_VEHICLE_ID}"
    const val RECEIPT = "receipt"
    const val VOICE = "voice"
    const val HANDOVER = "handover"
    const val PAYWALL = "settings/paywall"

    fun entryDetail(vehicleId: String, entryId: String) = "log/$vehicleId/$entryId"

    fun entryEdit(vehicleId: String? = null, entryId: String? = null): String {
        val params = listOfNotNull(
            vehicleId?.let { "$ARG_VEHICLE_ID=$it" },
            entryId?.let { "$ARG_ENTRY_ID=$it" },
        ).joinToString("&")
        return if (params.isEmpty()) "entry/edit" else "entry/edit?$params"
    }

    fun vehicleEdit(vehicleId: String? = null) =
        if (vehicleId == null) "garage/edit" else "garage/edit?$ARG_VEHICLE_ID=$vehicleId"

    fun recalls(vehicleId: String) = "garage/recalls/$vehicleId"
}
