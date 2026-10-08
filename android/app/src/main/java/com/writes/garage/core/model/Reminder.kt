package com.writes.garage.core.model

import java.time.Instant

/** Firestore `vehicles/{vehicleId}/reminders/{id}`. [completedAt] == null means still outstanding. */
data class Reminder(
    val id: String,
    val vehicleId: String,
    val title: String,
    val entryType: EntryType? = null,
    val dueDate: Instant? = null,
    val dueMileage: Int? = null,
    val repeatIntervalMonths: Int? = null,
    val repeatIntervalMiles: Int? = null,
    val notes: String? = null,
    val isProFeature: Boolean = false,
    val createdAt: Instant? = null,
    val completedAt: Instant? = null,
) {
    val isOutstanding: Boolean get() = completedAt == null
}
