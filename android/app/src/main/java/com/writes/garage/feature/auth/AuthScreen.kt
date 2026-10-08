package com.writes.garage.feature.auth

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.writes.garage.R
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.appViewModel

/** Sign-in gate: "Continue in demo" in Demo mode, Google (Credential Manager) in live mode. */
@Composable
fun AuthScreen(modifier: Modifier = Modifier) {
    val vm = appViewModel { AuthViewModel(it.auth, it.isDemo, it.googleSignIn, it.analytics) }
    val state by vm.state.collectAsState()
    val context = LocalContext.current
    Column(
        modifier = modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("Garage", style = MaterialTheme.typography.displayMedium, color = MaterialTheme.colorScheme.primary)
        Text(
            "Clean service logs. Resale-ready records.",
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
        )
        if (state.isDemo) {
            Button(onClick = vm::continueInDemo, enabled = !state.busy) { Text(stringResource(R.string.continue_in_demo)) }
            Text(
                stringResource(R.string.demo_banner),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        if (state.googleAvailable) {
            Button(onClick = { vm.signInWithGoogle(context.findActivity()) }, enabled = !state.busy) {
                Text("Sign in with Google")
            }
        }
        if (!state.isDemo && !state.googleAvailable) {
            OutlinedButton(onClick = {}, enabled = false) { Text("Sign in with Google") }
            Text(
                "Sign-in isn't configured for this build (no Google web client id).",
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
            )
        }
        if (state.busy) CircularProgressIndicator()
        ErrorText(state.error)
    }
}

/** Credential Manager needs an Activity context; Compose's LocalContext may be a wrapper around it. */
private fun Context.findActivity(): Context {
    var c: Context = this
    while (c is ContextWrapper) {
        if (c is Activity) return c
        c = c.baseContext
    }
    return this
}
