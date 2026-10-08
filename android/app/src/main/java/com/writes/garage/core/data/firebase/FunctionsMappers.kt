package com.writes.garage.core.data.firebase

import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.RecallSource
import com.writes.garage.core.model.RecallStatus
import com.writes.garage.core.model.ReceiptProposal
import com.writes.garage.core.model.ReceiptQuota
import com.writes.garage.core.model.Vehicle
import com.writes.garage.core.model.VoiceProposal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/** Why a callable failed, in product terms (port of iOS `classifyReceiptError` / lookup error handling). */
class GatewayException(
    val kind: Kind,
    message: String,
    /** ISO-8601 reset time for [Kind.PRO_MONTH_EXHAUSTED], when the server supplied one. */
    val resetAt: String? = null,
    cause: Throwable? = null,
) : Exception(message, cause) {
    enum class Kind {
        NOT_A_RECEIPT,
        FREE_LIFETIME_EXHAUSTED,
        PRO_MONTH_EXHAUSTED,
        VIN_NOT_RECOGNISED,
        UNAUTHENTICATED,
        /** `permission-denied {reason: pro_required}`: route the user to the paywall. */
        PRO_REQUIRED,
        APP_CHECK_OR_PERMISSION,
        UNAVAILABLE,
        OTHER,
    }
}

/** Pure request builders and response parsers for the callables (shapes from the TypeScript files in `CloudFunctions/src/functions`). */
object FunctionsMappers {
    /** schemaVersion 2 opts into typed detail extraction; a v1 server ignores the key. */
    const val SCHEMA_VERSION = 2

    /** Max pages the server accepts is enforced server-side; we only guard "exactly one of images / pdf". */
    fun vehicleContext(v: Vehicle): Map<String, Any?> =
        mapOf("year" to v.year, "make" to v.make, "model" to v.model, "currentOdometer" to v.currentOdometer)

    fun receiptRequest(vehicle: Vehicle, imagesBase64: List<String>, pdfBase64: String?): Map<String, Any?> {
        val hasImages = imagesBase64.isNotEmpty()
        val hasPdf = !pdfBase64.isNullOrEmpty()
        require(hasImages != hasPdf) { "Provide exactly one of images or pdfBase64." }
        return buildMap {
            put("schemaVersion", SCHEMA_VERSION)
            if (hasImages) put("images", imagesBase64) else put("pdfBase64", pdfBase64)
            put("vehicle", vehicleContext(vehicle))
        }
    }

    fun voiceRequest(vehicle: Vehicle, transcript: String): Map<String, Any?> {
        require(transcript.isNotBlank()) { "Transcript is empty." }
        return mapOf("transcript" to transcript, "schemaVersion" to SCHEMA_VERSION, "vehicle" to vehicleContext(vehicle))
    }

    // ---------- responses ----------

    /** Typed-detail field names the server may add to a proposal (schemaVersion 2). */
    val TYPED_DETAIL_FIELDS = listOf(
        "workItem", "brand", "productModel", "oilGrade", "quantityQuarts", "serviceAction",
        "nextDueOdometer", "tireSizeFront", "tireSizeRear", "upgradeCategory",
    )

    private fun typedDetails(m: Map<String, Any?>): Map<String, Any?> =
        TYPED_DETAIL_FIELDS.mapNotNull { f -> m[f]?.let { f to it } }.toMap()

    /** `entryDate` is an ISO instant (or null): fall back to [now] so the form always has a date. */
    private fun proposalDate(v: Any?, now: Instant): Instant =
        FirestoreMappers.instant(v)
            ?: (v as? String)?.let { runCatching { LocalDate.parse(it).atStartOfDay(ZoneOffset.UTC).toInstant() }.getOrNull() }
            ?: now

    fun parseReceiptProposal(data: Map<String, Any?>, vehicleId: String, now: Instant): ReceiptProposal {
        val token = FirestoreMappers.string(data["token"])
            ?: throw GatewayException(GatewayException.Kind.OTHER, "Receipt response had no confirmation token.")
        return ReceiptProposal(
            token = token,
            vehicleId = vehicleId,
            entryType = EntryType.fromWire(FirestoreMappers.string(data["entryType"])) ?: EntryType.MAINTENANCE,
            entryDate = proposalDate(data["entryDate"], now),
            odometerReading = FirestoreMappers.int(data["odometerReading"]),
            cost = FirestoreMappers.double(data["cost"]),
            shopName = FirestoreMappers.string(data["shopName"]),
            notes = FirestoreMappers.string(data["notes"]),
            lineItems = (data["lineItems"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList(),
            isDiy = FirestoreMappers.bool(data["isDiy"]),
            details = typedDetails(data),
            quota = (data["quota"] as? Map<*, *>)?.let { parseQuota(FirestoreMappers.stringMap(it)) },
        )
    }

    fun parseVoiceProposal(data: Map<String, Any?>, vehicleId: String, transcript: String, now: Instant): VoiceProposal =
        VoiceProposal(
            transcript = transcript,
            vehicleId = vehicleId,
            entryType = EntryType.fromWire(FirestoreMappers.string(data["entryType"])) ?: EntryType.MAINTENANCE,
            entryDate = proposalDate(data["entryDate"], now),
            odometerReading = FirestoreMappers.int(data["odometerReading"]),
            cost = FirestoreMappers.double(data["cost"]),
            shopName = FirestoreMappers.string(data["shopName"]),
            notes = FirestoreMappers.string(data["notes"]),
            isDiy = FirestoreMappers.bool(data["isDiy"]),
            details = typedDetails(data),
        )

    /** Server `ReceiptQuotaSnapshot` -> [ReceiptQuota]. */
    fun parseQuota(m: Map<String, Any?>, transactionState: String? = null): ReceiptQuota = ReceiptQuota(
        remaining = FirestoreMappers.int(m["confirmedRemaining"]) ?: 0,
        monthlyLimit = FirestoreMappers.int(m["confirmedAllowance"]) ?: 0,
        creditBalance = FirestoreMappers.int(m["creditsRemaining"]) ?: 0,
        isPro = m["entitlement"] == "pro",
        scanRemaining = FirestoreMappers.int(m["scanRemaining"]),
        resetAt = FirestoreMappers.string(m["resetAt"]),
        transactionState = transactionState ?: FirestoreMappers.string(m["transactionState"]),
    )

    /** `reconcileReceiptCreditPurchase` -> `{transactionState, quota:{...}}`. */
    fun parseReconcile(data: Map<String, Any?>): ReceiptQuota =
        parseQuota(FirestoreMappers.stringMap(data["quota"]), FirestoreMappers.string(data["transactionState"]))

    /**
     * `lookupRecalls` -> stored-model recalls. Status starts OUTSTANDING: NHTSA says what a vehicle is
     * *subject to*, only the owner knows whether the work was done.
     */
    fun parseRecalls(data: Map<String, Any?>, vehicleId: String, now: Instant): List<Recall> =
        (data["recalls"] as? List<*>).orEmpty().mapNotNull { raw ->
            val r = (raw as? Map<*, *>)?.let { FirestoreMappers.stringMap(it) } ?: return@mapNotNull null
            val campaign = FirestoreMappers.string(r["campaignNumber"]) ?: return@mapNotNull null
            val component = FirestoreMappers.string(r["component"])?.takeIf { it.isNotBlank() }
            Recall(
                id = campaign,
                vehicleId = vehicleId,
                campaignNumber = campaign,
                title = component ?: "NHTSA recall $campaign",
                description = FirestoreMappers.string(r["summary"]),
                componentAffected = component,
                dateAnnounced = parseNhtsaDate(FirestoreMappers.string(r["reportReceivedDate"])) ?: null,
                status = RecallStatus.OUTSTANDING,
                recallSource = RecallSource.NHTSA_API,
                notes = recallNotes(
                    FirestoreMappers.string(r["remedy"]),
                    parkIt = r["parkIt"] == true,
                    parkOutside = r["parkOutside"] == true,
                ),
            )
        }

    /** Leads with the urgent advisory; a do-not-drive notice buried under remedy text is not read in time. */
    fun recallNotes(remedy: String?, parkIt: Boolean, parkOutside: Boolean): String? {
        val parts = mutableListOf<String>()
        if (parkIt) parts += "DO NOT DRIVE — NHTSA advises not driving this vehicle until repaired."
        if (parkOutside) parts += "PARK OUTSIDE — fire risk; keep away from structures until repaired."
        remedy?.trim()?.takeIf { it.isNotEmpty() }?.let { parts += it }
        return parts.takeIf { it.isNotEmpty() }?.joinToString("\n\n")
    }

    private val nhtsaDay = DateTimeFormatter.ofPattern("dd/MM/yyyy")

    /** NHTSA reports `dd/MM/yyyy`; tolerate ISO as well. Null when unparseable (never throws). */
    fun parseNhtsaDate(s: String?): Instant? {
        val t = s?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return runCatching { LocalDate.parse(t, nhtsaDay).atStartOfDay(ZoneOffset.UTC).toInstant() }.getOrNull()
            ?: runCatching { Instant.parse(t) }.getOrNull()
            ?: runCatching { LocalDate.parse(t).atStartOfDay(ZoneOffset.UTC).toInstant() }.getOrNull()
    }

    // ---------- errors ----------

    /**
     * Maps a callable failure (Functions error code NAME, e.g. "RESOURCE_EXHAUSTED", plus the server `details`
     * object) to a [GatewayException]. Deliberately narrow: only documented shapes get product routing.
     */
    fun classifyError(
        operation: String,
        codeName: String,
        message: String?,
        details: Any?,
        cause: Throwable? = null,
    ): GatewayException {
        val d = (details as? Map<*, *>)?.let { FirestoreMappers.stringMap(it) } ?: emptyMap()
        val reason = d["reason"] as? String
        val msg = message ?: "$operation failed ($codeName)"
        val kind = when {
            codeName == "FAILED_PRECONDITION" && reason == "not_a_receipt" -> GatewayException.Kind.NOT_A_RECEIPT
            codeName == "RESOURCE_EXHAUSTED" &&
                (reason == "receipt_scan_exhausted" || reason == "receipt_confirmed_exhausted") ->
                when (d["scope"]) {
                    "free_lifetime" -> GatewayException.Kind.FREE_LIFETIME_EXHAUSTED
                    "pro_month" -> GatewayException.Kind.PRO_MONTH_EXHAUSTED
                    else -> GatewayException.Kind.OTHER
                }
            codeName == "NOT_FOUND" && operation == Callables.LOOKUP_RECALLS -> GatewayException.Kind.VIN_NOT_RECOGNISED
            codeName == "UNAUTHENTICATED" -> GatewayException.Kind.UNAUTHENTICATED
            codeName == "PERMISSION_DENIED" && reason == "pro_required" -> GatewayException.Kind.PRO_REQUIRED
            codeName == "PERMISSION_DENIED" -> GatewayException.Kind.APP_CHECK_OR_PERMISSION
            codeName == "UNAVAILABLE" || codeName == "DEADLINE_EXCEEDED" -> GatewayException.Kind.UNAVAILABLE
            else -> GatewayException.Kind.OTHER
        }
        return GatewayException(kind, msg, d["resetAt"] as? String, cause)
    }
}
