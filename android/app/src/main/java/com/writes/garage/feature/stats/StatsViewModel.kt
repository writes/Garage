package com.writes.garage.feature.stats

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.WearRepository
import com.writes.garage.core.model.WearItemType
import com.writes.garage.core.model.WearSnapshot
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import com.writes.garage.core.data.observeActiveVehicle
import com.writes.garage.core.domain.FuelEconomy
import com.writes.garage.core.domain.OwnershipCostCalculator
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import java.time.Instant

data class MpgPoint(val date: Instant, val mpg: Double)

data class TrackDaySummary(
    val events: Int,
    val totalCost: Double,
    val totalLaps: Int,
    val heatCycles: Int,
    val venues: List<String>,
    val bestLapSeconds: Double?,
    val bestLapLabel: String?,
    val bestLapVenue: String?,
)

/** One wear item's readings, oldest first (percent remaining). */
data class WearSeries(val item: WearItemType, val points: List<Double>)

/** Items with at least two readings, in [WearItemType] order. */
fun wearSeries(snapshots: List<WearSnapshot>): List<WearSeries> =
    WearItemType.entries.mapNotNull { type ->
        val pts = snapshots.filter { it.wearItem == type && it.valuePct != null }
            .sortedWith(compareBy({ it.recordedAt }, { it.odometerReading })).map { it.valuePct!! }
        if (pts.size >= 2) WearSeries(type, pts) else null
    }

data class StatsUiState(
    val vehicleName: String? = null,
    /** Sum of entry costs (operating cost); excludes the purchase price. */
    val totalCost: Double = 0.0,
    val purchasePrice: Double? = null,
    val costByType: List<Pair<EntryType, Double>> = emptyList(),
    val averageMpg: Double? = null,
    val entryCount: Int = 0,
    val summary: OwnershipCostCalculator.Summary? = null,
    /** Oldest first. */
    val mpgSeries: List<MpgPoint> = emptyList(),
    val trackDay: TrackDaySummary? = null,
    /** Percent remaining over time per wear item (oldest first), for the wear-history chart. */
    val wearHistory: List<WearSeries> = emptyList(),
) {
    /** Purchase price (when known) plus everything spent since. */
    val totalCostOfOwnership: Double get() = totalCost + (purchasePrice ?: 0.0)
}

/** `1:34.821` or `94.821` -> seconds; null when unparseable. */
fun parseLapTime(text: String?): Double? {
    val t = text?.trim().orEmpty()
    if (t.isEmpty()) return null
    val parts = t.split(':')
    return when (parts.size) {
        1 -> parts[0].toDoubleOrNull()
        2 -> {
            val m = parts[0].toIntOrNull() ?: return null
            val s = parts[1].toDoubleOrNull() ?: return null
            m * 60 + s
        }
        else -> null
    }?.takeIf { it > 0 }
}

private fun Any?.asNumber(): Double? = when (this) {
    is Number -> toDouble()
    is String -> toDoubleOrNull()
    else -> null
}

/** Pure aggregation, unit-testable without Android. */
fun computeStats(
    vehicleName: String?,
    entries: List<Entry>,
    purchasePrice: Double? = null,
    now: Instant = Instant.now(),
): StatsUiState {
    val series = FuelEconomy.fillMpgs(entries).map { MpgPoint(it.date, it.mpg) }.sortedBy { it.date }
    // Σmiles ÷ Σgallons over the SAME fills as the series; never the mean of per-tank MPG.
    val average = FuelEconomy.weightedAverageMpg(entries)

    return StatsUiState(
        vehicleName = vehicleName,
        totalCost = entries.sumOf { it.cost ?: 0.0 },
        purchasePrice = purchasePrice,
        costByType = OwnershipCostCalculator.costByType(entries),
        averageMpg = average,
        entryCount = entries.size,
        summary = OwnershipCostCalculator.summary(entries, now),
        mpgSeries = series,
        trackDay = trackDaySummary(entries),
    )
}

fun trackDaySummary(entries: List<Entry>): TrackDaySummary? {
    val days = entries.filter { it.entryType == EntryType.TRACK_DAY }
    if (days.isEmpty()) return null
    // Fastest lap; an exact tie goes to the most recent day (then id) so the card cannot change with list order.
    val best = days.mapNotNull { e ->
        val raw = e.details["bestLapTime"]?.toString()
        parseLapTime(raw)?.let { secs -> Triple(secs, raw!!.trim(), e.details["venueName"]?.toString() ?: e.shopName) to e }
    }.sortedWith(compareBy<Pair<Triple<Double, String, String?>, Entry>> { it.first.first }
        .thenByDescending { it.second.entryDate }.thenBy { it.second.id }).firstOrNull()?.first
    return TrackDaySummary(
        events = days.size,
        totalCost = days.sumOf { it.cost ?: 0.0 },
        totalLaps = days.sumOf { it.details["numberOfLaps"].asNumber()?.toInt() ?: 0 },
        heatCycles = days.sumOf { it.details["heatCyclesAdded"].asNumber()?.toInt() ?: 0 },
        // One circuit however it was typed ("Willow", " willow "): case-insensitive after trimming, first spelling kept.
        venues = days.mapNotNull { (it.details["venueName"] ?: it.shopName)?.toString()?.trim()?.takeIf(String::isNotEmpty) }
            .distinctBy { it.lowercase() },
        bestLapSeconds = best?.first,
        bestLapLabel = best?.second,
        bestLapVenue = best?.third,
    )
}

@OptIn(ExperimentalCoroutinesApi::class)
class StatsViewModel(
    vehicles: VehicleRepository,
    entries: EntryRepository,
    wear: WearRepository? = null,
    private val clock: () -> Instant = { Instant.now() },
) : ViewModel() {
    val state: StateFlow<StatsUiState> = vehicles.observeActiveVehicle()
        .flatMapLatest { v: Vehicle? ->
            if (v == null) flowOf(StatsUiState())
            else combine(
                entries.observeEntries(v.id),
                wear?.observe(v.id)?.catch { emit(emptyList()) } ?: flowOf(emptyList()),
            ) { e, w -> computeStats(v.displayName, e, v.purchasePrice, clock()).copy(wearHistory = wearSeries(w)) }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), StatsUiState())
}
