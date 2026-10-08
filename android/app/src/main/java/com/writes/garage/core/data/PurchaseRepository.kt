package com.writes.garage.core.data

import com.writes.garage.core.model.Entitlement
import com.writes.garage.core.model.PaywallPackage
import kotlinx.coroutines.flow.StateFlow

interface PurchaseRepository {
    val entitlement: StateFlow<Entitlement>

    suspend fun loadPackages(): List<PaywallPackage>

    /** Purchases [packageId]; the entitlement flow updates on success. */
    suspend fun purchase(packageId: String)

    suspend fun restore()
}
