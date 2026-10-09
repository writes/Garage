package com.writes.garage.feature.handover

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.AnalyticsEvents
import com.writes.garage.core.data.AnalyticsSink
import com.writes.garage.core.data.DetailingRepository
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.GalleryRepository
import com.writes.garage.core.data.NoopAnalyticsSink
import com.writes.garage.core.data.PartsRepository
import com.writes.garage.core.data.RecallRepository
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.data.VehicleRecordRepository
import com.writes.garage.core.data.WarrantyRepository
import com.writes.garage.core.data.WearRepository
import com.writes.garage.core.export.DossierRequest
import com.writes.garage.core.model.DetailingRecord
import com.writes.garage.core.review.NoopReviewMoments
import com.writes.garage.core.review.ReviewMoment
import com.writes.garage.core.review.ReviewMoments
import com.writes.garage.core.model.Entitlement
import com.writes.garage.core.model.GalleryPhoto
import com.writes.garage.core.model.ReportSection
import kotlinx.coroutines.flow.first
import java.time.LocalDate
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.ReminderRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.observeActiveVehicle
import com.writes.garage.core.domain.Validators
import com.writes.garage.core.export.CsvExporter
import com.writes.garage.core.export.DossierContent
import com.writes.garage.core.export.DossierLine
import com.writes.garage.core.export.IcsBuilder
import com.writes.garage.core.export.PdfExporter
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.Reminder
import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.OutputStream
import java.time.Instant
import java.time.ZoneId

/** The per-vehicle record collections that feed the dossier sections. Any may be null (section then has no data). */
class HandoverRecords(
    val recalls: RecallRepository? = null,
    val warranties: WarrantyRepository? = null,
    val parts: PartsRepository? = null,
    val detailing: DetailingRepository? = null,
    val gallery: GalleryRepository? = null,
    val wear: WearRepository? = null,
)

data class HandoverUiState(
    val vehicle: Vehicle? = null,
    /** The record PDF is a Pro entitlement (CSV and ICS stay free). */
    val isPro: Boolean = false,
    val sections: Set<ReportSection> = ReportSection.entries.toSet(),
    val startDate: LocalDate? = null,
    val endDate: LocalDate? = null,
    val entryCount: Int = 0,
    /** Outstanding reminders with a due date (the only ones an .ics event can represent). */
    val datedReminderCount: Int = 0,
    val includeRecalls: Boolean = true,
    val busy: Boolean = false,
    /** Set when a file is ready; the screen launches the share sheet and calls [HandoverViewModel.shareHandled]. */
    val pendingShare: ExportedFile? = null,
    val message: String? = null,
    val error: String? = null,
)

/** Exports the active vehicle's resale dossier (PDF), entries (CSV) and reminders (ICS) and hands them to the share sheet. */
@OptIn(ExperimentalCoroutinesApi::class)
class HandoverViewModel(
    private val vehicles: VehicleRepository,
    private val entries: EntryRepository,
    private val reminders: ReminderRepository,
    private val functions: FunctionsGateway,
    private val store: ExportFileStore,
    private val entitlement: StateFlow<Entitlement>,
    private val renderPdf: (List<DossierLine>, OutputStream) -> Int = PdfExporter::write,
    private val clock: () -> Instant = Instant::now,
    private val zone: ZoneId = ZoneId.systemDefault(),
    private val io: CoroutineDispatcher = Dispatchers.IO,
    private val records: HandoverRecords = HandoverRecords(),
    private val storage: StorageRepository? = null,
    private val analytics: AnalyticsSink = NoopAnalyticsSink,
    private val reviews: ReviewMoments = NoopReviewMoments,
) : ViewModel() {
    private val _state = MutableStateFlow(HandoverUiState())
    val state: StateFlow<HandoverUiState> = _state.asStateFlow()

    private var entryList: List<Entry> = emptyList()
    private var reminderList: List<Reminder> = emptyList()

    init {
        viewModelScope.launch { entitlement.collect { e -> _state.update { it.copy(isPro = e.isPro) } } }
        viewModelScope.launch {
            vehicles.observeActiveVehicle().flatMapLatest { v ->
                if (v == null) {
                    flowOf(Triple(null, emptyList<Entry>(), emptyList<Reminder>()))
                } else {
                    combine(entries.observeEntries(v.id), reminders.observeReminders(v.id)) { e, r -> Triple(v, e, r) }
                }
            }.collect { (v, e, r) ->
                entryList = e
                reminderList = r
                _state.update {
                    it.copy(
                        vehicle = v, entryCount = e.size,
                        datedReminderCount = r.count { x -> x.isOutstanding && x.dueDate != null },
                    )
                }
            }
        }
    }

    fun setIncludeRecalls(include: Boolean) = setSection(ReportSection.RECALLS, include)

    fun setSection(section: ReportSection, included: Boolean) =
        _state.update { it.copy(sections = if (included) it.sections + section else it.sections - section) }

    fun setStartDate(date: LocalDate?) = _state.update { it.copy(startDate = date) }

    fun setEndDate(date: LocalDate?) = _state.update { it.copy(endDate = date) }

    fun exportPdf() {
        if (!_state.value.isPro) {
            _state.update { it.copy(error = "The record PDF is a Garage Pro feature. CSV and calendar exports stay free.") }
            return
        }
        val s0 = _state.value
        if (s0.startDate != null && s0.endDate != null && s0.endDate.isBefore(s0.startDate)) {
            _state.update { it.copy(error = "The end date is before the start date.") }
            return
        }
        run("Building dossier...") { v ->
            val s = _state.value
            val now = clock()
            val recalls = if (ReportSection.RECALLS in s.sections) recallsFor(v) else emptyList()
            val gallery = if (ReportSection.PHOTO_GALLERY in s.sections) records.gallery.snapshot(v.id) else emptyList()
            val request = DossierRequest(
                vehicle = v,
                entries = entryList.sortedByDescending { it.entryDate },
                sections = s.sections,
                startDate = s.startDate,
                endDate = s.endDate,
                recalls = recalls,
                warranties = if (ReportSection.WARRANTIES in s.sections) records.warranties.snapshot(v.id) else emptyList(),
                parts = if (ReportSection.SPARE_PARTS in s.sections) records.parts.snapshot(v.id) else emptyList(),
                detailing = if (ReportSection.DETAILING in s.sections) records.detailing.snapshot(v.id) else emptyList(),
                gallery = gallery,
                wear = if (ReportSection.WEAR_SUMMARY in s.sections) records.wear.snapshot(v.id) else emptyList(),
                photoBytes = fetchPhotos(gallery),
            )
            val lines = DossierContent.buildReport(request, now, zone)
            val file = withContext(io) { store.write(fileName(v, "dossier", "pdf", now), "application/pdf") { renderPdf(lines, it) } }
            analytics.log(AnalyticsEvents.EXPORT_PDF, AnalyticsEvents.params())
            reviews.record(ReviewMoment.PDF_EXPORTED)
            file
        }
    }

    fun exportCsv() = run("Building CSV...") { v ->
        val csv = CsvExporter.export(entryList)
        withContext(io) {
            store.write(fileName(v, "entries", "csv", clock()), "text/csv") { it.write(csv.toByteArray(Charsets.UTF_8)) }
        }.also { analytics.log(AnalyticsEvents.EXPORT_CSV, AnalyticsEvents.params()) }
    }

    fun exportIcs() = run("Building calendar file...") { v ->
        val now = clock()
        val ics = IcsBuilder.makeCalendar(reminderList.filter { it.isOutstanding }, now)
            ?: error("No upcoming reminders with a due date to export.")
        withContext(io) {
            store.write(fileName(v, "reminders", "ics", now), "text/calendar") { it.write(ics.toByteArray(Charsets.UTF_8)) }
        }
    }

    fun shareHandled() = _state.update { it.copy(pendingShare = null) }

    private fun run(label: String, block: suspend (Vehicle) -> ExportedFile) {
        val v = _state.value.vehicle
        if (v == null) {
            _state.update { it.copy(error = "Add a vehicle first.") }
            return
        }
        if (_state.value.busy) return
        viewModelScope.launch {
            _state.update { it.copy(busy = true, message = label, error = null) }
            runCatching { block(v) }
                .onSuccess { f -> _state.update { it.copy(busy = false, message = "Ready: ${f.fileName}", pendingShare = f) } }
                .onFailure { e -> _state.update { it.copy(busy = false, message = null, error = e.message ?: "Export failed.") } }
        }
    }

    /** Stored recalls; with none stored, a best-effort live NHTSA lookup so the dossier is still useful offline-first. */
    private suspend fun recallsFor(v: Vehicle): List<Recall> {
        val stored = records.recalls.snapshot(v.id)
        if (stored.isNotEmpty() || records.recalls != null) return stored
        return fetchRecalls(v)
    }

    private suspend fun fetchRecalls(v: Vehicle): List<Recall> {
        val vin = Validators.normalizeVin(v.vin) ?: return emptyList()
        return runCatching { functions.lookupRecalls(v.id, vin) }.getOrDefault(emptyList())
    }

    private suspend fun <T> VehicleRecordRepository<T>?.snapshot(vehicleId: String): List<T> =
        this?.let { runCatching { it.observe(vehicleId).first() }.getOrDefault(emptyList()) }.orEmpty()

    /** Up to [MAX_PHOTOS] included gallery photos, best effort (a missing file just drops to a captioned line). */
    private suspend fun fetchPhotos(gallery: List<GalleryPhoto>): Map<String, ByteArray> {
        val repo = storage ?: return emptyMap()
        val out = LinkedHashMap<String, ByteArray>()
        for (p in gallery.filter { it.includeInExport }.sortedWith(compareBy({ it.section.ordinal }, { it.displayOrder })).take(MAX_PHOTOS)) {
            runCatching { repo.downloadAttachment(p.storagePath, PHOTO_MAX_BYTES) }.onSuccess { out[p.storagePath] = it }
        }
        return out
    }

    companion object {
        const val MAX_PHOTOS = 12
        const val PHOTO_MAX_BYTES = 6 * 1024 * 1024

        fun fileName(v: Vehicle, kind: String, ext: String, now: Instant): String {
            val slug = v.displayName.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-').ifEmpty { "vehicle" }
            return "garage-$slug-$kind-${now.toString().take(10)}.$ext"
        }
    }
}
