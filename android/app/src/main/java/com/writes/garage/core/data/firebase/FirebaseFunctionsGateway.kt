package com.writes.garage.core.data.firebase

import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.functions.FirebaseFunctionsException
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.ReceiptProposal
import com.writes.garage.core.model.ReceiptQuota
import com.writes.garage.core.model.Vehicle
import com.writes.garage.core.model.VoiceProposal
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await
import java.time.Instant
import java.util.concurrent.TimeUnit

/** Live callables (`us-central1`). All shaping/parsing lives in [FunctionsMappers] so it is unit-tested without Firebase. */
class FirebaseFunctionsGateway(
    private val functions: FirebaseFunctions = FirebaseFunctions.getInstance(Callables.REGION),
    private val clock: () -> Instant = Instant::now,
) : FunctionsGateway {

    /** AI callables allow ~55 s upstream; deleteVehicle/deleteAccount purge recursively (CF budget is 120 s). */
    private suspend fun call(name: String, payload: Any?, timeoutSeconds: Long = 90): Map<String, Any?> {
        try {
            val ref = functions.getHttpsCallable(name).withTimeout(timeoutSeconds, TimeUnit.SECONDS)
            val data = (if (payload == null) ref.call() else ref.call(payload)).await().getData()
            return FirestoreMappers.stringMap(data)
        } catch (e: CancellationException) {
            throw e
        } catch (e: FirebaseFunctionsException) {
            throw FunctionsMappers.classifyError(name, e.code.name, e.message, e.details, e)
        }
    }

    override suspend fun receiptQuickAdd(vehicle: Vehicle, imagesBase64: List<String>, pdfBase64: String?): ReceiptProposal {
        val request = FunctionsMappers.receiptRequest(vehicle, imagesBase64, pdfBase64)
        return FunctionsMappers.parseReceiptProposal(call(Callables.RECEIPT_QUICK_ADD, request, 120), vehicle.id, clock())
    }

    override suspend fun confirmReceiptScan(token: String): ReceiptQuota =
        FunctionsMappers.parseQuota(call(Callables.CONFIRM_RECEIPT_SCAN, mapOf("token" to token)))

    override suspend fun receiptQuotaStatus(transactionId: String?): ReceiptQuota =
        FunctionsMappers.parseQuota(
            call(Callables.RECEIPT_QUOTA_STATUS, if (transactionId == null) emptyMap<String, Any?>() else mapOf("transactionId" to transactionId)),
        )

    override suspend fun reconcileReceiptCreditPurchase(transactionId: String): ReceiptQuota =
        FunctionsMappers.parseReconcile(call(Callables.RECONCILE_RECEIPT_CREDIT_PURCHASE, mapOf("transactionId" to transactionId)))

    override suspend fun voiceQuickAdd(vehicle: Vehicle, transcript: String): VoiceProposal {
        val request = FunctionsMappers.voiceRequest(vehicle, transcript)
        return FunctionsMappers.parseVoiceProposal(call(Callables.VOICE_QUICK_ADD, request, 90), vehicle.id, transcript, clock())
    }

    override suspend fun parseOilAnalysis(pdfBase64: String): Map<String, Any?> =
        call(Callables.PARSE_OIL_ANALYSIS, mapOf("pdfBase64" to pdfBase64), 120)

    override suspend fun lookupRecalls(vehicleId: String, vin: String): List<Recall> =
        FunctionsMappers.parseRecalls(call(Callables.LOOKUP_RECALLS, mapOf("vin" to vin.trim())), vehicleId, clock())

    override suspend fun experimentConfig(): Map<String, Any?> = call(Callables.EXPERIMENT_CONFIG, null, 30)

    override suspend fun deleteAccount() {
        call(Callables.DELETE_ACCOUNT, emptyMap<String, Any?>(), 120)
    }

    override suspend fun deleteVehicle(vehicleId: String) {
        call(Callables.DELETE_VEHICLE, mapOf("vehicleId" to vehicleId), 120)
    }
}
