package com.writes.garage.core.model

import java.time.Instant

enum class RecallStatus(val wire: String) {
    OUTSTANDING("outstanding"),
    COMPLETED("completed"),
    NOT_APPLICABLE("not_applicable"),
}

enum class RecallSource(val wire: String) {
    MANUAL("manual"),
    NHTSA_API("nhtsa_api"),
}

data class Recall(
    val id: String,
    val vehicleId: String,
    val campaignNumber: String? = null,
    val title: String,
    val description: String? = null,
    val componentAffected: String? = null,
    val dateAnnounced: Instant? = null,
    val status: RecallStatus = RecallStatus.OUTSTANDING,
    val completedDate: Instant? = null,
    val completedShop: String? = null,
    val completedOdometer: Int? = null,
    val recallSource: RecallSource = RecallSource.MANUAL,
    val notes: String? = null,
)
