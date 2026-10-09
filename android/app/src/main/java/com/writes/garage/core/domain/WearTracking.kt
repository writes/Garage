package com.writes.garage.core.domain

import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.WearItemType
import com.writes.garage.core.model.WearSnapshot
import java.time.Instant

/** Port of iOS `WearSnapshotFactory`: turns a brake or tire entry into the wear snapshots the Dashboard reads. */
object WearSnapshotFactory {
    /** Tread depth is in 32nds of an inch. New ~10/32; 2/32 is the legal minimum, so percent is measured over that range. */
    const val NEW_TREAD_32NDS = 10.0
    const val MIN_LEGAL_TREAD_32NDS = 2.0
    const val MAX_PLAUSIBLE_TREAD_32NDS = 100.0

    data class WearWrite(val snapshots: List<WearSnapshot> = emptyList(), val clearedIds: List<String> = emptyList())

    /** "6", "6/32" or "6.5" -> 32nds. The denominator is ignored on purpose (matches iOS). Null if not finite/plausible. */
    fun parseTread32nds(reading: String): Double? {
        val head = reading.split('/').firstOrNull()?.trim().orEmpty()
        val v = head.toDoubleOrNull() ?: return null
        return v.takeIf { it.isFinite() && it >= 0 && it <= MAX_PLAUSIBLE_TREAD_32NDS }
    }

    fun treadPercentage(reading: String): Double? {
        val depth = parseTread32nds(reading) ?: return null
        val usable = NEW_TREAD_32NDS - MIN_LEGAL_TREAD_32NDS
        return ((depth - MIN_LEGAL_TREAD_32NDS) / usable * 100).coerceIn(0.0, 100.0)
    }

    /** Deterministic so re-saving an edited entry overwrites its snapshot rather than appending another. */
    fun snapshotId(entryId: String, item: WearItemType) = "$entryId-${item.wire}"

    fun allIdsFor(entryId: String): List<String> = WearItemType.entries.map { snapshotId(entryId, it) }

    /** Wear writes for [entry] (must already have its final id); non-brake/tire entries produce nothing to store. */
    fun write(entry: Entry, recordedAt: Instant): WearWrite = when (entry.entryType) {
        EntryType.BRAKE -> brake(entry, recordedAt)
        EntryType.TIRE -> tire(entry, recordedAt)
        else -> WearWrite()
    }

    private fun brake(e: Entry, at: Instant): WearWrite {
        val readings = listOf(
            WearItemType.FRONT_BRAKE_PADS to e.details["frontPadPct"].asDouble(),
            WearItemType.REAR_BRAKE_PADS to e.details["rearPadPct"].asDouble(),
            WearItemType.FRONT_ROTORS to e.details["frontRotorPct"].asDouble(),
            WearItemType.REAR_ROTORS to e.details["rearRotorPct"].asDouble(),
        )
        val snaps = mutableListOf<WearSnapshot>()
        val cleared = mutableListOf<String>()
        for ((item, pct) in readings) {
            if (pct == null || !pct.isFinite()) {
                cleared += snapshotId(e.id, item)
                continue
            }
            val clamped = pct.coerceIn(0.0, 100.0)
            snaps += WearSnapshot(
                id = snapshotId(e.id, item), vehicleId = e.vehicleId, entryId = e.id, wearItem = item, valuePct = clamped,
                valueRaw = "${Math.round(clamped)}%", odometerReading = e.odometerReading, recordedAt = at, createdAt = at,
            )
        }
        return WearWrite(snaps, cleared)
    }

    private fun tire(e: Entry, at: Instant): WearWrite {
        val axles = listOf(
            WearItemType.FRONT_TIRES to listOf("treadDepthFL", "treadDepthFR"),
            WearItemType.REAR_TIRES to listOf("treadDepthRL", "treadDepthRR"),
        )
        val snaps = mutableListOf<WearSnapshot>()
        val cleared = mutableListOf<String>()
        for ((item, keys) in axles) {
            // The worse corner wins: an axle is only as good as its most worn tire.
            val parsed = keys.mapNotNull { (e.details[it] as? String)?.takeIf { s -> s.isNotBlank() } }.mapNotNull { r ->
                val depth = parseTread32nds(r) ?: return@mapNotNull null
                val pct = treadPercentage(r) ?: return@mapNotNull null
                pct to "${formatDepth(depth)}/32"
            }
            val worst = parsed.minByOrNull { it.first }
            if (worst == null) {
                cleared += snapshotId(e.id, item)
                continue
            }
            snaps += WearSnapshot(
                id = snapshotId(e.id, item), vehicleId = e.vehicleId, entryId = e.id, wearItem = item, valuePct = worst.first,
                valueRaw = worst.second, odometerReading = e.odometerReading, recordedAt = at, createdAt = at,
            )
        }
        return WearWrite(snaps, cleared)
    }

    private fun formatDepth(d: Double): String = if (d == Math.rint(d)) d.toInt().toString() else "%.1f".format(d)
}

/** Port of iOS `WearProjection`: miles until an item reaches 0% at the rate its own history implies; null when unsupported. */
object WearProjection {
    const val MINIMUM_SPAN_MILES = 200
    const val FRESH_PART_THRESHOLD_PCT = 95.0
    const val CREDIBLE_CEILING_MILES = 100_000

    private val newestFirst = Comparator<WearSnapshot> { a, b ->
        when {
            a.recordedAt != b.recordedAt -> b.recordedAt.compareTo(a.recordedAt)
            a.odometerReading != b.odometerReading -> b.odometerReading.compareTo(a.odometerReading)
            else -> b.id.compareTo(a.id)
        }
    }

    fun milesToReplacement(item: WearItemType, snapshots: List<WearSnapshot>): Int? {
        val readings = snapshots.filter { it.wearItem == item && it.valuePct != null }.sortedWith(newestFirst)
        if (readings.size < 2) return null
        val current = readings[0].valuePct ?: return null
        val previous = readings[1].valuePct ?: return null
        if (current >= FRESH_PART_THRESHOLD_PCT) return null
        if (current > previous) return null // replaced between readings
        val span = readings[0].odometerReading - readings[1].odometerReading
        if (span < MINIMUM_SPAN_MILES) return null
        val rate = (previous - current) / span
        if (rate <= 0) return null
        val remaining = current / rate
        if (!remaining.isFinite() || remaining < 1) return null
        val miles = Math.round(remaining).toInt()
        if (miles > CREDIBLE_CEILING_MILES) return null
        return twoSignificantFigures(miles)
    }

    fun twoSignificantFigures(value: Int): Int {
        if (value < 100) return value
        var magnitude = 1
        var rest = value / 100
        while (rest > 0) {
            magnitude *= 10
            rest /= 10
        }
        return ((value + magnitude / 2) / magnitude) * magnitude
    }

    data class WearItem(val type: WearItemType, val percentage: Double, val rawValue: String?, val milesToReplacement: Int?)

    /** One row per item (newest snapshot) in [WearItemType] order, with the projected miles when supportable. */
    fun latestItems(snapshots: List<WearSnapshot>): List<WearItem> {
        val latest = snapshots.sortedWith(newestFirst).groupBy { it.wearItem }.mapValues { it.value.first() }
        return WearItemType.entries.mapNotNull { type ->
            val snap = latest[type] ?: return@mapNotNull null
            val pct = snap.valuePct ?: return@mapNotNull null
            WearItem(type, pct, snap.valueRaw, milesToReplacement(type, snapshots))
        }
    }
}

/** Port of iOS `TireAgeAdvisor`: years since the latest new tire install, only once past the 5-year threshold. */
object TireAgeAdvisor {
    const val AGING_THRESHOLD_YEARS = 5.0
    private const val SECONDS_PER_YEAR = 365.25 * 24 * 60 * 60

    fun yearsSinceNewInstall(entries: List<Entry>, now: Instant): Double? {
        val latest = entries.filter { it.entryType == EntryType.TIRE && it.details["actionType"] == "new_install" }
            .maxOfOrNull { it.entryDate } ?: return null
        val years = (now.epochSecond - latest.epochSecond) / SECONDS_PER_YEAR
        return years.takeIf { it >= AGING_THRESHOLD_YEARS }
    }
}
