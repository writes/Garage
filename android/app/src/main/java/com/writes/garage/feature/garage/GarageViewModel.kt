package com.writes.garage.feature.garage

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.PurchaseRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.domain.VehicleLimitPolicy
import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class GarageUiState(
    val vehicles: List<Vehicle> = emptyList(),
    val activeId: String? = null,
    val isPro: Boolean = false,
) {
    val canAdd: Boolean get() = VehicleLimitPolicy.canAddVehicle(vehicles.size, isPro)
    val limit: Int get() = VehicleLimitPolicy.limitFor(isPro)
}

class GarageViewModel(private val repo: VehicleRepository, purchases: PurchaseRepository) : ViewModel() {
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    val state: StateFlow<GarageUiState> = combine(
        repo.observeVehicles(), repo.activeVehicleId, purchases.entitlement,
    ) { v, active, ent -> GarageUiState(v, active ?: v.firstOrNull()?.id, ent.isPro) }
        .catch { e ->
            _error.value = e.message ?: "Couldn't load your vehicles."
            emit(GarageUiState())
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), GarageUiState())

    fun select(id: String) {
        viewModelScope.launch { runCatching { repo.setActiveVehicle(id) } }
    }

    /** Soft delete (tombstone); the server purges it afterwards. */
    fun delete(id: String) {
        viewModelScope.launch {
            _error.value = null
            runCatching { repo.deleteVehicle(id) }
                .onFailure { _error.value = it.message ?: "Could not delete the vehicle." }
        }
    }

    fun dismissError() {
        _error.value = null
    }
}
