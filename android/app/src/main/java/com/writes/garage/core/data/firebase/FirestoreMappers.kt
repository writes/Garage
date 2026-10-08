package com.writes.garage.core.data.firebase

import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.FuelType
import com.writes.garage.core.model.Reminder
import com.writes.garage.core.model.UserProfile
import com.writes.garage.core.model.Vehicle
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.Date

/**
 * Pure (Firebase-free) mapping between domain models and Firestore document maps, so field names and
 * shapes are unit-testable. Dates are [Instant]s here; [FirestoreValueCodec] converts them to/from
 * Firestore `Timestamp`s at the SDK boundary. Field names match the iOS `Codable` encoding exactly.
 *
 * `toMap` omits null optionals (iOS encodes nil as absent). With `forUpdate = true`, the *editable* optional
 * fields are kept as explicit `null`s so the repository can turn them into `FieldValue.delete()` and a user
 * can actually clear a field; server/system fields (`createdAt`, `deletedAt`, ...) are never nulled.
 */
object FirestoreMappers {
    // ---------- generic readers (tolerant: Firestore numbers arrive as Long/Double) ----------

    fun instant(v: Any?): Instant? = when (v) {
        is Instant -> v
        is Date -> v.toInstant()
        is Number -> Instant.ofEpochMilli(v.toLong())
        is String -> runCatching { Instant.parse(v) }.getOrNull()
        else -> null
    }

    fun int(v: Any?): Int? = (v as? Number)?.toInt() ?: (v as? String)?.toIntOrNull()

    fun double(v: Any?): Double? = (v as? Number)?.toDouble() ?: (v as? String)?.toDoubleOrNull()

    fun string(v: Any?): String? = v as? String

    fun bool(v: Any?): Boolean? = v as? Boolean

    @Suppress("UNCHECKED_CAST")
    fun stringMap(v: Any?): Map<String, Any?> =
        (v as? Map<*, *>)?.entries?.associate { it.key.toString() to it.value } ?: emptyMap()

    private fun MutableMap<String, Any?>.put(key: String, value: Any?, forUpdate: Boolean, editable: Boolean = true) {
        if (value != null) {
            this[key] = value
        } else if (forUpdate && editable) {
            this[key] = null
        }
    }

    // ---------- Vehicle ----------

    fun vehicleToMap(v: Vehicle, forUpdate: Boolean = false): Map<String, Any?> = LinkedHashMap<String, Any?>().apply {
        this["id"] = v.id
        this["userId"] = v.userId
        this["nickname"] = v.nickname
        this["make"] = v.make
        this["model"] = v.model
        this["year"] = v.year
        put("licensePlate", v.licensePlate, forUpdate)
        put("purchaseDate", v.purchaseDate, forUpdate)
        put("purchasePrice", v.purchasePrice, forUpdate)
        this["currentOdometer"] = v.currentOdometer
        put("odometerAtPurchase", v.odometerAtPurchase, forUpdate)
        put("engineOilType", v.engineOilType, forUpdate)
        put("tireSizeFront", v.tireSizeFront, forUpdate)
        put("tireSizeRear", v.tireSizeRear, forUpdate)
        put("fuelType", v.fuelType?.wire, forUpdate)
        put("vin", v.vin, forUpdate)
        put("color", v.color, forUpdate)
        put("weightClass", v.weightClass, forUpdate)
        put("notes", v.notes, forUpdate)
        this["displayOrder"] = v.displayOrder
        put("createdAt", v.createdAt, forUpdate, editable = false)
        put("updatedAt", v.updatedAt, forUpdate, editable = false)
        put("deletedAt", v.deletedAt, forUpdate, editable = false)
    }

    /** Null when required fields are missing/malformed (a corrupt doc must not crash the list). */
    fun vehicleFromMap(docId: String, m: Map<String, Any?>): Vehicle? {
        val userId = string(m["userId"]) ?: return null
        return Vehicle(
            id = docId,
            userId = userId,
            nickname = string(m["nickname"]).orEmpty(),
            make = string(m["make"]).orEmpty(),
            model = string(m["model"]).orEmpty(),
            year = int(m["year"]) ?: 0,
            licensePlate = string(m["licensePlate"]),
            purchaseDate = instant(m["purchaseDate"]),
            purchasePrice = double(m["purchasePrice"]),
            currentOdometer = int(m["currentOdometer"]) ?: 0,
            odometerAtPurchase = int(m["odometerAtPurchase"]),
            engineOilType = string(m["engineOilType"]),
            tireSizeFront = string(m["tireSizeFront"]),
            tireSizeRear = string(m["tireSizeRear"]),
            fuelType = FuelType.fromWire(string(m["fuelType"])),
            vin = string(m["vin"]),
            color = string(m["color"]),
            weightClass = string(m["weightClass"]),
            notes = string(m["notes"]),
            displayOrder = int(m["displayOrder"]) ?: 0,
            createdAt = instant(m["createdAt"]),
            updatedAt = instant(m["updatedAt"]),
            deletedAt = instant(m["deletedAt"]),
        )
    }

    // ---------- Counted vehicle create (RULES-1) ----------

    /**
     * The non-sentinel part of the `users/{uid}` write in the counted-create batch. The repository adds
     * `vehicleCount = FieldValue.increment(1)`. The rules require `lastVehicleOp == {id, op:"create"}` EXACTLY
     * (no extra keys), bound to the vehicle created in the same batch.
     */
    fun countedCreateUserFields(vehicleId: String): Map<String, Any?> =
        mapOf("lastVehicleOp" to mapOf("id" to vehicleId, "op" to "create"))

    /** Soft-delete tombstone written client-side before the `deleteVehicle` callable purges. */
    fun tombstoneFields(at: Instant): Map<String, Any?> = mapOf("deletedAt" to at)

    // ---------- Entry ----------

    fun entryToMap(e: Entry, forUpdate: Boolean = false): Map<String, Any?> = LinkedHashMap<String, Any?>().apply {
        this["id"] = e.id
        this["vehicleId"] = e.vehicleId
        this["userId"] = e.userId
        this["entryType"] = e.entryType.wire
        this["entryDate"] = e.entryDate
        this["odometerReading"] = e.odometerReading
        put("cost", e.cost, forUpdate)
        put("isDiy", e.isDiy, forUpdate)
        put("shopName", e.shopName, forUpdate)
        put("notes", e.notes, forUpdate)
        this["attachmentPaths"] = e.attachmentPaths
        put("isResolved", e.isResolved, forUpdate)
        this["details"] = e.details.filterValues { it != null }
        put("createdAt", e.createdAt, forUpdate, editable = false)
        put("updatedAt", e.updatedAt, forUpdate, editable = false)
    }

    /** Null for an unknown `entryType` (forward-compat: skip rather than crash). */
    fun entryFromMap(docId: String, vehicleIdFallback: String, m: Map<String, Any?>): Entry? {
        val type = EntryType.fromWire(string(m["entryType"])) ?: return null
        val date = instant(m["entryDate"]) ?: return null
        return Entry(
            id = docId,
            vehicleId = string(m["vehicleId"]) ?: vehicleIdFallback,
            userId = string(m["userId"]).orEmpty(),
            entryType = type,
            entryDate = date,
            odometerReading = int(m["odometerReading"]) ?: 0,
            cost = double(m["cost"]),
            isDiy = bool(m["isDiy"]),
            shopName = string(m["shopName"]),
            notes = string(m["notes"]),
            attachmentPaths = (m["attachmentPaths"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList(),
            isResolved = bool(m["isResolved"]),
            details = stringMap(m["details"]),
            createdAt = instant(m["createdAt"]),
            updatedAt = instant(m["updatedAt"]),
        )
    }

    // ---------- Reminder ----------

    fun reminderToMap(r: Reminder, forUpdate: Boolean = false): Map<String, Any?> = LinkedHashMap<String, Any?>().apply {
        this["id"] = r.id
        this["vehicleId"] = r.vehicleId
        this["title"] = r.title
        put("entryType", r.entryType?.wire, forUpdate)
        put("dueDate", r.dueDate, forUpdate)
        put("dueMileage", r.dueMileage, forUpdate)
        put("repeatIntervalMonths", r.repeatIntervalMonths, forUpdate)
        put("repeatIntervalMiles", r.repeatIntervalMiles, forUpdate)
        put("notes", r.notes, forUpdate)
        this["isProFeature"] = r.isProFeature
        put("createdAt", r.createdAt, forUpdate, editable = false)
        put("completedAt", r.completedAt, forUpdate)
    }

    fun reminderFromMap(docId: String, vehicleIdFallback: String, m: Map<String, Any?>): Reminder? {
        val title = string(m["title"]) ?: return null
        return Reminder(
            id = docId,
            vehicleId = string(m["vehicleId"]) ?: vehicleIdFallback,
            title = title,
            entryType = EntryType.fromWire(string(m["entryType"])),
            dueDate = instant(m["dueDate"]),
            dueMileage = int(m["dueMileage"]),
            repeatIntervalMonths = int(m["repeatIntervalMonths"]),
            repeatIntervalMiles = int(m["repeatIntervalMiles"]),
            notes = string(m["notes"]),
            isProFeature = bool(m["isProFeature"]) ?: false,
            createdAt = instant(m["createdAt"]),
            completedAt = instant(m["completedAt"]),
        )
    }

    // ---------- User profile (users/{uid}) ----------

    const val AI_CONSENT_FIELD = "aiConsentGrantedAt"

    /** iOS stores AI consent as an ISO-8601 *string* ("" = never granted / revoked). */
    fun encodeAiConsent(at: Instant?): String = at?.truncatedTo(ChronoUnit.SECONDS)?.toString().orEmpty()

    fun decodeAiConsent(v: Any?): Instant? = (v as? String)?.takeIf { it.isNotEmpty() }?.let { instant(it) } ?: (v as? Instant)

    fun profileFromMap(uid: String, email: String?, m: Map<String, Any?>): UserProfile = UserProfile(
        id = uid,
        email = email,
        name = string(m["name"])?.takeIf { it.isNotEmpty() },
        address = string(m["address"])?.takeIf { it.isNotEmpty() },
        phone = string(m["phone"])?.takeIf { it.isNotEmpty() },
        insuranceCompany = string(m["insuranceCompany"])?.takeIf { it.isNotEmpty() },
        policyNumber = string(m["policyNumber"])?.takeIf { it.isNotEmpty() },
        analyticsOptOut = bool(m["analyticsOptOut"]) ?: true,
        themeId = string(m["themeID"])?.takeIf { it.isNotEmpty() },
        aiConsentGrantedAt = decodeAiConsent(m[AI_CONSENT_FIELD]),
        createdAt = instant(m["createdAt"]),
        updatedAt = instant(m["updatedAt"]),
        serverIsPro = isProFromUserDoc(m),
    )

    /**
     * What the profile FORM saves (merge write): only the fields its screen edits. `themeID` and
     * `aiConsentGrantedAt` belong to other surfaces and must never be written from a possibly stale copy.
     */
    fun profileFormFields(p: UserProfile, now: Instant): Map<String, Any?> = mapOf(
        "name" to p.name.orEmpty(),
        "address" to p.address.orEmpty(),
        "phone" to p.phone.orEmpty(),
        "insuranceCompany" to p.insuranceCompany.orEmpty(),
        "policyNumber" to p.policyNumber.orEmpty(),
        "analyticsOptOut" to p.analyticsOptOut,
        "updatedAt" to now,
    )

    fun aiConsentFields(granted: Boolean, now: Instant): Map<String, Any?> = mapOf(
        AI_CONSENT_FIELD to encodeAiConsent(if (granted) now else null),
        "updatedAt" to now,
    )

    /** Server-written `users/{uid}.subscription` map -> is Pro? (mirrors the rules' `isProUser`). */
    fun isProFromUserDoc(m: Map<String, Any?>): Boolean {
        val sub = stringMap(m["subscription"])
        return sub["entitlement"] == "pro" && sub["isActive"] == true
    }
}
