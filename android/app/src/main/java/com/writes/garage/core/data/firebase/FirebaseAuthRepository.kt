package com.writes.garage.core.data.firebase

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.model.AuthUser
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.tasks.await

/** Firebase Auth. Sign-in is Google (via Credential Manager, see [CredentialManagerGoogleSignIn]) -> Firebase credential. */
class FirebaseAuthRepository(private val auth: FirebaseAuth = FirebaseAuth.getInstance()) : AuthRepository {
    private val _user = MutableStateFlow(auth.currentUser?.toAuthUser())
    override val currentUser: StateFlow<AuthUser?> = _user.asStateFlow()

    init {
        // Lives for the process (the repository is an application singleton), so never removed.
        auth.addAuthStateListener { _user.value = it.currentUser?.toAuthUser() }
    }

    override suspend fun signInDemo() {
        throw UnsupportedOperationException("Demo sign-in is only available in Demo mode.")
    }

    override suspend fun signInWithGoogle(idToken: String) {
        auth.signInWithCredential(GoogleAuthProvider.getCredential(idToken, null)).await()
    }

    override suspend fun signOut() {
        auth.signOut()
    }

    private fun FirebaseUser.toAuthUser() = AuthUser(uid = uid, email = email, displayName = displayName, isDemo = false)
}
