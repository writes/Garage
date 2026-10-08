package com.writes.garage.core.model

import java.time.Instant

/** RevenueCat-backed access level. Free = 1 vehicle, Pro = 5 (see VehicleLimitPolicy). */
data class Entitlement(
    val isPro: Boolean = false,
    val productId: String? = null,
    val expiresAt: Instant? = null,
    val willRenew: Boolean = false,
) {
    companion object {
        val FREE = Entitlement()
    }
}

/** One purchasable package shown on the paywall. */
data class PaywallPackage(
    val id: String,
    val productId: String,
    val title: String,
    val priceLabel: String,
    val period: String,
)

/** Subscription map mirrored from `users/{uid}.subscription` (server-written, read-only to the client). */
data class Subscription(
    val status: String = "none",
    val productId: String? = null,
    val expiresAt: Instant? = null,
)
