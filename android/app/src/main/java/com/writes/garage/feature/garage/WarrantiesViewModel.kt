package com.writes.garage.feature.garage

import com.writes.garage.core.data.WarrantyRepository
import com.writes.garage.core.domain.WarrantyForm
import com.writes.garage.core.domain.WarrantyFormState
import com.writes.garage.core.model.Warranty
import java.time.Instant
import java.time.ZoneId

class WarrantiesViewModel(
    repo: WarrantyRepository,
    vehicleId: String,
    private val zone: ZoneId = ZoneId.systemDefault(),
    clock: () -> Instant = Instant::now,
) : RecordsViewModel<Warranty, WarrantyFormState>(repo, vehicleId, clock) {
    override fun idOf(item: Warranty) = item.id

    override fun newForm() = WarrantyFormState(startDate = clock().atZone(zone).toLocalDate())

    override fun toForm(item: Warranty) = WarrantyForm.from(item, zone)

    override fun build(form: WarrantyFormState, existing: Warranty?): Pair<Warranty?, WarrantyFormState> {
        val (w, errors) = WarrantyForm.build(form, vehicleId, existing, zone)
        return (w?.let { if (existing == null) it.copy(createdAt = clock()) else it }) to form.copy(errors = errors)
    }

    /** Active coverage first (soonest to end first), then expired, newest first. */
    override fun order(items: List<Warranty>): List<Warranty> {
        val now = clock()
        return items.sortedWith(
            compareBy<Warranty> { !it.isActive(now) }
                .thenBy { if (it.isActive(now)) it.endsAt else null }
                .thenByDescending { it.startDate },
        )
    }
}
