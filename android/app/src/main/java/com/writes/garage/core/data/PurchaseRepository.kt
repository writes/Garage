package com.writes.garage.core.data

import com.writes.garage.core.model.CreditsOffer
import com.writes.garage.core.model.CreditsPurchaseResult
import com.writes.garage.core.model.Entitlement
import com.writes.garage.core.model.PaywallPackage
import kotlinx.coroutines.flow.StateFlow

interface PurchaseRepository {
    val entitlement: StateFlow<Entitlement>

    /**
     * The purchasing identity (RevenueCat `appUserID`). Null for backends that aren't identity-bound (demo, unconfigured):
     * they can't charge anyone, so there is nothing to mismatch. A real store backend always reports a value.
     */
    val appUserID: String? get() = null

    /** True when the store identity is anonymous (e.g. `$RCAnonymousID`): a charge there can never be tied to a uid. */
    val isAnonymous: Boolean get() = false

    suspend fun loadPackages(): List<PaywallPackage>

    /** Purchases [packageId]; the entitlement flow updates on success. */
    suspend fun purchase(packageId: String)

    suspend fun restore()

    /** The +10 receipt-credits consumable (null when the store product isn't available). */
    suspend fun receiptCreditsOffer(): CreditsOffer? = null

    suspend fun purchaseReceiptCredits(): CreditsPurchaseResult = CreditsPurchaseResult.Unavailable
}
