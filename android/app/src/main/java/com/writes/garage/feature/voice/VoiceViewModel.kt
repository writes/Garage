package com.writes.garage.feature.voice

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.ProfileRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.observeActiveVehicle
import com.writes.garage.core.domain.Validators
import com.writes.garage.core.model.Vehicle
import com.writes.garage.core.model.VoiceProposal
import com.writes.garage.feature.shared.ProposalForm
import com.writes.garage.feature.shared.ProposalFormState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.ZoneId

data class VoiceUiState(
    val hasConsent: Boolean = false,
    val needsConsent: Boolean = false,
    val transcript: String = "",
    /** Live partial recognition text while [listening]. */
    val partial: String = "",
    val listening: Boolean = false,
    val busy: Boolean = false,
    val proposal: VoiceProposal? = null,
    val form: ProposalFormState? = null,
    val saved: Boolean = false,
    val error: String? = null,
)

/** speech (SpeechRecognizer) -> voiceQuickAdd -> editable proposal -> save. Nothing is written before confirm. */
class VoiceViewModel(
    private val vehicles: VehicleRepository,
    private val profile: ProfileRepository,
    private val functions: FunctionsGateway,
    private val entries: EntryRepository,
    private val zone: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    private val _state = MutableStateFlow(VoiceUiState())
    val state: StateFlow<VoiceUiState> = _state.asStateFlow()

    private var vehicle: Vehicle? = null
    private var interpretAfterConsent = false

    init {
        viewModelScope.launch {
            profile.observeProfile()
                .catch { e -> _state.update { it.copy(error = e.message ?: "Couldn't load your AI consent.") } }
                .collect { p -> _state.update { it.copy(hasConsent = p?.hasAiConsent == true) } }
        }
    }

    fun setTranscript(text: String) = _state.update { it.copy(transcript = text, saved = false, error = null) }

    // --- speech recognizer callbacks (invoked from the screen's SpeechController) ---

    fun onListeningStarted() = _state.update { it.copy(listening = true, partial = "", error = null, saved = false) }

    fun onPartial(text: String) = _state.update { it.copy(partial = text) }

    fun onSpeechResult(text: String) = _state.update {
        it.copy(listening = false, partial = "", transcript = text.trim().ifEmpty { it.transcript })
    }

    fun onSpeechError(message: String) = _state.update { it.copy(listening = false, partial = "", error = message) }

    fun onListeningStopped() = _state.update { it.copy(listening = false, partial = "") }

    fun reportError(message: String) = _state.update { it.copy(error = message) }

    // --- consent ---

    fun grantConsent() {
        viewModelScope.launch {
            runCatching { profile.setAiConsent(true) }.onFailure { e ->
                interpretAfterConsent = false
                _state.update { it.copy(needsConsent = false, error = e.message ?: "Couldn't save your AI consent.") }
                return@launch
            }
            _state.update { it.copy(needsConsent = false, hasConsent = true) }
            if (interpretAfterConsent) {
                interpretAfterConsent = false
                interpret()
            }
        }
    }

    fun dismissConsent() {
        interpretAfterConsent = false
        _state.update { it.copy(needsConsent = false) }
    }

    fun interpret() {
        val text = _state.value.transcript.trim()
        if (text.isEmpty() || _state.value.busy) return
        viewModelScope.launch {
            if (profile.observeProfile().first()?.hasAiConsent != true) {
                interpretAfterConsent = true
                _state.update { it.copy(needsConsent = true, hasConsent = false) }
                return@launch
            }
            val active = vehicles.observeActiveVehicle().first()
            if (active == null) {
                _state.update { it.copy(error = "Add a vehicle first.") }
                return@launch
            }
            vehicle = active
            _state.update { it.copy(busy = true, error = null) }
            runCatching { functions.voiceQuickAdd(active, text) }
                .onSuccess { p ->
                    _state.update {
                        it.copy(busy = false, proposal = p, form = ProposalForm.fromVoice(p, active.currentOdometer, zone), saved = false)
                    }
                }
                .onFailure { e -> _state.update { it.copy(busy = false, error = e.message ?: "Couldn't interpret that.") } }
        }
    }

    fun updateForm(form: ProposalFormState) = _state.update { it.copy(form = form) }

    /** Nothing is written until the user confirms the (possibly edited) proposal. */
    fun confirm() {
        val s = _state.value
        val p = s.proposal ?: return
        val form = s.form ?: return
        if (s.busy) return
        val errors = ProposalForm.validate(form)
        if (errors.isNotEmpty()) {
            _state.update { it.copy(form = form.copy(errors = errors), error = "Fix the highlighted fields.") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(busy = true, error = null) }
            runCatching {
                entries.addEntry(ProposalForm.toEntry(form, p.vehicleId, zone = zone))
                bumpOdometer(p.vehicleId, Validators.parseOdometer(form.odometer) ?: 0)
            }.onSuccess { _state.update { it.copy(busy = false, proposal = null, form = null, transcript = "", saved = true) } }
                .onFailure { e -> _state.update { it.copy(busy = false, error = e.message ?: "Couldn't save the entry.") } }
        }
    }

    fun discard() = _state.update { it.copy(proposal = null, form = null, error = null) }

    fun recordAnother() = _state.update { it.copy(saved = false, error = null) }

    private suspend fun bumpOdometer(vehicleId: String, reading: Int) {
        runCatching {
            val v = vehicles.observeVehicle(vehicleId).first() ?: return
            if (reading > v.currentOdometer) vehicles.updateVehicle(v.copy(currentOdometer = reading))
        }
    }
}
