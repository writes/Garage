package com.writes.garage.core.data

import com.writes.garage.core.model.UserProfile
import kotlinx.coroutines.flow.Flow

interface ProfileRepository {
    fun observeProfile(): Flow<UserProfile?>

    suspend fun updateProfile(profile: UserProfile)

    /** Partial write of `analyticsOptOut` only (true = no analytics/crash collection); never touches the form fields. */
    suspend fun setAnalyticsOptOut(optOut: Boolean)

    /** Partial write of `themeID` only (null/blank clears it). */
    suspend fun setThemeId(themeId: String?)

    /** Grants (true) or revokes (false) permission to send voice/receipt content to the AI backend. */
    suspend fun setAiConsent(granted: Boolean)
}
