package com.writes.garage.core.data.demo

import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.ReceiptProposal
import com.writes.garage.core.model.ReceiptQuota
import com.writes.garage.core.model.Vehicle
import com.writes.garage.core.model.VoiceProposal
import kotlinx.coroutines.flow.update

/**
 * Fake AI: deterministic canned proposals, no network. Nothing is written by the gateway; like the live
 * backend, the caller saves the entry and then confirms the token (which only moves the quota).
 */
class DemoFunctionsGateway(private val store: DemoStore) : FunctionsGateway {
    private val pending = mutableMapOf<String, ReceiptProposal>()
    private var confirmed = 0

    override suspend fun receiptQuickAdd(
        vehicle: Vehicle,
        imagesBase64: List<String>,
        pdfBase64: String?,
    ): ReceiptProposal {
        val seedBasis = (imagesBase64.firstOrNull() ?: pdfBase64 ?: vehicle.id)
        val proposal = ReceiptProposal(
            token = "demo-token-${seedBasis.hashCode().toUInt()}",
            vehicleId = vehicle.id,
            entryType = EntryType.OIL_CHANGE,
            entryDate = store.clock(),
            odometerReading = vehicle.currentOdometer,
            cost = 89.95,
            shopName = "Demo Quick Lube",
            notes = "Full synthetic oil change (demo receipt).",
            lineItems = listOf("Synthetic oil 5qt", "Oil filter", "Shop supplies"),
            confidence = 0.92,
            isDiy = false,
            details = mapOf("brand" to "Mobil 1", "oilGrade" to "5W-30", "quantityQuarts" to 5.0),
            quota = quota(),
        )
        pending[proposal.token] = proposal
        return proposal
    }

    override suspend fun confirmReceiptScan(token: String): ReceiptQuota {
        pending.remove(token) ?: error("Unknown or expired receipt token")
        confirmed++
        return quota()
    }

    override suspend fun receiptQuotaStatus(): ReceiptQuota = quota()

    override suspend fun reconcileReceiptCreditPurchase(transactionId: String): ReceiptQuota =
        quota().copy(transactionState = "granted")

    override suspend fun voiceQuickAdd(vehicle: Vehicle, transcript: String): VoiceProposal {
        val lower = transcript.lowercase()
        val type = when {
            "oil" in lower -> EntryType.OIL_CHANGE
            "gas" in lower || "fuel" in lower || "fill" in lower -> EntryType.FUEL
            "brake" in lower -> EntryType.BRAKE
            "tire" in lower -> EntryType.TIRE
            else -> EntryType.MAINTENANCE
        }
        return VoiceProposal(
            transcript = transcript, vehicleId = vehicle.id, entryType = type, entryDate = store.clock(),
            odometerReading = vehicle.currentOdometer,
            cost = Regex("""\$?(\d+(?:\.\d{1,2})?)""").find(transcript)?.groupValues?.get(1)?.toDoubleOrNull(),
            notes = transcript, confidence = 0.8,
        )
    }

    override suspend fun parseOilAnalysis(pdfBase64: String): Map<String, Any?> =
        mapOf("labName" to "Demo Lab", "iron" to 10.0, "aluminum" to 3.0, "viscosity" to "14.0 cSt")

    override suspend fun lookupRecalls(vehicleId: String, vin: String): List<Recall> =
        store.recalls.value.filter { it.vehicleId == vehicleId }

    override suspend fun experimentConfig(): Map<String, Any?> = emptyMap()

    override suspend fun deleteAccount() {
        store.user.value = null
    }

    override suspend fun deleteVehicle(vehicleId: String) {
        store.vehicles.update { list -> list.filterNot { it.id == vehicleId } }
        store.entries.update { list -> list.filterNot { it.vehicleId == vehicleId } }
    }

    private fun quota(): ReceiptQuota {
        val pro = store.entitlement.value.isPro
        val allowance = if (pro) 20 else 5
        return ReceiptQuota(
            remaining = (allowance - confirmed).coerceAtLeast(0), monthlyLimit = allowance, isPro = pro,
            scanRemaining = (if (pro) 80 else 20) - confirmed,
        )
    }
}
