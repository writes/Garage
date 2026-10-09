package com.writes.garage.feature.garage

import com.writes.garage.core.data.DetailingRepository
import com.writes.garage.core.domain.DetailingForm
import com.writes.garage.core.domain.DetailingFormState
import com.writes.garage.core.model.DetailingRecord
import java.time.ZoneId

/** Coatings, paint correction, PPF, etc. with layers, warranty expiration and maintenance notes. */
class DetailingViewModel(
    repo: DetailingRepository,
    vehicleId: String,
    private val zone: ZoneId = ZoneId.systemDefault(),
) : RecordsViewModel<DetailingRecord, DetailingFormState>(repo, vehicleId) {
    override fun idOf(item: DetailingRecord) = item.id

    override fun newForm() = DetailingFormState()

    override fun toForm(item: DetailingRecord) = DetailingForm.from(item, zone)

    override fun build(form: DetailingFormState, existing: DetailingRecord?): Pair<DetailingRecord?, DetailingFormState> {
        val (r, errors) = DetailingForm.build(form, vehicleId, existing, zone)
        return r to form.copy(errors = errors)
    }

    override fun order(items: List<DetailingRecord>) = items.sortedByDescending { it.serviceDate }
}
