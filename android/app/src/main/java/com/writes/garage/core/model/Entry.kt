package com.writes.garage.core.model

import com.writes.garage.core.domain.EntrySearch
import java.time.Instant

/**
 * A log entry (Firestore `vehicles/{vehicleId}/entries/{id}`). Type-specific fields live in
 * [details] (string-keyed, values are String/Number/Boolean/List/Map) exactly like iOS.
 */
data class Entry(
    val id: String,
    val vehicleId: String,
    val userId: String,
    val entryType: EntryType,
    val entryDate: Instant,
    val odometerReading: Int,
    val cost: Double? = null,
    val isDiy: Boolean? = null,
    val shopName: String? = null,
    val notes: String? = null,
    val attachmentPaths: List<String> = emptyList(),
    val isResolved: Boolean? = null,
    val details: Map<String, Any?> = emptyMap(),
    val createdAt: Instant? = null,
    val updatedAt: Instant? = null,
)

/** Filter used by the Log screen (port of iOS `EntryQuery`). */
data class EntryQuery(
    val vehicleId: String,
    val entryTypes: Set<EntryType> = emptySet(),
    val searchText: String = "",
    val startDate: Instant? = null,
    val endDate: Instant? = null,
) {
    fun matches(entry: Entry): Boolean {
        if (entry.vehicleId != vehicleId) return false
        if (entryTypes.isNotEmpty() && entry.entryType !in entryTypes) return false
        if (startDate != null && entry.entryDate < startDate) return false
        if (endDate != null && entry.entryDate > endDate) return false
        val q = searchText.trim()
        if (q.isNotEmpty()) {
            val hay = listOfNotNull(entry.shopName, entry.notes, entry.entryType.displayName) +
                EntrySearch.detailHaystack(entry.details)
            if (hay.none { it.contains(q, ignoreCase = true) }) return false
        }
        return true
    }
}
