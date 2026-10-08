package com.writes.garage.feature.receipt

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.AnalyticsEvents
import com.writes.garage.core.data.AnalyticsSink
import com.writes.garage.core.data.CreditsOutcome
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.NoopAnalyticsSink
import com.writes.garage.core.data.PurchaseRepository
import com.writes.garage.core.data.ReceiptCreditsCoordinator
import com.writes.garage.core.domain.PdfPreflight
import com.writes.garage.core.model.CreditsOffer
import com.writes.garage.core.review.NoopReviewMoments
import com.writes.garage.core.review.ReviewMoment
import com.writes.garage.core.review.ReviewMoments
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.ProfileRepository
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.data.firebase.GatewayException
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.syncOdometer
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
import java.util.UUID

enum class CreditsState { IDLE, PURCHASING, WAITING, GRANTED, REFUNDED, DELAYED }

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
    /** The credits pack as the store sells it; null when unavailable. */
    val creditsOffer: CreditsOffer? = null,
    val creditsState: CreditsState = CreditsState.IDLE,
    val creditsMessage: String? = null,
    /** The server said the free allowance is used up / Pro is required: the screen routes to the paywall. */
    val needsUpgrade: Boolean = false,
) {
    /** Offer the pack once the allowance is used up, only while the server capability is on and the product is fetchable. */
    val showCreditsOffer: Boolean
        get() = quotaExhausted && creditsOffer != null && quota?.creditsPurchasingEnabled == true

    /** A refund left credits owed; shown only with the server capability on. */
    val creditsDeficit: Int get() = if (quota?.creditsPurchasingEnabled == true) quota.creditsDeficit else 0

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
    /** Live builds: the server deletes uploads unless `users/{uid}.subscription` is active, so require that too. */
    private val requireServerPro: Boolean = false,
    /** Receipt-credits purchase (null = not offered). */
    private val credits: ReceiptCreditsCoordinator? = null,
    private val purchases: PurchaseRepository? = null,
    private val uid: () -> String? = { null },
    private val analytics: AnalyticsSink = NoopAnalyticsSink,
    private val reviews: ReviewMoments = NoopReviewMoments,
    /** Deletes a camera capture once it is no longer needed (they hold personal data). */
    private val releaseCapture: (String) -> Unit = {},
    private val zone: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    private val _state = MutableStateFlow(ReceiptUiState())
    val state: StateFlow<ReceiptUiState> = _state.asStateFlow()

    private var images: List<PickedImage> = emptyList()
    private var pendingAfterConsent: List<PickedImage>? = null
    private var uploadedPaths: List<String> = emptyList()
    private var vehicle: Vehicle? = null
    /** Reserved before the first upload so a retry reuses the same Storage folder / entry id. */
    private var reservedEntryId: String? = null

    init {
        viewModelScope.launch {
            profile.observeProfile()
                .catch { e -> _state.update { it.copy(error = e.message ?: "Couldn't load your AI consent.") } }
                .collect { p -> _state.update { it.copy(hasConsent = p?.hasAiConsent == true) } }
        }
        refreshQuota()
        loadCreditsOffer()
        resumeCredits()
    }

    // --- receipt credits ---

    private fun loadCreditsOffer() {
        val p = purchases ?: return
        viewModelScope.launch {
            runCatching { p.receiptCreditsOffer() }.onSuccess { o -> _state.update { it.copy(creditsOffer = o) } }
        }
    }

    /** An earlier purchase whose grant never confirmed (process death, slow webhook) resumes here. */
    private fun resumeCredits() {
        val c = credits ?: return
        val u = uid() ?: return
        viewModelScope.launch {
            val outcome = c.resume(u) ?: return@launch
            applyCredits(outcome)
        }
    }

    fun buyCredits() {
        val c = credits ?: return
        val u = uid() ?: run {
            _state.update { it.copy(creditsMessage = "Sign in to buy credits.") }
            return
        }
        if (_state.value.creditsState == CreditsState.PURCHASING || _state.value.creditsState == CreditsState.WAITING) return
        viewModelScope.launch {
            _state.update { it.copy(creditsState = CreditsState.PURCHASING, creditsMessage = null) }
            analytics.log("receipt_credits_purchase_started", AnalyticsEvents.params())
            val outcome = c.purchase(u) { _state.update { s -> s.copy(creditsState = CreditsState.WAITING) } }
            applyCredits(outcome)
        }
    }

    private fun applyCredits(outcome: CreditsOutcome) = _state.update {
        when (outcome) {
            is CreditsOutcome.Granted -> {
                analytics.log("receipt_credits_grant_confirmed", AnalyticsEvents.params())
                it.copy(creditsState = CreditsState.GRANTED, quota = outcome.quota, creditsMessage = "Credits added.")
            }
            is CreditsOutcome.Refunded -> {
                analytics.log("receipt_credits_refund_observed", AnalyticsEvents.params())
                it.copy(creditsState = CreditsState.REFUNDED, quota = outcome.quota, creditsMessage = "That purchase was refunded, so no credits were added.")
            }
            CreditsOutcome.Delayed -> {
                analytics.log("receipt_credits_grant_delayed", AnalyticsEvents.params())
                it.copy(
                    creditsState = CreditsState.DELAYED,
                    creditsMessage = "Your purchase went through but the credits haven't arrived yet. Reopen this screen in a minute; you won't be charged again.",
                )
            }
            CreditsOutcome.Cancelled -> it.copy(creditsState = CreditsState.IDLE)
            CreditsOutcome.Pending -> it.copy(creditsState = CreditsState.IDLE, creditsMessage = "Your purchase is pending approval. Credits appear once it completes.")
            CreditsOutcome.Unavailable -> it.copy(creditsState = CreditsState.IDLE, creditsMessage = "Credits aren't available right now.")
            is CreditsOutcome.Failed -> {
                analytics.log("receipt_credits_purchase_failed", AnalyticsEvents.params())
                it.copy(creditsState = CreditsState.IDLE, creditsMessage = outcome.message)
            }
            CreditsOutcome.IdentityMismatch -> it.copy(
                creditsState = CreditsState.IDLE,
                creditsMessage = "We couldn't verify your account with the store, so you weren't charged. Sign out and back in, then try again.",
            )
            CreditsOutcome.IdentityChangedAfterPurchase -> {
                analytics.log("receipt_credits_grant_delayed", AnalyticsEvents.params())
                it.copy(
                    creditsState = CreditsState.DELAYED,
                    creditsMessage = "Your purchase went through but your account changed during checkout. Sign back in to the account that paid and the credits will appear; you won't be charged again.",
                )
            }
        }
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
        val pdfs = picked.count { it.mimeType == "application/pdf" }
        if (pdfs > 0 && picked.size > 1) {
            _state.update { it.copy(error = "Choose one PDF or up to $MAX_IMAGES photos, not both.") }
            return
        }
        if (picked.size > MAX_IMAGES) {
            _state.update { it.copy(error = "Choose up to $MAX_IMAGES photos.") }
            return
        }
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
                if (pdfs == 1) {
                    // Local preflight (size / signature / pages) before anything leaves the device.
                    val bytes = storage.readBytes(picked.single().uri, PdfPreflight.MAX_RAW_BYTES + 1)
                    when (val pre = PdfPreflight.check(bytes)) {
                        is PdfPreflight.Result.Rejected -> throw IllegalArgumentException(pre.message)
                        is PdfPreflight.Result.Ok -> functions.receiptQuickAdd(active, pdfBase64 = pre.base64)
                    }
                } else {
                    val encoded = picked.map { storage.readAsBase64(it.uri, it.mimeType) }
                    if (encoded.any { it.length > MAX_IMAGE_BASE64 }) throw IllegalArgumentException("Choose a smaller photo.")
                    functions.receiptQuickAdd(active, imagesBase64 = encoded)
                }
            }.onSuccess { p ->
                images = picked
                uploadedPaths = emptyList()
                reservedEntryId = null
                _state.update {
                    it.copy(
                        busy = false, busyLabel = null, proposal = p, entrySaved = false, saved = false,
                        form = ProposalForm.fromReceipt(p, active.currentOdometer, zone),
                        quota = p.quota ?: it.quota,
                    )
                }
            }.onFailure { e ->
                picked.forEach { releaseCapture(it.uri) }
                refreshQuota()
                _state.update { routeFailure(it.copy(busy = false, busyLabel = null), e, "Couldn't read that receipt.") }
            }
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
                    val entryId = reservedEntryId ?: UUID.randomUUID().toString().also { reservedEntryId = it }
                    if (canAttach()) {
                        // One at a time, remembering each: a partial failure keeps what landed and a retry resumes after it.
                        for (i in uploadedPaths.size until images.size) {
                            val img = images[i]
                            uploadedPaths = uploadedPaths + storage.uploadAttachment(p.vehicleId, img.uri, img.mimeType, entryId)
                        }
                    }
                    // Like iOS: the client saves the reviewed entry first, then commits the server quota reservation.
                    entries.addEntry(ProposalForm.toEntry(form, p.vehicleId, uploadedPaths, zone, entryId))
                    vehicles.syncOdometer(p.vehicleId, com.writes.garage.core.domain.Validators.parseOdometer(form.odometer) ?: 0)
                    _state.update { it.copy(entrySaved = true) }
                }
                functions.confirmReceiptScan(p.token)
            }.onSuccess { quota ->
                _state.update {
                    it.copy(busy = false, busyLabel = null, proposal = null, form = null, entrySaved = false, saved = true, quota = quota)
                }
                images.forEach { releaseCapture(it.uri) }
                analytics.log(AnalyticsEvents.RECEIPT_ENTRY_CONFIRMED, AnalyticsEvents.params())
                reviews.record(ReviewMoment.ENTRY_LOGGED)
                images = emptyList()
                uploadedPaths = emptyList()
                reservedEntryId = null
            }.onFailure { e ->
                val msg = if (_state.value.entrySaved) {
                    "Entry saved, but the scan couldn't be confirmed. Tap Confirm to retry. (${e.message})"
                } else {
                    e.message ?: "Couldn't save the entry."
                }
                _state.update {
                    // A server "exhausted" outcome is final, not retryable: keep the retry copy only for transient failures.
                    val kind = (e as? GatewayException)?.kind
                    if (kind in ROUTED_KINDS) routeFailure(it.copy(busy = false, busyLabel = null), e, msg)
                    else it.copy(busy = false, busyLabel = null, error = msg)
                }
            }
        }
    }

    /** Throws the proposal away. Not allowed once the entry was written. */
    fun discard() {
        if (_state.value.entrySaved) return
        images.forEach { releaseCapture(it.uri) }
        images = emptyList()
        // Uploaded for a retry that will never come: nothing references them, so don't leave them in Storage.
        val orphans = uploadedPaths
        if (orphans.isNotEmpty()) viewModelScope.launch { orphans.forEach { runCatching { storage.deleteAttachment(it) } } }
        uploadedPaths = emptyList()
        reservedEntryId = null
        _state.update { it.copy(proposal = null, form = null, error = null) }
    }

    private suspend fun canAttach(): Boolean =
        isPro() && (!requireServerPro || profile.observeProfile().first()?.serverIsPro == true)

    companion object {
        /** Receipt photos per scan (iOS `ReceiptPreflighter.maxPages`). */
        const val MAX_IMAGES = 2

        /** Base64 ceiling for one downscaled photo (iOS `maxImageBase64Bytes`). */
        const val MAX_IMAGE_BASE64 = 4 * 1024 * 1024

        private val ROUTED_KINDS = setOf(
            GatewayException.Kind.FREE_LIFETIME_EXHAUSTED, GatewayException.Kind.PRO_REQUIRED, GatewayException.Kind.PRO_MONTH_EXHAUSTED,
        )
    }

    fun upgradeHandled() = _state.update { it.copy(needsUpgrade = false) }

    /** Maps the documented server outcomes to product routing; anything else shows the raw message. */
    private fun routeFailure(s: ReceiptUiState, e: Throwable, fallback: String): ReceiptUiState {
        val g = e as? GatewayException
        return when (g?.kind) {
            GatewayException.Kind.FREE_LIFETIME_EXHAUSTED, GatewayException.Kind.PRO_REQUIRED ->
                s.copy(needsUpgrade = true, error = "You've used your free receipt scans. Upgrade to Garage Pro or buy credits to keep scanning.")
            GatewayException.Kind.PRO_MONTH_EXHAUSTED ->
                s.copy(error = "You've used this month's receipt scans." + (g.resetAt?.let { " They reset on ${it.take(10)}." } ?: "") + " Buy credits to keep scanning.")
            GatewayException.Kind.NOT_A_RECEIPT -> s.copy(error = "That doesn't look like a receipt. Try a clearer photo.")
            else -> s.copy(error = e.message ?: fallback)
        }
    }

    fun scanAnother() = _state.update { it.copy(saved = false, error = null) }

    fun reportError(message: String) = _state.update { it.copy(error = message) }
}
