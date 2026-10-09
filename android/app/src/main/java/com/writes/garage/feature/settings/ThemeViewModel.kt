package com.writes.garage.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.ProfileRepository
import com.writes.garage.core.data.PurchaseRepository
import com.writes.garage.core.domain.AccentScheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class ThemeUiState(val isPro: Boolean = false, val selected: AccentScheme? = null, val error: String? = null) {
    /** Every scheme is always listed; for free users all are locked (a preview, never applied). */
    val schemes: List<Pair<AccentScheme, Boolean>> get() = AccentScheme.entries.map { it to !isPro }
}

/** Pro-gated accent picker: writes only `themeID`. Free users get a locked preview. */
class ThemeViewModel(private val profile: ProfileRepository, purchases: PurchaseRepository) : ViewModel() {
    private val error = MutableStateFlow<String?>(null)

    val state: StateFlow<ThemeUiState> = combine(
        purchases.entitlement,
        profile.observeProfile().catch { emit(null) },
        error,
    ) { ent, p, err -> ThemeUiState(ent.isPro, AccentScheme.fromId(p?.themeId), err) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ThemeUiState())

    /** Returns false when the caller should open the paywall instead (not Pro). */
    fun select(scheme: AccentScheme): Boolean {
        if (!state.value.isPro) return false
        viewModelScope.launch {
            error.value = null
            runCatching { profile.setThemeId(scheme.id) }.onFailure { error.value = it.message ?: "Couldn't save the theme." }
        }
        return true
    }
}
