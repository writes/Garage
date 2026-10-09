package com.writes.garage.core.data

import com.writes.garage.core.model.AuthUser
import kotlinx.coroutines.flow.StateFlow

interface AuthRepository {
    /** null = signed out. */
    val currentUser: StateFlow<AuthUser?>

    /** Fake auth for Demo mode ("Continue in demo"). Live implementations may throw. */
    suspend fun signInDemo()

    /** Live: exchange a Google ID token (from Credential Manager) for a Firebase session. */
    suspend fun signInWithGoogle(idToken: String)

    suspend fun signOut()
}
