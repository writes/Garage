package com.writes.garage.core.data

import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.ReceiptProposal
import com.writes.garage.core.model.ReceiptQuota
import com.writes.garage.core.model.Vehicle
import com.writes.garage.core.model.VoiceProposal

/**
 * Typed wrappers over the Firebase callables (region `us-central1`). Request/response shapes live in
 * the TypeScript sources under `CloudFunctions/src/functions/`. AI callables require AI consent (checked by the caller).
 */
interface FunctionsGateway {
    /**
     * `receiptQuickAdd`: parse receipt images (base64 JPEG/PNG, 1..N) or a PDF (base64) into a proposal.
     * Nothing is written; the caller saves the entry and then calls [confirmReceiptScan] with the token.
     */
    suspend fun receiptQuickAdd(
        vehicle: Vehicle,
        imagesBase64: List<String> = emptyList(),
        pdfBase64: String? = null,
    ): ReceiptProposal

    /** `confirmReceiptScan {token}`: commit the quota reservation after the entry was saved. */
    suspend fun confirmReceiptScan(token: String): ReceiptQuota

    suspend fun receiptQuotaStatus(): ReceiptQuota

    /** `reconcileReceiptCreditPurchase {transactionId}` for the receipt-credits consumable. */
    suspend fun reconcileReceiptCreditPurchase(transactionId: String): ReceiptQuota

    /** `voiceQuickAdd`: transcript -> proposal. */
    suspend fun voiceQuickAdd(vehicle: Vehicle, transcript: String): VoiceProposal

    /** `parseOilAnalysis {pdfBase64}`: returns raw extracted fields keyed by name. */
    suspend fun parseOilAnalysis(pdfBase64: String): Map<String, Any?>

    /** `lookupRecalls {vin}` (NHTSA via the proxy). Returned recalls are attributed to [vehicleId]. */
    suspend fun lookupRecalls(vehicleId: String, vin: String): List<Recall>

    suspend fun experimentConfig(): Map<String, Any?>

    suspend fun deleteAccount()

    /** `deleteVehicle {vehicleId}`: server purge of a tombstoned vehicle (+ counter decrement). */
    suspend fun deleteVehicle(vehicleId: String)
}
