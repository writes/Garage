package com.writes.garage

import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Vehicle
import java.time.Instant

object TestFixtures {
    val NOW: Instant = Instant.parse("2026-06-01T12:00:00Z")

    fun daysAgo(days: Long): Instant = NOW.minusSeconds(days * 86_400)

    fun entry(
        id: String,
        type: EntryType = EntryType.MAINTENANCE,
        daysAgo: Long = 0,
        odo: Int = 0,
        cost: Double? = null,
        vehicleId: String = "v1",
        details: Map<String, Any?> = emptyMap(),
        shop: String? = null,
        notes: String? = null,
    ) = Entry(
        id = id, vehicleId = vehicleId, userId = "u1", entryType = type, entryDate = daysAgo(daysAgo),
        odometerReading = odo, cost = cost, shopName = shop, notes = notes, details = details,
    )

    fun vehicle(id: String = "v1") = Vehicle(
        id = id, userId = "u1", nickname = "Daily", make = "Audi", model = "SQ5", year = 2015, currentOdometer = 82_440,
    )
}
