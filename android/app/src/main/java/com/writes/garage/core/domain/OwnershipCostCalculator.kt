package com.writes.garage.core.domain

import com.writes.garage.core.model.Entry
import java.time.Duration
import java.time.Instant

/**
 * Ownership economics derived from stored entries (port of iOS `OwnershipCostCalculator`).
 * A single entry cannot establish a distance or duration, so ratios are null rather than zero.
 */
object OwnershipCostCalculator {
    data class Summary(
        val totalCost: Double,
        val milesCovered: Int,
        val costPerMile: Double?,
        val costPerMonth: Double?,
        val monthsCovered: Double,
    )

    private const val SECONDS_PER_MONTH = 30.44 * 24 * 60 * 60

    /** Null when no entry carries a positive cost. */
    fun summary(entries: List<Entry>, now: Instant): Summary? {
        val costed = entries.filter { (it.cost ?: 0.0) > 0.0 }
        if (costed.isEmpty()) return null
        val total = costed.sumOf { it.cost ?: 0.0 }

        // Distance uses EVERY entry's odometer: a free warranty repair still proves the miles.
        val odometers = entries.map { it.odometerReading }.filter { it > 0 }
        val miles = (odometers.maxOrNull() ?: 0) - (odometers.minOrNull() ?: 0)

        val dates = entries.map { it.entryDate }
        val spanSeconds = Duration.between(dates.minOrNull() ?: now, dates.maxOrNull() ?: now).seconds.toDouble()
        val months = spanSeconds / SECONDS_PER_MONTH

        return Summary(
            totalCost = total,
            milesCovered = miles,
            costPerMile = if (miles > 0) total / miles else null,
            // Below roughly a month there is no meaningful monthly rate.
            costPerMonth = if (months >= 1.0) total / months else null,
            monthsCovered = months,
        )
    }

    /** Total cost grouped by entry type, largest first (zero-cost types omitted). */
    fun costByType(entries: List<Entry>): List<Pair<com.writes.garage.core.model.EntryType, Double>> =
        entries.filter { (it.cost ?: 0.0) > 0.0 }
            .groupBy { it.entryType }
            .map { (type, list) -> type to list.sumOf { it.cost ?: 0.0 } }
            // Ties keep a fixed order (by entry type) so the cost breakdown cannot reshuffle between renders.
            .sortedWith(compareByDescending<Pair<com.writes.garage.core.model.EntryType, Double>> { it.second }.thenBy { it.first.ordinal })
}
