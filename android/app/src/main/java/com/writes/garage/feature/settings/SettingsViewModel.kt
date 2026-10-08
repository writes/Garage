package com.writes.garage.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.ProfileRepository
import com.writes.garage.core.data.PurchaseRepository
import com.writes.garage.core.model.AuthUser
import com.writes.garage.core.model.Entitlement
import com.writes.garage.core.model.PaywallPackage
import com.writes.garage.core.model.UserProfile
import com.writes.garage.core.notify.NotificationSettings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class SettingsUiState(
    val user: AuthUser? = null,
    val profile: UserProfile? = null,
    val entitlement: Entitlement = Entitlement.FREE,
    val notificationsEnabled: Boolean = false,
    /** true = Demo (in-memory) backend, false = live Firebase. */
    val isDemo: Boolean = true,
    val appVersion: String = "",
    val busy: Boolean = false,
    val message: String? = null,
    val error: String? = null,
) {
    val backendLabel: String get() = if (isDemo) "Demo" else "Live"
    val planLabel: String get() = if (entitlement.isPro) "Garage Pro" else "Free"
}

class SettingsViewModel(
    private val auth: AuthRepository,
    private val profile: ProfileRepository,
    private val purchases: PurchaseRepository,
    private val functions: FunctionsGateway,
    private val notifications: NotificationSettings,
    isDemo: Boolean,
    appVersion: String,
) : ViewModel() {
    private val _state = MutableStateFlow(SettingsUiState(isDemo = isDemo, appVersion = appVersion))
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            combine(auth.currentUser, profile.observeProfile(), purchases.entitlement, notifications.enabled) { u, p, e, n ->
                arrayOf(u, p, e, n)
            }.catch { e -> _state.update { it.copy(error = e.message ?: "Couldn't load your settings.") } }
                .collect { (u, p, e, n) ->
                _state.update {
                    it.copy(user = u as AuthUser?, profile = p as UserProfile?, entitlement = e as Entitlement, notificationsEnabled = n as Boolean)
                }
            }
        }
    }

    fun setAiConsent(granted: Boolean) {
        viewModelScope.launch {
            runCatching { profile.setAiConsent(granted) }
                .onFailure { e -> _state.update { it.copy(error = e.message ?: "Couldn't update AI consent.") } }
        }
    }

    /** The screen requests POST_NOTIFICATIONS first (API 33+) and passes the outcome here. */
    fun setNotificationsEnabled(enabled: Boolean) {
        notifications.setEnabled(enabled)
    }

    fun notificationPermissionDenied() {
        notifications.setEnabled(false)
        _state.update { it.copy(error = "Notification permission denied. Enable it in system settings to get reminders.") }
    }

    fun signOut() {
        viewModelScope.launch {
            runCatching { auth.signOut() }
                .onFailure { e -> _state.update { it.copy(error = e.message ?: "Couldn't sign out.") } }
        }
    }

    /** Server-side account purge (`deleteAccount`), then drop the local session. The screen confirms first. */
    fun deleteAccount() {
        if (_state.value.busy) return
        viewModelScope.launch {
            _state.update { it.copy(busy = true, error = null, message = null) }
            runCatching {
                functions.deleteAccount()
                notifications.setEnabled(false)
                auth.signOut()
            }.onSuccess { _state.update { it.copy(busy = false) } }
                .onFailure { e -> _state.update { it.copy(busy = false, error = e.message ?: "Couldn't delete the account.") } }
        }
    }

    fun clearMessages() = _state.update { it.copy(message = null, error = null) }
}

data class PaywallUiState(
    val packages: List<PaywallPackage> = emptyList(),
    val loaded: Boolean = false,
    val isPro: Boolean = false,
    val busy: Boolean = false,
    val message: String? = null,
    val error: String? = null,
)

class PaywallViewModel(private val purchases: PurchaseRepository) : ViewModel() {
    private val _packages = MutableStateFlow<List<PaywallPackage>>(emptyList())
    private val _loaded = MutableStateFlow(false)
    private val _busy = MutableStateFlow(false)
    private val _message = MutableStateFlow<String?>(null)
    private val _error = MutableStateFlow<String?>(null)

    val state: StateFlow<PaywallUiState> = combine(
        combine(_packages, _loaded, _busy) { p, l, b -> Triple(p, l, b) },
        purchases.entitlement, _message, _error,
    ) { (p, l, b), e, m, err -> PaywallUiState(p, l, e.isPro, b, m, err) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PaywallUiState())

    init {
        viewModelScope.launch {
            runCatching { purchases.loadPackages() }
                .onSuccess { _packages.value = it }
                .onFailure { _error.value = it.message ?: "Couldn't load subscription options." }
            _loaded.value = true
        }
    }

    fun purchase(id: String) {
        if (_busy.value) return
        viewModelScope.launch {
            _busy.value = true
            _error.value = null
            _message.value = null
            runCatching { purchases.purchase(id) }
                .onSuccess { _message.value = "Thanks! Garage Pro is active." }
                .onFailure { _error.value = it.message ?: "Purchase failed." }
            _busy.value = false
        }
    }

    fun restore() {
        if (_busy.value) return
        viewModelScope.launch {
            _busy.value = true
            _error.value = null
            _message.value = null
            runCatching { purchases.restore() }
                .onSuccess { _message.value = "Purchases restored." }
                .onFailure { _error.value = it.message ?: "Couldn't restore purchases." }
            _busy.value = false
        }
    }
}
