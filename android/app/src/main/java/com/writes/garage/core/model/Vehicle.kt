package com.writes.garage.core.model

import java.time.Instant

enum class FuelType(val wire: String, val displayName: String) {
    REGULAR_87("regular_87", "Regular 87"),
    PREMIUM_91("premium_91", "Premium 91"),
    PREMIUM_93("premium_93", "Premium 93"),
    E85("e85", "E85"),
    DIESEL("diesel", "Diesel");

    companion object {
        fun fromWire(value: String?): FuelType? = entries.firstOrNull { it.wire == value }
    }
}

/** Firestore `vehicles/{id}`; `userId` is the owner. Soft-deleted via [deletedAt], never hard-deleted client-side. */
data class Vehicle(
    val id: String,
    val userId: String,
    val nickname: String,
    val make: String,
    val model: String,
    val year: Int,
    val licensePlate: String? = null,
    val purchaseDate: Instant? = null,
    val purchasePrice: Double? = null,
    val currentOdometer: Int = 0,
    val odometerAtPurchase: Int? = null,
    val engineOilType: String? = null,
    val tireSizeFront: String? = null,
    val tireSizeRear: String? = null,
    val fuelType: FuelType? = null,
    val vin: String? = null,
    val color: String? = null,
    val weightClass: String? = null,
    val notes: String? = null,
    val displayOrder: Int = 0,
    val createdAt: Instant? = null,
    val updatedAt: Instant? = null,
    val deletedAt: Instant? = null,
) {
    val displayName: String
        get() = nickname.ifBlank { "$year $make $model" }
}
