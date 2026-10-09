package com.writes.garage.core.data.demo

import com.writes.garage.core.model.AuthUser
import com.writes.garage.core.model.Entitlement
import com.writes.garage.core.model.DetailingRecord
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.GalleryPhoto
import com.writes.garage.core.model.SparePart
import com.writes.garage.core.model.Warranty
import com.writes.garage.core.model.WearSnapshot
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.Reminder
import com.writes.garage.core.model.UserProfile
import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.flow.MutableStateFlow
import java.time.Instant

/** Shared in-memory state behind all demo repositories. Resets when the process dies. */
class DemoStore(seed: SeedData = SeedData(), val clock: () -> Instant = { Instant.now() }) {
    val user = MutableStateFlow<AuthUser?>(null)
    val profile = MutableStateFlow(
        UserProfile(
            id = seed.userId, email = "demo@garage.local", name = "Demo Driver",
            analyticsOptOut = true, aiConsentGrantedAt = seed.entries.first().createdAt,
        ),
    )
    val vehicles = MutableStateFlow<List<Vehicle>>(seed.vehicles)
    val entries = MutableStateFlow<List<Entry>>(seed.entries)
    val reminders = MutableStateFlow<List<Reminder>>(seed.reminders)
    val recalls = MutableStateFlow<List<Recall>>(seed.recalls)
    val gallery = MutableStateFlow<List<GalleryPhoto>>(emptyList())
    val warranties = MutableStateFlow<List<Warranty>>(seed.warranties)
    val parts = MutableStateFlow<List<SparePart>>(emptyList())
    val detailing = MutableStateFlow<List<DetailingRecord>>(emptyList())
    val wear = MutableStateFlow<List<WearSnapshot>>(emptyList())
    val activeVehicleId = MutableStateFlow<String?>(seed.vehicles.firstOrNull()?.id)

    /** Demo starts as Pro so the two seeded vehicles are within the plan limit. */
    val entitlement = MutableStateFlow(Entitlement(isPro = true, productId = "demo.pro"))

    private var counter = 0

    fun newId(prefix: String): String = "$prefix-demo-${++counter}-${clock().toEpochMilli()}"
}
