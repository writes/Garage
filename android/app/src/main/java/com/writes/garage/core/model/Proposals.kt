package com.writes.garage.core.model

import java.time.Instant

/**
 * Response of `receiptQuickAdd`. Nothing is written server-side until the client saves the entry and
 * then calls `confirmReceiptScan {token}` (which only commits the quota reservation).
 * [details] carries the schemaVersion-2 typed fields (brand, oilGrade, ...), already filtered to non-null.
 */
data class ReceiptProposal(
    val token: String,
    val vehicleId: String,
    val entryType: EntryType,
    val entryDate: Instant,
    val odometerReading: Int? = null,
    val cost: Double? = null,
    val shopName: String? = null,
    val notes: String? = null,
    val lineItems: List<String> = emptyList(),
    val confidence: Double = 0.0,
    val isDiy: Boolean? = null,
    val details: Map<String, Any?> = emptyMap(),
    val quota: ReceiptQuota? = null,
)

/** Response of `voiceQuickAdd`; reviewed by the user before it becomes an [Entry]. */
data class VoiceProposal(
    val transcript: String,
    val vehicleId: String,
    val entryType: EntryType,
    val entryDate: Instant,
    val odometerReading: Int? = null,
    val cost: Double? = null,
    val shopName: String? = null,
    val notes: String? = null,
    val confidence: Double = 0.0,
    val isDiy: Boolean? = null,
    val details: Map<String, Any?> = emptyMap(),
)

/**
 * Mirror of the server `ReceiptQuotaSnapshot`. [remaining]/[monthlyLimit] describe the base
 * (free lifetime or Pro monthly) confirmed-save allowance; [creditBalance] is purchased credits.
 */
data class ReceiptQuota(
    val remaining: Int,
    val monthlyLimit: Int,
    val creditBalance: Int = 0,
    val isPro: Boolean = false,
    val scanRemaining: Int? = null,
    val resetAt: String? = null,
    /** `granted` / `refunded` / `unknown` when the call was a transaction reconcile. */
    val transactionState: String? = null,
)
