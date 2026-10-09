package com.writes.garage.feature.entry

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.AnalyticsEvents
import com.writes.garage.core.data.AnalyticsSink
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.ProfileRepository
import com.writes.garage.core.data.firebase.GatewayException
import com.writes.garage.core.domain.OilAnalysisImport
import com.writes.garage.core.domain.PdfPreflight
import com.writes.garage.core.review.NoopReviewMoments
import com.writes.garage.core.review.ReviewMoment
import com.writes.garage.core.review.ReviewMoments
import com.writes.garage.core.data.NoopAnalyticsSink
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.data.WearSync
import com.writes.garage.core.domain.AttachmentRules
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.syncOdometer
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
import java.util.UUID
import kotlin.math.round

/** Add/edit entry form: type picker, shared fields and the per-type detail fields from [EntryFieldSpecs]. */
class EntryEditViewModel(
    private val entries: EntryRepository,
    private val vehicles: VehicleRepository,
    private val vehicleId: String?,
    private val entryId: String?,
    private val zone: ZoneId = ZoneId.systemDefault(),
    today: () -> LocalDate = { LocalDate.now() },
    /** Wear snapshots follow brake/tire entries (iOS `WearSnapshotFactory`); null = not tracked. */
    private val wear: WearSync? = null,
    /** Attachments need Storage; null disables the picker. */
    private val storage: StorageRepository? = null,
    /** Attachments are a Pro feature (the server removes a free user's uploads). */
    private val canAttach: suspend () -> Boolean = { false },
    private val analytics: AnalyticsSink = NoopAnalyticsSink,
    /** Oil-analysis PDF import needs AI consent (profile) and the callable (functions); either null disables it. */
    private val profile: ProfileRepository? = null,
    private val functions: FunctionsGateway? = null,
    private val reviews: ReviewMoments = NoopReviewMoments,
) : ViewModel() {
    private val _state = MutableStateFlow(EntryFormState(date = today()))
    val state: StateFlow<EntryFormState> = _state.asStateFlow()

    private var existing: Entry? = null
    private var known: List<Entry> = emptyList()
    private val removedPaths = mutableListOf<String>()

    val isEdit: Boolean get() = entryId != null

    private var reservedNewEntryId: String? = null

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
                    attachmentPaths = old.attachmentPaths,
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

    // --- oil analysis PDF import ---

    val importAvailable: Boolean get() = functions != null && storage != null

    private var pendingImportUri: String? = null

    /** Picks a lab PDF: preflight (size/signature/pages), AI-consent gate, `parseOilAnalysis`, then prefill the form. */
    fun importOilAnalysis(uri: String) {
        if (_state.value.importing || _state.value.type != EntryType.OIL_ANALYSIS) return
        viewModelScope.launch {
            if (profile?.observeProfile()?.first()?.hasAiConsent != true) {
                pendingImportUri = uri
                _state.update { it.copy(needsAiConsent = true) }
                return@launch
            }
            runImport(uri)
        }
    }

    fun grantImportConsent() {
        viewModelScope.launch {
            runCatching { profile?.setAiConsent(true) }.onFailure { e ->
                pendingImportUri = null
                _state.update { it.copy(needsAiConsent = false, formError = e.message ?: "Couldn't save your AI consent.") }
                return@launch
            }
            _state.update { it.copy(needsAiConsent = false) }
            pendingImportUri?.also { pendingImportUri = null }?.let { runImport(it) }
        }
    }

    fun dismissImportConsent() {
        pendingImportUri = null
        _state.update { it.copy(needsAiConsent = false) }
    }

    fun upgradeHandled() = _state.update { it.copy(needsUpgrade = false) }

    private suspend fun runImport(uri: String) {
        val repo = storage ?: return
        val fn = functions ?: return
        _state.update { it.copy(importing = true, importNotice = null, formError = null) }
        try {
            val bytes = repo.readBytes(uri, PdfPreflight.MAX_RAW_BYTES + 1)
            val pre = PdfPreflight.check(bytes)
            if (pre is PdfPreflight.Result.Rejected) {
                _state.update { it.copy(importing = false, formError = pre.message) }
                return
            }
            val prefill = OilAnalysisImport.prefill(fn.parseOilAnalysis((pre as PdfPreflight.Result.Ok).base64))
            if (!OilAnalysisImport.isUsable(prefill)) {
                _state.update { it.copy(importing = false, formError = "That doesn't look like an oil analysis report. Enter the values by hand.") }
                return
            }
            _state.update {
                it.copy(
                    importing = false,
                    details = it.details + prefill,
                    errors = it.errors - prefill.keys.map(EntryFormValidator::detailKey).toSet(),
                    importNotice = "Imported ${prefill.size} field${if (prefill.size == 1) "" else "s"} from the PDF. Review them before saving.",
                )
            }
            analytics.log(AnalyticsEvents.OIL_ANALYSIS_SUCCEEDED, AnalyticsEvents.params())
            reviews.record(ReviewMoment.OIL_ANALYSIS_SUCCEEDED)
        } catch (e: GatewayException) {
            _state.update {
                when (e.kind) {
                    GatewayException.Kind.OIL_FREE_LIFETIME_EXHAUSTED, GatewayException.Kind.PRO_REQUIRED ->
                        it.copy(importing = false, needsUpgrade = true, formError = "You've used your free PDF imports. Upgrade to keep importing, or enter the values by hand.")
                    GatewayException.Kind.OIL_DAILY_EXHAUSTED ->
                        it.copy(importing = false, formError = "You've used today's PDF imports. The limit resets at midnight UTC; you can enter the values by hand.")
                    else -> it.copy(importing = false, formError = e.message ?: "Couldn't read that report.")
                }
            }
        } catch (e: Exception) {
            _state.update { it.copy(importing = false, formError = e.message ?: "Couldn't read that report.") }
        }
    }

    // --- attachments ---

    val attachmentsAvailable: Boolean get() = storage != null

    fun addAttachment(uri: String, mimeType: String, displayName: String) {
        if (!AttachmentRules.isAllowedMime(mimeType)) {
            _state.update { it.copy(formError = "Only photos and PDFs can be attached.") }
            return
        }
        _state.update { s ->
            if (!AttachmentRules.canAddMore(s.attachmentPaths.size, s.pendingAttachments.size)) {
                s.copy(formError = "At most ${AttachmentRules.MAX_PER_ENTRY} attachments per entry.")
            } else {
                s.copy(pendingAttachments = s.pendingAttachments + PendingAttachment(uri, mimeType, displayName), formError = null)
            }
        }
    }

    fun removePendingAttachment(index: Int) =
        _state.update { s -> s.copy(pendingAttachments = s.pendingAttachments.filterIndexed { i, _ -> i != index }) }

    /** Queues the removal: Storage is only touched after the entry save succeeds, so backing out destroys nothing. */
    fun removeExistingAttachment(path: String) {
        removedPaths += path
        _state.update { s -> s.copy(attachmentPaths = s.attachmentPaths - path) }
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
        val loaded = existing?.takeIf { it.entryType == s.type }?.let { EntryDetailsMapper.toRaw(it.entryType, it.details, zone) }.orEmpty()
        val errors = EntryFormValidator.validate(s, unchangedLegacy = loaded)
        if (errors.isNotEmpty()) {
            _state.update { it.copy(errors = errors, formError = "Fix the highlighted fields.") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(saving = true, errors = emptyMap(), formError = null) }
            val old = existing
            // The entry id exists before any upload so attachments land in users/{uid}/entry-attachments/{vehicle}/{entryId}/.
            // A new entry reuses one reserved id across retries, so a failed attempt never strands a second folder.
            val entryId = old?.id ?: reservedNewEntryId ?: UUID.randomUUID().toString().also { reservedNewEntryId = it }
            val uploaded = mutableListOf<String>()
            var written = false
            runCatching {
                if (s.pendingAttachments.isNotEmpty()) {
                    val repo = storage ?: error("Attachments aren't available.")
                    check(canAttach()) { "Attachments are a Garage Pro feature." }
                    // A failure anywhere before the Firestore write removes what already landed (see onFailure).
                    for (p in s.pendingAttachments) uploaded += repo.uploadAttachment(target, p.uri, p.mimeType, entryId)
                }
                val built = buildEntry(s, target, old).copy(id = entryId, attachmentPaths = s.attachmentPaths + uploaded)
                val saved = if (old == null) entries.addEntry(built) else built.also { entries.updateEntry(it) }
                written = true
                vehicles.syncOdometer(
                    target, saved.odometerReading,
                    otherEntriesMax = known.filter { it.id != saved.id }.maxOfOrNull { it.odometerReading },
                    isEditing = old != null, previousReading = old?.odometerReading,
                )
                wear?.sync(saved, isEdit = old != null)
                saved
            }.onSuccess { saved ->
                removedPaths.forEach { path -> runCatching { storage?.deleteAttachment(path) } }
                removedPaths.clear()
                analytics.log(
                    AnalyticsEvents.ENTRY_SAVED,
                    AnalyticsEvents.params("entry_type" to saved.entryType.wire, "is_edit" to if (old != null) 1 else 0),
                )
                if (old == null) reviews.record(ReviewMoment.ENTRY_LOGGED)
                reservedNewEntryId = null
                onDone()
            }.onFailure { e ->
                // The Firestore write failed after the uploads landed: nothing points at them, so remove them (retry re-uploads).
                if (!written) uploaded.forEach { path -> runCatching { storage?.deleteAttachment(path) } }
                _state.update { it.copy(saving = false, formError = e.message ?: "Could not save the entry.") }
            }
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
