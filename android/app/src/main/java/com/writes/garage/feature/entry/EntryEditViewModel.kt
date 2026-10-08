package com.writes.garage.feature.entry

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.observeActiveVehicle
import com.writes.garage.core.domain.FuelEconomy
import com.writes.garage.core.domain.Validators
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.round

/** Add/edit entry form: type picker, shared fields and the per-type detail fields from [EntryFieldSpecs]. */
class EntryEditViewModel(
    private val entries: EntryRepository,
    private val vehicles: VehicleRepository,
    private val vehicleId: String?,
    private val entryId: String?,
    private val zone: ZoneId = ZoneId.systemDefault(),
    today: () -> LocalDate = { LocalDate.now() },
) : ViewModel() {
    private val _state = MutableStateFlow(EntryFormState(date = today()))
    val state: StateFlow<EntryFormState> = _state.asStateFlow()

    private var existing: Entry? = null
    private var known: List<Entry> = emptyList()

    val isEdit: Boolean get() = entryId != null

    init {
        viewModelScope.launch { load() }
    }

    private suspend fun load() {
        val list = vehicles.observeVehicles().first()
        val old = if (vehicleId != null && entryId != null) entries.observeEntry(vehicleId, entryId).first() else null
        if (entryId != null && old == null) {
            _state.update { it.copy(loading = false, notFound = true, vehicles = list) }
            return
        }
        existing = old
        if (old != null) {
            known = entries.observeEntries(old.vehicleId).first()
            _state.update {
                it.copy(
                    vehicleId = old.vehicleId,
                    vehicles = list,
                    type = old.entryType,
                    date = old.entryDate.atZone(zone).toLocalDate(),
                    odometer = old.odometerReading.toString(),
                    cost = old.cost?.let(::moneyText).orEmpty(),
                    shop = old.shopName.orEmpty(),
                    notes = old.notes.orEmpty(),
                    isDiy = old.isDiy == true,
                    details = EntryDetailsMapper.defaults(old.entryType) + EntryDetailsMapper.toRaw(old.entryType, old.details, zone),
                    loading = false,
                )
            }
        } else {
            val target = vehicleId?.let { id -> list.firstOrNull { it.id == id } } ?: vehicles.observeActiveVehicle().first()
            if (target == null) {
                _state.update { it.copy(loading = false, vehicles = list, formError = "Add a vehicle first.") }
                return
            }
            known = entries.observeEntries(target.id).first()
            _state.update {
                it.copy(
                    vehicleId = target.id,
                    vehicles = list,
                    odometer = target.currentOdometer.takeIf { o -> o > 0 }?.toString().orEmpty(),
                    details = EntryDetailsMapper.defaults(it.type, target.fuelType?.wire),
                    loading = false,
                )
            }
        }
        refreshWarnings()
    }

    // --- input handlers ---

    fun update(transform: EntryFormState.() -> EntryFormState) {
        _state.update { it.transform() }
        refreshWarnings()
    }

    fun setType(type: EntryType) = _state.update { s ->
        if (s.type == type) return@update s
        val fuel = s.vehicles.firstOrNull { it.id == s.vehicleId }?.fuelType?.wire
        s.copy(type = type, details = EntryDetailsMapper.defaults(type, fuel), errors = emptyMap(), formError = null)
    }

    fun setOdometer(text: String) {
        _state.update { it.copy(odometer = text.filter { c -> c.isDigit() || c == ',' }, errors = it.errors - EntryFormValidator.ODOMETER) }
        refreshWarnings()
    }

    fun setCost(text: String) =
        _state.update { it.copy(cost = text.filter { c -> c.isDigit() || c == '.' }, errors = it.errors - EntryFormValidator.COST) }

    fun setDate(date: LocalDate) {
        _state.update { it.copy(date = date) }
        refreshWarnings()
    }

    fun setDetail(key: String, value: String) = _state.update {
        it.copy(details = it.details + (key to value), errors = it.errors - EntryFormValidator.detailKey(key))
    }

    /** Add mode only: switch the target vehicle. */
    fun selectVehicle(id: String) {
        if (isEdit || _state.value.vehicleId == id) return
        viewModelScope.launch {
            known = entries.observeEntries(id).first()
            val v = _state.value.vehicles.firstOrNull { it.id == id }
            _state.update {
                it.copy(
                    vehicleId = id,
                    odometer = v?.currentOdometer?.takeIf { o -> o > 0 }?.toString() ?: it.odometer,
                    details = if (it.type == EntryType.FUEL && v?.fuelType != null) it.details + ("fuelGrade" to v.fuelType.wire) else it.details,
                )
            }
            refreshWarnings()
        }
    }

    private fun refreshWarnings() {
        val s = _state.value
        val vid = s.vehicleId ?: return
        val reading = Validators.parseOdometer(s.odometer) ?: return _state.update { it.copy(warnings = emptyList()) }
        val on = instantFor(s.date, existing)
        val bounds = Validators.odometerBounds(known, vid, on, excludingEntryId = existing?.id)
        _state.update { it.copy(warnings = Validators.odometerWarnings(reading, bounds)) }
    }

    // --- save ---

    fun save(onDone: () -> Unit = {}) {
        val s = _state.value
        if (s.saving || s.loading) return
        val target = s.vehicleId
        if (target == null) {
            _state.update { it.copy(formError = "Add a vehicle first.") }
            return
        }
        val errors = EntryFormValidator.validate(s)
        if (errors.isNotEmpty()) {
            _state.update { it.copy(errors = errors, formError = "Fix the highlighted fields.") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(saving = true, errors = emptyMap(), formError = null) }
            val old = existing
            val entry = buildEntry(s, target, old)
            runCatching {
                if (old == null) entries.addEntry(entry) else entries.updateEntry(entry)
                bumpOdometer(target, entry.odometerReading)
            }.onSuccess { onDone() }
                .onFailure { e -> _state.update { it.copy(saving = false, formError = e.message ?: "Could not save the entry.") } }
        }
    }

    private fun buildEntry(s: EntryFormState, vehicle: String, old: Entry?): Entry {
        val sameType = old != null && old.entryType == s.type
        val details = EntryDetailsMapper.toDetails(s.type, s.details, if (sameType) old!!.details else emptyMap(), zone)
            .toMutableMap()
        var cost = EntryFormValidator.parseDecimal(s.cost)
        val odometer = Validators.parseOdometer(s.odometer) ?: 0
        val id = old?.id.orEmpty()

        if (s.type == EntryType.FUEL) {
            val gallons = (details["gallons"] as? Number)?.toDouble()
            val price = (details["pricePerGallon"] as? Number)?.toDouble()
            if (cost == null && gallons != null && price != null) cost = round(gallons * price * 100) / 100
            details["totalCost"] = cost ?: 0.0
            val others = known.filter { it.id != old?.id }
            val probe = Entry(
                id = id.ifEmpty { NEW_ID }, vehicleId = vehicle, userId = "", entryType = EntryType.FUEL,
                entryDate = instantFor(s.date, old), odometerReading = odometer, details = details,
            )
            val mpg = FuelEconomy.mpgBetweenFills(others + probe)[probe.id]
            if (mpg != null) details["calculatedMPG"] = round(mpg * 10) / 10 else details.remove("calculatedMPG")
        }

        val resolved = when (s.type) {
            EntryType.REPAIR, EntryType.MAINTENANCE -> details["status"] == "resolved"
            else -> old?.isResolved
        }
        return (old ?: Entry(
            id = "", vehicleId = vehicle, userId = "", entryType = s.type,
            entryDate = Instant.EPOCH, odometerReading = 0,
        )).copy(
            vehicleId = vehicle,
            entryType = s.type,
            entryDate = instantFor(s.date, old),
            odometerReading = odometer,
            cost = cost,
            isDiy = if (s.isDiy) true else old?.isDiy?.let { false },
            shopName = s.shop.trim().ifBlank { null },
            notes = s.notes.trim().ifBlank { null },
            isResolved = resolved,
            details = details,
        )
    }

    /** Best effort: the vehicle's odometer follows its newest reading (iOS does this transactionally). */
    private suspend fun bumpOdometer(vehicle: String, reading: Int) {
        runCatching {
            val v = vehicles.observeVehicle(vehicle).first() ?: return
            if (reading > v.currentOdometer) vehicles.updateVehicle(v.copy(currentOdometer = reading))
        }
    }

    private fun instantFor(date: LocalDate, old: Entry?): Instant =
        if (old != null && old.entryDate.atZone(zone).toLocalDate() == date) {
            old.entryDate
        } else {
            date.atTime(12, 0).atZone(zone).toInstant()
        }

    private fun moneyText(d: Double): String = java.math.BigDecimal.valueOf(d).stripTrailingZeros().toPlainString()

    private companion object {
        const val NEW_ID = "__new__"
    }
}
