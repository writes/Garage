package com.writes.garage.core.domain

import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.RecallStatus
import com.writes.garage.core.model.Vehicle
import java.time.Instant

/** Recall persistence and safety rules (port of iOS `WarrantyViewModel.checkForRecalls` + `RecallLookupService`). */
object RecallRules {
    const val DO_NOT_DRIVE_MARKER = "DO NOT DRIVE"
    const val PARK_OUTSIDE_MARKER = "PARK OUTSIDE"

    /** NHTSA "park it": the vehicle should not be driven at all until repaired. */
    fun isDoNotDrive(r: Recall): Boolean = r.notes?.contains(DO_NOT_DRIVE_MARKER) == true

    /** NHTSA "park outside": fire risk. */
    fun isParkOutside(r: Recall): Boolean = r.notes?.contains(PARK_OUTSIDE_MARKER) == true

    fun isOutstanding(r: Recall): Boolean = r.status == RecallStatus.OUTSTANDING

    fun outstandingCount(recalls: List<Recall>): Int = recalls.count(::isOutstanding)

    /** Open recalls that carry a safety-urgent advisory; shown first and styled as errors. */
    fun urgent(recalls: List<Recall>): List<Recall> =
        recalls.filter { isOutstanding(it) && (isDoNotDrive(it) || isParkOutside(it)) }

    /** Urgent first, then outstanding, then the rest; newest announcement first within each group. */
    fun ordered(recalls: List<Recall>): List<Recall> =
        recalls.sortedWith(
            compareBy<Recall> { if (urgent(listOf(it)).isNotEmpty()) 0 else if (isOutstanding(it)) 1 else 2 }
                .thenByDescending { it.dateAnnounced ?: Instant.EPOCH },
        )

    /**
     * Looked-up recalls that are not stored yet. Known campaign numbers are skipped so a recall the owner already
     * marked completed is never reset to outstanding. New rows get a blank id (the repository assigns one).
     */
    fun newRecalls(known: List<Recall>, fetched: List<Recall>, now: Instant): List<Recall> {
        val seen = known.map { key(it) }.toMutableSet()
        return fetched.filter { r -> seen.add(key(r)) }.map { it.copy(id = "", createdAt = now) }
    }

    /** Campaign number when there is one; otherwise title + component + announce date, so a number-less recall dedupes too. */
    private fun key(r: Recall): String =
        r.campaignNumber?.trim()?.takeIf { it.isNotEmpty() }?.uppercase()?.let { "c:$it" }
            ?: "t:${r.title.trim().lowercase()}|${r.componentAffected?.trim()?.lowercase().orEmpty()}|${r.dateAnnounced?.toEpochMilli() ?: 0L}"

    fun summary(v: Vehicle, count: Int): String =
        "Checked ${v.year} ${v.make} ${v.model} - $count recall${if (count == 1) "" else "s"} on file."

    fun markCompleted(r: Recall, shop: String?, odometer: Int?, date: Instant): Recall = r.copy(
        status = RecallStatus.COMPLETED,
        completedDate = date,
        completedShop = shop?.trim()?.takeIf { it.isNotEmpty() },
        completedOdometer = odometer,
    )
}
