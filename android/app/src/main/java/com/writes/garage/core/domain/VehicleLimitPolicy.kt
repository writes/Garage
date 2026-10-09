package com.writes.garage.core.domain

/** Free = 1 vehicle, Pro = 5. The server (rules + counter) is authoritative; this drives UI gating. */
object VehicleLimitPolicy {
    fun limitFor(isPro: Boolean): Int = if (isPro) Constants.MAX_PRO_VEHICLES else Constants.MAX_FREE_VEHICLES

    fun canAddVehicle(currentCount: Int, isPro: Boolean): Boolean = currentCount < limitFor(isPro)
}

class VehicleLimitReachedException(val limit: Int) :
    IllegalStateException("Vehicle limit reached ($limit)")
