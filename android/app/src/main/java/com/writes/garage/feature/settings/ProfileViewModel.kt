package com.writes.garage.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.writes.garage.core.data.ProfileRepository
import com.writes.garage.core.model.UserProfile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ProfileFormState(
    val name: String = "",
    val address: String = "",
    val phone: String = "",
    val insuranceCompany: String = "",
    val policyNumber: String = "",
    val email: String? = null,
    val loaded: Boolean = false,
    val saving: Boolean = false,
    val saved: Boolean = false,
    val error: String? = null,
)

/** Owner + insurance details (iOS `UserProfileView`). Saves only the form-owned fields (merge write). */
class ProfileViewModel(private val repo: ProfileRepository) : ViewModel() {
    private val _state = MutableStateFlow(ProfileFormState())
    val state: StateFlow<ProfileFormState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            runCatching { repo.observeProfile().first() }
                .onSuccess { p ->
                    if (p == null) {
                        _state.update { it.copy(error = "Couldn't load your profile.") }
                    } else {
                        _state.update {
                            it.copy(
                                name = p.name.orEmpty(), address = p.address.orEmpty(), phone = p.phone.orEmpty(),
                                insuranceCompany = p.insuranceCompany.orEmpty(), policyNumber = p.policyNumber.orEmpty(),
                                email = p.email, loaded = true,
                            )
                        }
                    }
                }
                .onFailure { e -> _state.update { it.copy(error = e.message ?: "Couldn't load your profile.") } }
        }
    }

    fun edit(transform: ProfileFormState.() -> ProfileFormState) = _state.update { it.transform().copy(saved = false, error = null) }

    /** Never saves before a successful load: the empty defaults would wipe the stored details. */
    fun save() {
        val s = _state.value
        if (!s.loaded || s.saving) return
        viewModelScope.launch {
            _state.update { it.copy(saving = true, error = null, saved = false) }
            runCatching {
                // Re-read right before writing so fields other surfaces own are not carried from a stale copy.
                val fresh: UserProfile = repo.observeProfile().first() ?: error("Not signed in")
                repo.updateProfile(
                    fresh.copy(
                        name = s.name.trim().ifEmpty { null }, address = s.address.trim().ifEmpty { null },
                        phone = s.phone.trim().ifEmpty { null }, insuranceCompany = s.insuranceCompany.trim().ifEmpty { null },
                        policyNumber = s.policyNumber.trim().ifEmpty { null },
                    ),
                )
            }.onSuccess { _state.update { it.copy(saving = false, saved = true) } }
                .onFailure { e -> _state.update { it.copy(saving = false, error = e.message ?: "Couldn't save your profile.") } }
        }
    }
}
