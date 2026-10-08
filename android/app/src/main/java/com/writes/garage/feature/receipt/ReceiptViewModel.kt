package com.writes.garage.feature.receipt

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.ProfileRepository
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.observeActiveVehicle
import com.writes.garage.core.model.ReceiptProposal
import com.writes.garage.core.model.ReceiptQuota
import com.writes.garage.core.model.Vehicle
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

/** A receipt photo chosen from the Photo Picker or captured into a FileProvider uri. */
data class PickedImage(val uri: String, val mimeType: String = "image/jpeg")

data class ReceiptUiState(
    val hasConsent: Boolean = false,
    /** Shows the consent dialog (a scan was attempted without consent). */
    val needsConsent: Boolean = false,
    val quota: ReceiptQuota? = null,
    val busy: Boolean = false,
    val busyLabel: String? = null,
    val proposal: ReceiptProposal? = null,
    val form: ProposalFormState? = null,
    /** The reviewed entry was written; only the server quota commit is still outstanding (retry-safe). */
    val entrySaved: Boolean = false,
    val saved: Boolean = false,
    val error: String? = null,
) {
    /** Scanning is blocked once both the base allowance and purchased credits are exhausted. */
    val quotaExhausted: Boolean get() = quota?.let { it.remaining <= 0 && it.creditBalance <= 0 } == true
}

/**
 * AI-consent gate -> capture/pick image -> receiptQuickAdd -> editable proposal -> confirm:
 * upload image, save the reviewed entry, then `confirmReceiptScan {token}`. Nothing is written before confirm.
 */
class ReceiptViewModel(
    private val vehicles: VehicleRepository,
    private val profile: ProfileRepository,
    private val storage: StorageRepository,
    private val functions: FunctionsGateway,
    private val entries: EntryRepository,
    /** Attachments are a Pro feature (the server deletes a free user's uploads), so free users get none. */
    private val isPro: () -> Boolean,
    private val zone: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    private val _state = MutableStateFlow(ReceiptUiState())
    val state: StateFlow<ReceiptUiState> = _state.asStateFlow()

    private var images: List<PickedImage> = emptyList()
    private var pendingAfterConsent: List<PickedImage>? = null
    private var uploadedPaths: List<String> = emptyList()
    private var vehicle: Vehicle? = null

    init {
        viewModelScope.launch {
            profile.observeProfile()
                .catch { e -> _state.update { it.copy(error = e.message ?: "Couldn't load your AI consent.") } }
                .collect { p -> _state.update { it.copy(hasConsent = p?.hasAiConsent == true) } }
        }
        refreshQuota()
    }

    fun refreshQuota() {
        viewModelScope.launch {
            runCatching { functions.receiptQuotaStatus() }.onSuccess { q -> _state.update { it.copy(quota = q) } }
        }
    }

    fun grantConsent() {
        viewModelScope.launch {
            runCatching { profile.setAiConsent(true) }.onFailure { e ->
                _state.update { it.copy(needsConsent = false, error = e.message ?: "Couldn't save your AI consent.") }
                return@launch
            }
            _state.update { it.copy(needsConsent = false, hasConsent = true) }
            pendingAfterConsent?.also { pendingAfterConsent = null }?.let { scan(it) }
        }
    }

    fun dismissConsent() {
        pendingAfterConsent = null
        _state.update { it.copy(needsConsent = false) }
    }

    /** The consent gate: callers should check this before launching the picker/camera. */
    fun requireConsent(): Boolean {
        if (_state.value.hasConsent) return true
        _state.update { it.copy(needsConsent = true) }
        return false
    }

    fun scan(picked: List<PickedImage>) {
        if (picked.isEmpty() || _state.value.busy) return
        viewModelScope.launch {
            if (profile.observeProfile().first()?.hasAiConsent != true) {
                pendingAfterConsent = picked
                _state.update { it.copy(needsConsent = true, hasConsent = false) }
                return@launch
            }
            if (_state.value.quotaExhausted) {
                _state.update { it.copy(error = "No receipt scans left. Upgrade or buy credits to continue.") }
                return@launch
            }
            val active = vehicles.observeActiveVehicle().first()
            if (active == null) {
                _state.update { it.copy(error = "Add a vehicle first.") }
                return@launch
            }
            vehicle = active
            _state.update { it.copy(busy = true, busyLabel = "Reading receipt...", error = null) }
            runCatching {
                val encoded = picked.map { storage.readAsBase64(it.uri, it.mimeType) }
                functions.receiptQuickAdd(active, imagesBase64 = encoded)
            }.onSuccess { p ->
                images = picked
                uploadedPaths = emptyList()
                _state.update {
                    it.copy(
                        busy = false, busyLabel = null, proposal = p, entrySaved = false, saved = false,
                        form = ProposalForm.fromReceipt(p, active.currentOdometer, zone),
                        quota = p.quota ?: it.quota,
                    )
                }
            }.onFailure { e -> _state.update { it.copy(busy = false, busyLabel = null, error = e.message ?: "Couldn't read that receipt.") } }
        }
    }

    fun updateForm(form: ProposalFormState) {
        if (_state.value.entrySaved) return
        _state.update { it.copy(form = form) }
    }

    fun confirm() {
        val s = _state.value
        val p = s.proposal ?: return
        val form = s.form ?: return
        if (s.busy) return
        if (!s.entrySaved) {
            val errors = ProposalForm.validate(form)
            if (errors.isNotEmpty()) {
                _state.update { it.copy(form = form.copy(errors = errors), error = "Fix the highlighted fields.") }
                return
            }
        }
        viewModelScope.launch {
            _state.update { it.copy(busy = true, busyLabel = "Saving...", error = null) }
            runCatching {
                if (!_state.value.entrySaved) {
                    if (isPro() && uploadedPaths.isEmpty() && images.isNotEmpty()) {
                        uploadedPaths = images.map { storage.uploadAttachment(p.vehicleId, it.uri, it.mimeType) }
                    }
                    // Like iOS: the client saves the reviewed entry first, then commits the server quota reservation.
                    entries.addEntry(ProposalForm.toEntry(form, p.vehicleId, uploadedPaths, zone))
                    bumpOdometer(p.vehicleId, com.writes.garage.core.domain.Validators.parseOdometer(form.odometer) ?: 0)
                    _state.update { it.copy(entrySaved = true) }
                }
                functions.confirmReceiptScan(p.token)
            }.onSuccess { quota ->
                _state.update {
                    it.copy(busy = false, busyLabel = null, proposal = null, form = null, entrySaved = false, saved = true, quota = quota)
                }
                images = emptyList()
                uploadedPaths = emptyList()
            }.onFailure { e ->
                val msg = if (_state.value.entrySaved) {
                    "Entry saved, but the scan couldn't be confirmed. Tap Confirm to retry. (${e.message})"
                } else {
                    e.message ?: "Couldn't save the entry."
                }
                _state.update { it.copy(busy = false, busyLabel = null, error = msg) }
            }
        }
    }

    /** Throws the proposal away. Not allowed once the entry was written. */
    fun discard() {
        if (_state.value.entrySaved) return
        images = emptyList()
        uploadedPaths = emptyList()
        _state.update { it.copy(proposal = null, form = null, error = null) }
    }

    fun scanAnother() = _state.update { it.copy(saved = false, error = null) }

    fun reportError(message: String) = _state.update { it.copy(error = message) }

    private suspend fun bumpOdometer(vehicleId: String, reading: Int) {
        runCatching {
            val v = vehicles.observeVehicle(vehicleId).first() ?: return
            if (reading > v.currentOdometer) vehicles.updateVehicle(v.copy(currentOdometer = reading))
        }
    }
}
