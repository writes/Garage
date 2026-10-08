package com.writes.garage.feature.garage

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.PurchaseRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.domain.Validators
import com.writes.garage.core.domain.VehicleLimitPolicy
import com.writes.garage.core.domain.VehicleLimitReachedException
import com.writes.garage.core.model.FuelType
import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId
import java.time.Year

data class VehicleFormState(
    val nickname: String = "",
    val make: String = "",
    val model: String = "",
    val year: String = Year.now().value.toString(),
    val licensePlate: String = "",
    val vin: String = "",
    val color: String = "",
    val odometer: String = "0",
    val odometerAtPurchase: String = "",
    val purchaseDate: LocalDate? = null,
    val purchasePrice: String = "",
    val engineOilType: String = "",
    val tireSizeFront: String = "",
    val tireSizeRear: String = "",
    /** [FuelType.wire] or "" for unset. */
    val fuelType: String = "",
    val weightClass: String = "",
    val notes: String = "",
    val errors: Map<String, String> = emptyMap(),
    val formError: String? = null,
    val saving: Boolean = false,
    val loading: Boolean = false,
    val notFound: Boolean = false,
    /** Add mode only: the plan's vehicle limit is already used up. */
    val limitReached: Boolean = false,
    val limit: Int = 1,
) {
    val isValid: Boolean get() = VehicleFormValidator.validate(this).isEmpty()
}

object VehicleFormValidator {
    const val MIN_YEAR = 1886

    fun validate(s: VehicleFormState, maxYear: Int = Year.now().value + 2): Map<String, String> {
        val e = LinkedHashMap<String, String>()
        if (s.make.isBlank()) e["make"] = "Required"
        if (s.model.isBlank()) e["model"] = "Required"
        val year = s.year.toIntOrNull()
        if (year == null || year !in MIN_YEAR..maxYear) e["year"] = "Enter a year from $MIN_YEAR to $maxYear"
        if (s.odometer.isBlank() || Validators.parseOdometer(s.odometer) == null) e["odometer"] = "Enter 0 to 2,000,000"
        if (s.odometerAtPurchase.isNotBlank() && Validators.parseOdometer(s.odometerAtPurchase) == null) {
            e["odometerAtPurchase"] = "Enter 0 to 2,000,000"
        }
        if (s.vin.isNotBlank() && !Validators.isValidVin(s.vin)) e["vin"] = "17 characters, letters and digits, no I, O or Q"
        if (s.purchasePrice.isNotBlank()) {
            val p = s.purchasePrice.filterNot { it == '$' || it == ',' || it.isWhitespace() }.toDoubleOrNull()
            if (p == null || p < 0 || !p.isFinite()) e["purchasePrice"] = "Enter a non-negative amount"
        }
        return e
    }
}

class VehicleEditViewModel(
    private val repo: VehicleRepository,
    private val purchases: PurchaseRepository,
    private val vehicleId: String?,
    private val zone: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    private val _state = MutableStateFlow(VehicleFormState(loading = vehicleId != null))
    val state: StateFlow<VehicleFormState> = _state.asStateFlow()
    private var existing: Vehicle? = null

    init {
        if (vehicleId != null) {
            viewModelScope.launch {
                val v = repo.observeVehicle(vehicleId).first()
                if (v == null) {
                    _state.update { it.copy(loading = false, notFound = true) }
                } else {
                    existing = v
                    _state.value = v.toForm()
                }
            }
        } else {
            // Plan gate for adding: re-evaluated if the entitlement or garage changes.
            viewModelScope.launch {
                combine(repo.observeVehicles(), purchases.entitlement) { list, ent -> list.size to ent.isPro }
                    .collect { (count, isPro) ->
                        _state.update {
                            it.copy(
                                limitReached = !VehicleLimitPolicy.canAddVehicle(count, isPro),
                                limit = VehicleLimitPolicy.limitFor(isPro),
                            )
                        }
                    }
            }
        }
    }

    fun update(transform: VehicleFormState.() -> VehicleFormState) = _state.update { it.transform() }

    /** Edit one text field and clear its error. */
    fun edit(field: String, value: String) = _state.update { s ->
        val next = when (field) {
            "nickname" -> s.copy(nickname = value)
            "make" -> s.copy(make = value)
            "model" -> s.copy(model = value)
            "year" -> s.copy(year = value.filter(Char::isDigit).take(4))
            "licensePlate" -> s.copy(licensePlate = value)
            "vin" -> s.copy(vin = value.uppercase().filter { it.isLetterOrDigit() }.take(17))
            "color" -> s.copy(color = value)
            "odometer" -> s.copy(odometer = value.filter { it.isDigit() || it == ',' })
            "odometerAtPurchase" -> s.copy(odometerAtPurchase = value.filter { it.isDigit() || it == ',' })
            "purchasePrice" -> s.copy(purchasePrice = value.filter { it.isDigit() || it == '.' })
            "engineOilType" -> s.copy(engineOilType = value)
            "tireSizeFront" -> s.copy(tireSizeFront = value)
            "tireSizeRear" -> s.copy(tireSizeRear = value)
            "fuelType" -> s.copy(fuelType = value)
            "weightClass" -> s.copy(weightClass = value)
            "notes" -> s.copy(notes = value)
            else -> s
        }
        next.copy(errors = next.errors - field)
    }

    fun save(onDone: () -> Unit = {}) {
        val s = _state.value
        if (s.saving || s.loading) return
        val errors = VehicleFormValidator.validate(s)
        if (errors.isNotEmpty()) {
            _state.update { it.copy(errors = errors, formError = "Fix the highlighted fields.") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(saving = true, errors = emptyMap(), formError = null) }
            val old = existing
            val vehicle = (old ?: Vehicle(id = "", userId = "", nickname = "", make = "", model = "", year = 0)).copy(
                nickname = s.nickname.trim(),
                make = s.make.trim(),
                model = s.model.trim(),
                year = s.year.toInt(),
                licensePlate = s.licensePlate.blankToNull(),
                vin = Validators.normalizeVin(s.vin),
                color = s.color.blankToNull(),
                currentOdometer = Validators.parseOdometer(s.odometer) ?: 0,
                odometerAtPurchase = s.odometerAtPurchase.takeIf { it.isNotBlank() }?.let(Validators::parseOdometer),
                purchaseDate = s.purchaseDate?.let { d ->
                    if (old?.purchaseDate?.atZone(zone)?.toLocalDate() == d) old.purchaseDate
                    else d.atTime(12, 0).atZone(zone).toInstant()
                },
                purchasePrice = s.purchasePrice.filterNot { it == '$' || it == ',' || it.isWhitespace() }.toDoubleOrNull(),
                engineOilType = s.engineOilType.blankToNull(),
                tireSizeFront = s.tireSizeFront.blankToNull(),
                tireSizeRear = s.tireSizeRear.blankToNull(),
                fuelType = FuelType.fromWire(s.fuelType),
                weightClass = s.weightClass.blankToNull(),
                notes = s.notes.blankToNull(),
            )
            runCatching { if (old == null) repo.addVehicle(vehicle) else repo.updateVehicle(vehicle) }
                .onSuccess { onDone() }
                .onFailure { e ->
                    val msg = if (e is VehicleLimitReachedException) {
                        "Plan limit reached (${e.limit}). Upgrade to add more."
                    } else {
                        e.message ?: "Could not save the vehicle."
                    }
                    _state.update { it.copy(saving = false, formError = msg, limitReached = e is VehicleLimitReachedException || it.limitReached) }
                }
        }
    }

    private fun String.blankToNull(): String? = trim().ifBlank { null }

    private fun Vehicle.toForm() = VehicleFormState(
        nickname = nickname,
        make = make,
        model = model,
        year = year.toString(),
        licensePlate = licensePlate.orEmpty(),
        vin = vin.orEmpty(),
        color = color.orEmpty(),
        odometer = currentOdometer.toString(),
        odometerAtPurchase = odometerAtPurchase?.toString().orEmpty(),
        purchaseDate = purchaseDate?.atZone(zone)?.toLocalDate(),
        purchasePrice = purchasePrice?.let { java.math.BigDecimal.valueOf(it).stripTrailingZeros().toPlainString() }.orEmpty(),
        engineOilType = engineOilType.orEmpty(),
        tireSizeFront = tireSizeFront.orEmpty(),
        tireSizeRear = tireSizeRear.orEmpty(),
        fuelType = fuelType?.wire.orEmpty(),
        weightClass = weightClass.orEmpty(),
        notes = notes.orEmpty(),
    )
}
