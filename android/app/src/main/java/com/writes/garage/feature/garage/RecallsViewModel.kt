package com.writes.garage.feature.garage

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.RecallRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.firebase.GatewayException
import com.writes.garage.core.domain.RecallRules
import com.writes.garage.core.domain.Validators
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.RecallSource
import com.writes.garage.core.model.RecallStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant

data class RecallsUiState(
    val recalls: List<Recall> = emptyList(),
    val checking: Boolean = false,
    /** "Checked 2015 Audi SQ5 - 1 recall on file." after a successful lookup (also when it found nothing). */
    val lastCheck: String? = null,
    val error: String? = null,
) {
    val outstandingCount: Int get() = RecallRules.outstandingCount(recalls)
    val urgent: List<Recall> get() = RecallRules.urgent(recalls)
}

/** Stored recalls for one vehicle + the NHTSA lookup, mark-completed and manual add. */
class RecallsViewModel(
    private val functions: FunctionsGateway,
    private val vehicles: VehicleRepository,
    private val repo: RecallRepository,
    private val vehicleId: String,
    private val clock: () -> Instant = Instant::now,
) : ViewModel() {
    private val _state = MutableStateFlow(RecallsUiState())
    val state: StateFlow<RecallsUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            repo.observe(vehicleId)
                .catch { e -> _state.update { it.copy(error = e.message ?: "Couldn't load recalls.") } }
                .collect { list -> _state.update { it.copy(recalls = RecallRules.ordered(list)) } }
        }
    }

    /** Looks the VIN up and stores anything new (known campaign numbers are never overwritten). */
    fun check() {
        if (_state.value.checking) return
        viewModelScope.launch {
            _state.update { it.copy(checking = true, error = null) }
            val vehicle = vehicles.observeVehicle(vehicleId).first()
            val vin = vehicle?.vin?.trim().orEmpty()
            if (vehicle == null || !Validators.isValidVin(vin)) {
                _state.update { it.copy(checking = false, error = "Add a valid 17-character VIN to this vehicle to check recalls.") }
                return@launch
            }
            runCatching {
                val fetched = functions.lookupRecalls(vehicleId, vin)
                // Read the stored set now: the live snapshot in _state may not have arrived yet (would re-insert completed rows).
                val stored = repo.observe(vehicleId).first()
                val fresh = RecallRules.newRecalls(stored, fetched, clock())
                fresh.forEach { repo.upsert(it) }
                RecallRules.summary(vehicle, fetched.size)
            }.onSuccess { summary -> _state.update { it.copy(checking = false, lastCheck = summary) } }
                .onFailure { e ->
                    val msg = if (e is GatewayException && e.kind == GatewayException.Kind.VIN_NOT_RECOGNISED) {
                        "NHTSA did not recognise that VIN. Check it for typos."
                    } else {
                        e.message ?: "Couldn't check recalls."
                    }
                    _state.update { it.copy(checking = false, error = msg) }
                }
        }
    }

    fun markCompleted(recall: Recall, shop: String, odometerText: String, date: Instant) {
        val odo = odometerText.trim().takeIf { it.isNotEmpty() }?.let { Validators.parseOdometer(it) }
        if (odometerText.isNotBlank() && odo == null) {
            _state.update { it.copy(error = "Enter an odometer between 0 and 2,000,000.") }
            return
        }
        save { repo.upsert(RecallRules.markCompleted(recall, shop, odo, date)) }
    }

    fun markNotApplicable(recall: Recall) = save { repo.upsert(recall.copy(status = RecallStatus.NOT_APPLICABLE)) }

    fun reopen(recall: Recall) = save {
        repo.upsert(recall.copy(status = RecallStatus.OUTSTANDING, completedDate = null, completedShop = null, completedOdometer = null))
    }

    fun addManual(title: String, campaign: String, component: String, description: String): Boolean {
        if (title.isBlank()) {
            _state.update { it.copy(error = "Give the recall a title.") }
            return false
        }
        save {
            repo.upsert(
                Recall(
                    id = "", vehicleId = vehicleId, campaignNumber = campaign.trim().ifEmpty { null }, title = title.trim(),
                    description = description.trim().ifEmpty { null }, componentAffected = component.trim().ifEmpty { null },
                    status = RecallStatus.OUTSTANDING, recallSource = RecallSource.MANUAL, createdAt = clock(),
                ),
            )
        }
        return true
    }

    fun dismissError() = _state.update { it.copy(error = null) }

    private fun save(block: suspend () -> Unit) {
        viewModelScope.launch {
            runCatching { block() }.onFailure { e -> _state.update { it.copy(error = e.message ?: "Couldn't save the recall.") } }
        }
    }
}
