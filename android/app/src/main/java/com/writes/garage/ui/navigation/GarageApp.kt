package com.writes.garage.ui.navigation

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import com.writes.garage.core.domain.AccentScheme
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import androidx.compose.ui.Modifier
import androidx.navigation.compose.rememberNavController
import com.writes.garage.di.AppContainer
import com.writes.garage.feature.auth.AuthScreen
import com.writes.garage.feature.shared.LocalAppContainer
import com.writes.garage.ui.theme.GarageTheme

/** Root composable: theme + DI + auth gate + navigation. */
@Composable
fun GarageApp(container: AppContainer) {
    val accent = rememberAccentScheme(container)
    GarageTheme(accent = accent) {
        CompositionLocalProvider(LocalAppContainer provides container) {
            Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                val user by container.auth.currentUser.collectAsState()
                if (user == null) {
                    AuthScreen()
                } else {
                    GarageNavHost(rememberNavController())
                }
            }
        }
    }
}

/** The user's stored accent, applied only while Pro (free users see a locked preview in Settings instead). */
@Composable
private fun rememberAccentScheme(container: AppContainer): AccentScheme? {
    val user by container.auth.currentUser.collectAsState()
    val entitlement by container.purchases.entitlement.collectAsState()
    val uid = user?.uid
    val themeId by remember(uid) {
        if (uid == null) flowOf(null) else container.profile.observeProfile().map { it?.themeId }.catch { emit(null) }
    }.collectAsState(initial = null)
    return if (uid != null && entitlement.isPro) AccentScheme.fromId(themeId) else null
}
