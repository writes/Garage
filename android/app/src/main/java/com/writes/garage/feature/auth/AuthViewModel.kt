package com.writes.garage.feature.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.content.Context
import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.data.GoogleSignInProvider
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class AuthUiState(
    val isDemo: Boolean,
    val googleAvailable: Boolean = false,
    val busy: Boolean = false,
    val error: String? = null,
)

class AuthViewModel(
    private val auth: AuthRepository,
    isDemo: Boolean,
    private val google: GoogleSignInProvider? = null,
) : ViewModel() {
    private val _state = MutableStateFlow(AuthUiState(isDemo, googleAvailable = google != null))
    val state: StateFlow<AuthUiState> = _state.asStateFlow()

    fun continueInDemo() {
        viewModelScope.launch {
            _state.value = _state.value.copy(busy = true, error = null)
            runCatching { auth.signInDemo() }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
            _state.value = _state.value.copy(busy = false)
        }
    }

    /** Live mode: called with the Google ID token from Credential Manager. */
    fun signInWithGoogle(idToken: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(busy = true, error = null)
            runCatching { auth.signInWithGoogle(idToken) }
                .onFailure { _state.value = _state.value.copy(error = it.message) }
            _state.value = _state.value.copy(busy = false)
        }
    }

    /** Live mode: Credential Manager sheet -> Google ID token -> Firebase session. Hidden when [google] is null. */
    fun signInWithGoogle(activityContext: Context) {
        val provider = google ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(busy = true, error = null)
            runCatching { auth.signInWithGoogle(provider.requestIdToken(activityContext)) }
                .onFailure { _state.value = _state.value.copy(error = it.message ?: "Google sign-in failed.") }
            _state.value = _state.value.copy(busy = false)
        }
    }
}
