package com.writes.garage.feature.garage

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.domain.Validators
import com.writes.garage.core.model.Recall
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

data class RecallsUiState(val recalls: List<Recall> = emptyList(), val loading: Boolean = true, val error: String? = null)

class RecallsViewModel(
    private val functions: FunctionsGateway,
    private val vehicles: VehicleRepository,
    private val vehicleId: String,
) : ViewModel() {
    private val _state = MutableStateFlow(RecallsUiState())
    val state: StateFlow<RecallsUiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(loading = true, error = null)
            val vin = vehicles.observeVehicle(vehicleId).first()?.vin?.trim().orEmpty()
            if (!Validators.isValidVin(vin)) {
                _state.value = RecallsUiState(loading = false, error = "Add a valid 17-character VIN to this vehicle to check recalls.")
                return@launch
            }
            runCatching { functions.lookupRecalls(vehicleId, vin) }
                .onSuccess { _state.value = RecallsUiState(it, loading = false) }
                .onFailure { _state.value = RecallsUiState(loading = false, error = it.message) }
        }
    }
}
