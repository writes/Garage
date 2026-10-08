package com.writes.garage.core.data.firebase

import com.writes.garage.TestFixtures.NOW
import com.writes.garage.TestFixtures.vehicle
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.RecallSource
import com.writes.garage.core.model.RecallStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class FunctionsMappersTest {
    @Test
    fun receiptRequestShape() {
        val req = FunctionsMappers.receiptRequest(vehicle(), listOf("aaa", "bbb"), null)
        assertEquals(2, req["schemaVersion"])
        assertEquals(listOf("aaa", "bbb"), req["images"])
        assertFalse(req.containsKey("pdfBase64"))
        assertEquals(
            mapOf("year" to 2015, "make" to "Audi", "model" to "SQ5", "currentOdometer" to 82_440),
            req["vehicle"],
        )
        val pdf = FunctionsMappers.receiptRequest(vehicle(), emptyList(), "JVBER")
        assertEquals("JVBER", pdf["pdfBase64"])
        assertFalse(pdf.containsKey("images"))
    }

    @Test
    fun receiptRequestRequiresExactlyOneSource() {
        assertThrows(IllegalArgumentException::class.java) { FunctionsMappers.receiptRequest(vehicle(), emptyList(), null) }
        assertThrows(IllegalArgumentException::class.java) { FunctionsMappers.receiptRequest(vehicle(), listOf("a"), "p") }
    }

    @Test
    fun voiceRequestShape() {
        val req = FunctionsMappers.voiceRequest(vehicle(), "changed the oil for 80 bucks")
        assertEquals("changed the oil for 80 bucks", req["transcript"])
        assertEquals(2, req["schemaVersion"])
        assertThrows(IllegalArgumentException::class.java) { FunctionsMappers.voiceRequest(vehicle(), "  ") }
    }

    private val quotaJson = mapOf(
        "entitlement" to "pro", "scanRemaining" to 70L, "scanCeiling" to 80L, "confirmedRemaining" to 18L,
        "confirmedAllowance" to 20L, "resetAt" to "2026-07-01T00:00:00.000Z", "creditsRemaining" to 3L,
        "creditsScanRemaining" to 5L, "creditsGranted" to 10L, "creditsDeficit" to 0L,
    )

    @Test
    fun receiptProposalParsesServerEnvelope() {
        val data = mapOf(
            "token" to "11111111-1111-4111-8111-111111111111",
            "entryType" to "oil_change", "odometerReading" to 42_180L, "cost" to 89.95, "shopName" to "Joe's",
            "isDiy" to false, "entryDate" to "2026-05-30T00:00:00.000Z", "notes" to null,
            "lineItems" to listOf("Oil", "Filter"), "quota" to quotaJson, "proposalSchemaVersion" to 2L,
            "brand" to "Mobil 1", "oilGrade" to "5W-30", "quantityQuarts" to 5.0, "workItem" to null,
        )
        val p = FunctionsMappers.parseReceiptProposal(data, "v1", NOW)
        assertEquals(EntryType.OIL_CHANGE, p.entryType)
        assertEquals(42_180, p.odometerReading)
        assertEquals(Instant.parse("2026-05-30T00:00:00Z"), p.entryDate)
        assertEquals(listOf("Oil", "Filter"), p.lineItems)
        assertEquals(mapOf("brand" to "Mobil 1", "oilGrade" to "5W-30", "quantityQuarts" to 5.0), p.details)
        assertEquals(false, p.isDiy)
        assertEquals(18, p.quota!!.remaining)
        assertEquals(20, p.quota!!.monthlyLimit)
        assertEquals(3, p.quota!!.creditBalance)
        assertTrue(p.quota!!.isPro)
        assertEquals("v1", p.vehicleId)
    }

    @Test
    fun proposalFallsBackSafely() {
        val p = FunctionsMappers.parseReceiptProposal(
            mapOf("token" to "t", "entryType" to "hovercraft", "entryDate" to null), "v1", NOW,
        )
        assertEquals(EntryType.MAINTENANCE, p.entryType) // out-of-vocabulary -> maintenance, like the server
        assertEquals(NOW, p.entryDate)
        assertNull(p.quota)
        val dateOnly = FunctionsMappers.parseVoiceProposal(mapOf("entryDate" to "2026-05-01"), "v1", "hi", NOW)
        assertEquals(Instant.parse("2026-05-01T00:00:00Z"), dateOnly.entryDate)
        assertEquals("hi", dateOnly.transcript)
        assertEquals(
            GatewayException.Kind.OTHER,
            assertThrows(GatewayException::class.java) { FunctionsMappers.parseReceiptProposal(emptyMap(), "v1", NOW) }.kind,
        )
    }

    @Test
    fun voiceProposalParses() {
        val p = FunctionsMappers.parseVoiceProposal(
            mapOf("entryType" to "tire", "cost" to 900L, "tireSizeFront" to "255/35R19", "proposalSchemaVersion" to 2L),
            "v1", "new tires nine hundred", NOW,
        )
        assertEquals(EntryType.TIRE, p.entryType)
        assertEquals(900.0, p.cost!!, 0.0)
        assertEquals(mapOf("tireSizeFront" to "255/35R19"), p.details)
    }

    @Test
    fun reconcileFoldsTransactionStateIntoQuota() {
        val q = FunctionsMappers.parseReconcile(mapOf("transactionState" to "granted", "quota" to quotaJson))
        assertEquals("granted", q.transactionState)
        assertEquals(3, q.creditBalance)
        assertNull(FunctionsMappers.parseQuota(quotaJson).transactionState)
    }

    @Test
    fun recallsMapToOutstandingNhtsaRecalls() {
        val data = mapOf(
            "make" to "AUDI", "model" to "SQ5", "modelYear" to "2015",
            "recalls" to listOf(
                mapOf(
                    "campaignNumber" to "24V123", "component" to "AIR BAGS", "summary" to "May not deploy.",
                    "remedy" to "Dealer will replace.", "reportReceivedDate" to "15/03/2024", "parkIt" to true, "parkOutside" to false,
                ),
                mapOf("campaignNumber" to "24V999", "component" to null, "summary" to null, "remedy" to null, "parkIt" to false),
                mapOf("component" to "no campaign number cannot be acted on"),
            ),
        )
        val recalls = FunctionsMappers.parseRecalls(data, "v1", NOW)
        assertEquals(2, recalls.size)
        val first = recalls[0]
        assertEquals("24V123", first.id)
        assertEquals(RecallStatus.OUTSTANDING, first.status)
        assertEquals(RecallSource.NHTSA_API, first.recallSource)
        assertEquals("AIR BAGS", first.title)
        assertEquals(Instant.parse("2024-03-15T00:00:00Z"), first.dateAnnounced)
        assertTrue(first.notes!!.startsWith("DO NOT DRIVE"))
        assertTrue(first.notes!!.endsWith("Dealer will replace."))
        assertEquals("NHTSA recall 24V999", recalls[1].title)
        assertNull(recalls[1].notes)
    }

    @Test
    fun nhtsaDateParsing() {
        assertEquals(Instant.parse("2024-03-15T00:00:00Z"), FunctionsMappers.parseNhtsaDate("15/03/2024"))
        assertEquals(Instant.parse("2024-03-15T00:00:00Z"), FunctionsMappers.parseNhtsaDate("2024-03-15"))
        assertNull(FunctionsMappers.parseNhtsaDate("garbage"))
        assertNull(FunctionsMappers.parseNhtsaDate(null))
    }

    @Test
    fun errorClassificationIsNarrow() {
        fun kind(code: String, details: Any?, op: String = Callables.RECEIPT_QUICK_ADD) =
            FunctionsMappers.classifyError(op, code, "m", details).kind

        assertEquals(GatewayException.Kind.NOT_A_RECEIPT, kind("FAILED_PRECONDITION", mapOf("reason" to "not_a_receipt")))
        assertEquals(
            GatewayException.Kind.FREE_LIFETIME_EXHAUSTED,
            kind("RESOURCE_EXHAUSTED", mapOf("reason" to "receipt_scan_exhausted", "scope" to "free_lifetime")),
        )
        val pro = FunctionsMappers.classifyError(
            Callables.RECEIPT_QUICK_ADD, "RESOURCE_EXHAUSTED", "m",
            mapOf("reason" to "receipt_confirmed_exhausted", "scope" to "pro_month", "resetAt" to "2026-07-01T00:00:00Z"),
        )
        assertEquals(GatewayException.Kind.PRO_MONTH_EXHAUSTED, pro.kind)
        assertEquals("2026-07-01T00:00:00Z", pro.resetAt)
        // unknown scope / shapes never masquerade as a known outcome
        assertEquals(GatewayException.Kind.OTHER, kind("RESOURCE_EXHAUSTED", mapOf("reason" to "receipt_scan_exhausted", "scope" to "mystery")))
        assertEquals(GatewayException.Kind.OTHER, kind("RESOURCE_EXHAUSTED", "oops"))
        assertEquals(GatewayException.Kind.VIN_NOT_RECOGNISED, kind("NOT_FOUND", null, Callables.LOOKUP_RECALLS))
        assertEquals(GatewayException.Kind.OTHER, kind("NOT_FOUND", null))
        assertEquals(GatewayException.Kind.UNAUTHENTICATED, kind("UNAUTHENTICATED", null))
        assertEquals(GatewayException.Kind.UNAVAILABLE, kind("DEADLINE_EXCEEDED", null))
        assertEquals(GatewayException.Kind.UNAVAILABLE, kind("UNAVAILABLE", null))
    }

    @Test
    fun permissionDeniedSplitsProRequiredFromEverythingElse() {
        fun kind(details: Any?) = FunctionsMappers.classifyError(Callables.VOICE_QUICK_ADD, "PERMISSION_DENIED", "m", details).kind
        assertEquals(GatewayException.Kind.PRO_REQUIRED, kind(mapOf("reason" to "pro_required")))
        // No details / another reason / wrong shape: App Check or plain permission, never a paywall nudge.
        assertEquals(GatewayException.Kind.APP_CHECK_OR_PERMISSION, kind(null))
        assertEquals(GatewayException.Kind.APP_CHECK_OR_PERMISSION, kind(mapOf("reason" to "app_check")))
        assertEquals(GatewayException.Kind.APP_CHECK_OR_PERMISSION, kind("pro_required"))
        assertEquals(GatewayException.Kind.APP_CHECK_OR_PERMISSION, kind(emptyMap<String, Any>()))
    }

    @Test
    fun confirmedExhaustedRoutesByScopeLikeScanExhausted() {
        fun kind(reason: String, scope: String?) = FunctionsMappers.classifyError(
            Callables.RECEIPT_QUICK_ADD, "RESOURCE_EXHAUSTED", "m", buildMap { put("reason", reason); if (scope != null) put("scope", scope) },
        ).kind
        assertEquals(GatewayException.Kind.FREE_LIFETIME_EXHAUSTED, kind("receipt_confirmed_exhausted", "free_lifetime"))
        assertEquals(GatewayException.Kind.PRO_MONTH_EXHAUSTED, kind("receipt_confirmed_exhausted", "pro_month"))
        assertEquals(GatewayException.Kind.OTHER, kind("receipt_confirmed_exhausted", null))
        assertEquals(GatewayException.Kind.OTHER, kind("something_else", "free_lifetime"))
    }

    @Test
    fun failedPreconditionWithAnotherReasonIsNotAReceiptRejection() {
        fun kind(details: Any?) = FunctionsMappers.classifyError(Callables.RECEIPT_QUICK_ADD, "FAILED_PRECONDITION", "m", details).kind
        assertEquals(GatewayException.Kind.OTHER, kind(mapOf("reason" to "ai_consent_required")))
        assertEquals(GatewayException.Kind.OTHER, kind(null))
    }

    @Test
    fun notFoundOnlyMeansUnrecognisedVinForTheRecallLookup() {
        fun kind(op: String) = FunctionsMappers.classifyError(op, "NOT_FOUND", "m", null).kind
        assertEquals(GatewayException.Kind.VIN_NOT_RECOGNISED, kind(Callables.LOOKUP_RECALLS))
        assertEquals(GatewayException.Kind.OTHER, kind(Callables.RECEIPT_QUICK_ADD))
    }

    @Test
    fun messageFallsBackToTheOperationAndCodeAndKeepsResetAt() {
        val e = FunctionsMappers.classifyError("op", "INTERNAL", null, null)
        assertEquals("op failed (INTERNAL)", e.message)
        val r = FunctionsMappers.classifyError(
            Callables.RECEIPT_QUICK_ADD, "RESOURCE_EXHAUSTED", "m", mapOf("reason" to "receipt_scan_exhausted", "scope" to "pro_month", "resetAt" to "2026-08-01T00:00:00Z"),
        )
        assertEquals("2026-08-01T00:00:00Z", r.resetAt)
        assertNull(FunctionsMappers.classifyError("op", "INTERNAL", "m", null).resetAt)
    }
}
