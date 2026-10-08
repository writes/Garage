package com.writes.garage.core.data

import com.writes.garage.core.model.UserProfile
import kotlinx.coroutines.flow.Flow

interface ProfileRepository {
    fun observeProfile(): Flow<UserProfile?>

    suspend fun updateProfile(profile: UserProfile)

    /** Grants (true) or revokes (false) permission to send voice/receipt content to the AI backend. */
    suspend fun setAiConsent(granted: Boolean)
}
