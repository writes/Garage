package com.writes.garage.core.notify

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Per-device preference: should reminders raise local notifications? (Off by default; opt-in from Settings.) */
interface NotificationSettings {
    val enabled: StateFlow<Boolean>

    fun setEnabled(enabled: Boolean)
}

class InMemoryNotificationSettings(initial: Boolean = false) : NotificationSettings {
    private val _enabled = MutableStateFlow(initial)
    override val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    override fun setEnabled(enabled: Boolean) {
        _enabled.value = enabled
    }
}

class PrefsNotificationSettings(private val prefs: SharedPreferences) : NotificationSettings {
    private val _enabled = MutableStateFlow(prefs.getBoolean(KEY, false))
    override val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    override fun setEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY, enabled).apply()
        _enabled.value = enabled
    }

    private companion object {
        const val KEY = "reminder_notifications_enabled"
    }
}
