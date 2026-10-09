package com.writes.garage.feature.garage

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.PurchaseRepository
import com.writes.garage.core.data.RecallRepository
import com.writes.garage.core.domain.RecallRules
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
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
    /** vehicleId -> outstanding recall count (drives the badge on each vehicle card). */
    val openRecalls: Map<String, Int> = emptyMap(),
) {
    val canAdd: Boolean get() = VehicleLimitPolicy.canAddVehicle(vehicles.size, isPro)
    val limit: Int get() = VehicleLimitPolicy.limitFor(isPro)
}

@OptIn(ExperimentalCoroutinesApi::class)
class GarageViewModel(
    private val repo: VehicleRepository,
    purchases: PurchaseRepository,
    recalls: RecallRepository? = null,
) : ViewModel() {
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    val state: StateFlow<GarageUiState> = combine(
        repo.observeVehicles(), repo.activeVehicleId, purchases.entitlement,
        repo.observeVehicles().flatMapLatest { vs -> openRecallCounts(recalls, vs.map { it.id }) },
    ) { v, active, ent, open -> GarageUiState(v, active ?: v.firstOrNull()?.id, ent.isPro, open) }
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

    private fun openRecallCounts(recalls: RecallRepository?, ids: List<String>): Flow<Map<String, Int>> {
        if (recalls == null || ids.isEmpty()) return flowOf(emptyMap())
        return combine(ids.map { id -> recalls.observe(id).catch { emit(emptyList()) } }) { lists ->
            ids.zip(lists.toList()).associate { (id, l) -> id to RecallRules.outstandingCount(l) }
        }
    }
}
