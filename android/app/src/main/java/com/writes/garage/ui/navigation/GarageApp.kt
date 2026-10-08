package com.writes.garage.ui.navigation

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.compose.rememberNavController
import com.writes.garage.di.AppContainer
import com.writes.garage.feature.auth.AuthScreen
import com.writes.garage.feature.shared.LocalAppContainer
import com.writes.garage.ui.theme.GarageTheme

/** Root composable: theme + DI + auth gate + navigation. */
@Composable
fun GarageApp(container: AppContainer) {
    GarageTheme {
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
