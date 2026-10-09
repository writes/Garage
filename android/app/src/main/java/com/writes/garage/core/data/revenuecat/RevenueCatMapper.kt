package com.writes.garage.core.data.revenuecat

import com.writes.garage.core.model.Entitlement
import java.time.Instant

/** Pure mapping from RevenueCat values to domain types (no SDK types, so it is unit-testable). */
object RevenueCatMapper {
    /** RevenueCat entitlement identifier; must match iOS (`info.entitlements["pro"]`) and the server webhook. */
    const val ENTITLEMENT_ID = "pro"

    fun entitlement(isActive: Boolean, productId: String?, expiresAtMillis: Long?, willRenew: Boolean): Entitlement =
        if (!isActive) {
            Entitlement.FREE
        } else {
            Entitlement(
                isPro = true,
                productId = productId,
                expiresAt = expiresAtMillis?.let(Instant::ofEpochMilli),
                willRenew = willRenew,
            )
        }

    /** RevenueCat `PackageType` name -> paywall period label. */
    fun periodLabel(packageTypeName: String): String = when (packageTypeName) {
        "ANNUAL" -> "year"
        "SIX_MONTH" -> "6 months"
        "THREE_MONTH" -> "3 months"
        "TWO_MONTH" -> "2 months"
        "MONTHLY" -> "month"
        "WEEKLY" -> "week"
        "LIFETIME" -> "lifetime"
        else -> ""
    }

    /**
     * Play subscription product ids look like `subscriptionId:basePlanId`; iOS-style ids
     * ([com.writes.garage.core.domain.Constants]) are the subscription id part.
     */
    fun subscriptionId(productId: String): String = productId.substringBefore(':')
}
