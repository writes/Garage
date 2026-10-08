package com.writes.garage.core.model

import java.time.Instant

/** Firestore `users/{uid}` client-owned fields. `subscription` and `vehicleCount` are server-written. */
data class UserProfile(
    val id: String,
    val email: String? = null,
    val name: String? = null,
    val address: String? = null,
    val phone: String? = null,
    val insuranceCompany: String? = null,
    val policyNumber: String? = null,
    val analyticsOptOut: Boolean = true,
    val themeId: String? = null,
    /** When the user allowed voice/receipt content to be sent to the Claude API. null = never / revoked. */
    val aiConsentGrantedAt: Instant? = null,
    val createdAt: Instant? = null,
    val updatedAt: Instant? = null,
    /** Server-written `subscription` map says Pro (e.g. bought on another platform). Read-only. */
    val serverIsPro: Boolean = false,
) {
    val hasAiConsent: Boolean get() = aiConsentGrantedAt != null
}

/** Signed-in identity. [isDemo] is true for the fake "Continue in demo" session. */
data class AuthUser(
    val uid: String,
    val email: String? = null,
    val displayName: String? = null,
    val isDemo: Boolean = false,
)
