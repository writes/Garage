package com.writes.garage.core.domain

import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType

/** Fuel economy math (port of iOS `FuelEntry.calculatedMPG` + `FuelEconomyAdvisor`). */
object FuelEconomy {
    /** Full-to-full MPG; null for a non-positive distance or gallons (out-of-order entry, corrected odometer). */
    fun calculatedMpg(currentOdometer: Int, previousOdometer: Int, gallons: Double): Double? {
        val distance = currentOdometer - previousOdometer
        if (distance <= 0 || gallons <= 0.0) return null
        return distance / gallons
    }

    /**
     * MPG for each fuel fill-up, measured against the previous fill-up by odometer (full-tank assumption,
     * exactly like iOS). Key = entry id. Fill-ups without gallons or a usable odometer pair are absent.
     */
    fun mpgBetweenFills(entries: List<Entry>): Map<String, Double> {
        val fills = entries.filter { it.entryType == EntryType.FUEL && it.odometerReading > 0 }
            .sortedWith(compareBy<Entry> { it.odometerReading }.thenBy { it.entryDate }.thenBy { it.id })
        val out = LinkedHashMap<String, Double>()
        for (i in 1 until fills.size) {
            val gallons = fills[i].details["gallons"].asDouble() ?: continue
            val mpg = calculatedMpg(fills[i].odometerReading, fills[i - 1].odometerReading, gallons) ?: continue
            out[fills[i].id] = mpg
        }
        return out
    }

    /** One fill-up's MPG ([gallons] is null when the entry has none, so it can chart but not weight an average). */
    data class FillMpg(val entryId: String, val date: java.time.Instant, val mpg: Double, val gallons: Double?)

    /**
     * Every fuel entry that has an MPG: its stored `calculatedMPG`, else the figure derived from the odometer pair.
     * Entries made by receipt/voice carry no stored value, so Stats must not ignore them. The chart series and
     * [weightedAverageMpg] both read this one list so they can never disagree.
     */
    fun fillMpgs(entries: List<Entry>): List<FillMpg> {
        val derived = mpgBetweenFills(entries)
        return entries.mapNotNull { e ->
            if (e.entryType != EntryType.FUEL) return@mapNotNull null
            val mpg = e.details["calculatedMPG"].asDouble()?.takeIf { it > 0 } ?: derived[e.id] ?: return@mapNotNull null
            FillMpg(e.id, e.entryDate, mpg, e.details["gallons"].asDouble()?.takeIf { it > 0 })
        }
    }

    /**
     * Σmiles ÷ Σgallons across the fills that have both figures (never the mean of per-tank MPG, which lets a tiny
     * tank skew the result). Null when no fill has gallons to weight by.
     */
    fun weightedAverageMpg(entries: List<Entry>): Double? =
        averageMpg(fillMpgs(entries).mapNotNull { f -> f.gallons?.let { Tank(f.entryId, f.date, f.mpg, it) } })

    // --- FuelEconomyAdvisor ---

    const val RECENT_WINDOW = 3
    const val BASELINE_WINDOW = 10
    const val DROP_THRESHOLD_PCT = 15.0

    data class Verdict(val currentAvgMpg: Double, val baselineAvgMpg: Double, val dropPct: Double)

    private data class Tank(val id: String, val date: java.time.Instant, val mpg: Double, val gallons: Double) {
        val miles: Double get() = mpg * gallons
    }

    private fun tanks(entries: List<Entry>): List<Tank> = entries.mapNotNull { e ->
        if (e.entryType != EntryType.FUEL) return@mapNotNull null
        val mpg = e.details["calculatedMPG"].asDouble()?.takeIf { it > 0 } ?: return@mapNotNull null
        val gallons = e.details["gallons"].asDouble()?.takeIf { it > 0 } ?: return@mapNotNull null
        Tank(e.id, e.entryDate, mpg, gallons)
    }

    private fun averageMpg(tanks: List<Tank>): Double? {
        val gallons = tanks.sumOf { it.gallons }
        if (gallons <= 0.0) return null
        return tanks.sumOf { it.miles } / gallons
    }

    /**
     * Non-null only with a full baseline window AND a recent window more than [DROP_THRESHOLD_PCT] below it.
     * Null is the answer in every ambiguous case.
     */
    fun degradation(entries: List<Entry>): Verdict? {
        val sorted = tanks(entries).sortedWith(compareByDescending<Tank> { it.date }.thenByDescending { it.id })
        if (sorted.size < BASELINE_WINDOW) return null
        val current = averageMpg(sorted.take(RECENT_WINDOW)) ?: return null
        val baseline = averageMpg(sorted.take(BASELINE_WINDOW)) ?: return null
        if (baseline <= 0.0) return null
        val drop = (baseline - current) / baseline * 100
        if (drop <= DROP_THRESHOLD_PCT) return null
        return Verdict(current, baseline, drop)
    }
}
