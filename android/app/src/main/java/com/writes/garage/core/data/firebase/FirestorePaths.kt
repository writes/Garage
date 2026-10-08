package com.writes.garage.core.data.firebase

/** Firestore collection names (mirror of iOS `FirestorePaths`). */
object FirestorePaths {
    const val USERS = "users"
    const val VEHICLES = "vehicles"
    const val ENTRIES = "entries"
    const val ATTACHMENTS = "attachments"
    const val REMINDERS = "reminders"
    const val GALLERY = "gallery"
    const val PARTS_INVENTORY = "parts_inventory"
    const val WARRANTIES = "warranties"
    const val WEAR_SNAPSHOTS = "wear_snapshots"
    const val RECALLS = "recalls"

    fun user(uid: String) = "$USERS/$uid"

    fun vehicle(vehicleId: String) = "$VEHICLES/$vehicleId"

    fun vehicleEntries(vehicleId: String) = "$VEHICLES/$vehicleId/$ENTRIES"

    fun vehicleReminders(vehicleId: String) = "$VEHICLES/$vehicleId/$REMINDERS"

    fun vehicleRecalls(vehicleId: String) = "$VEHICLES/$vehicleId/$RECALLS"
}

/** Cloud Storage paths; all live under `users/{uid}/` so the owner-only, <25 MB, image-or-PDF rules apply. */
object StoragePaths {
    fun entryAttachment(userId: String, vehicleId: String, entryId: String, filename: String) =
        "users/$userId/entry-attachments/$vehicleId/$entryId/$filename"

    /** Rules accept `image/…` and `application/pdf` only. */
    fun isAllowedContentType(contentType: String): Boolean =
        contentType == "application/pdf" || (contentType.startsWith("image/") && contentType.length > "image/".length)

    fun extensionFor(contentType: String): String = when (contentType.lowercase()) {
        "application/pdf" -> "pdf"
        "image/png" -> "png"
        "image/webp" -> "webp"
        "image/heic" -> "heic"
        else -> "jpg"
    }
}

/** Callable names and region (`Secrets.anthroProxyRegion` on iOS). */
object Callables {
    const val REGION = "us-central1"
    const val RECEIPT_QUICK_ADD = "receiptQuickAdd"
    const val CONFIRM_RECEIPT_SCAN = "confirmReceiptScan"
    const val RECEIPT_QUOTA_STATUS = "receiptQuotaStatus"
    const val RECONCILE_RECEIPT_CREDIT_PURCHASE = "reconcileReceiptCreditPurchase"
    const val VOICE_QUICK_ADD = "voiceQuickAdd"
    const val PARSE_OIL_ANALYSIS = "parseOilAnalysis"
    const val LOOKUP_RECALLS = "lookupRecalls"
    const val EXPERIMENT_CONFIG = "experimentConfig"
    const val DELETE_ACCOUNT = "deleteAccount"
    const val DELETE_VEHICLE = "deleteVehicle"
}
