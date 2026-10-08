package com.writes.garage.feature.settings

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Button
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.writes.garage.BuildConfig
import com.writes.garage.core.domain.Constants
import com.writes.garage.feature.shared.ConfirmDialog
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.appViewModel

@Composable
fun SettingsScreen() {
    val vm = appViewModel {
        SettingsViewModel(it.auth, it.profile, it.purchases, it.functions, it.notifications, it.isDemo, BuildConfig.VERSION_NAME)
    }
    val s by vm.state.collectAsState()
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    var showPaywall by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    val notifPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) vm.setNotificationsEnabled(true) else vm.notificationPermissionDenied()
    }
    fun toggleNotifications(on: Boolean) {
        if (!on) {
            vm.setNotificationsEnabled(false)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            vm.setNotificationsEnabled(true)
        }
    }

    if (showPaywall) PaywallSheet(onDismiss = { showPaywall = false })
    if (confirmDelete) {
        ConfirmDialog(
            title = "Delete account?",
            message = "This permanently deletes your account, vehicles, entries and attachments from our servers. This can't be undone.",
            confirmLabel = "Delete",
            onConfirm = { confirmDelete = false; vm.deleteAccount() },
            onDismiss = { confirmDelete = false },
        )
    }

    ScreenColumn("Settings") {
        item { SectionHeader("Account") }
        item {
            ListItem(
                headlineContent = { Text(s.user?.displayName ?: "Signed out") },
                supportingContent = { Text(listOfNotNull(s.user?.email, if (s.user?.isDemo == true) "demo session" else null).joinToString(" - ")) },
            )
        }
        item { SectionHeader("Subscription") }
        item {
            ListItem(
                headlineContent = { Text(s.planLabel) },
                supportingContent = {
                    Text(
                        if (s.entitlement.isPro) {
                            if (s.entitlement.willRenew) "Renews automatically" else "Active"
                        } else {
                            "1 vehicle. Upgrade for up to 5."
                        },
                    )
                },
                trailingContent = { OutlinedButton(onClick = { showPaywall = true }) { Text(if (s.entitlement.isPro) "Manage" else "Upgrade") } },
            )
        }
        item { SectionHeader("Notifications") }
        item {
            ListItem(
                headlineContent = { Text("Reminder notifications") },
                supportingContent = { Text("A nudge 3 days before and on the day a reminder is due") },
                trailingContent = { Switch(checked = s.notificationsEnabled, onCheckedChange = ::toggleNotifications) },
            )
        }
        item { SectionHeader("Privacy") }
        item {
            ListItem(
                headlineContent = { Text("Allow AI processing") },
                supportingContent = { Text("Receipt and voice entry send content to Claude") },
                trailingContent = { Switch(checked = s.profile?.hasAiConsent == true, onCheckedChange = vm::setAiConsent) },
            )
        }
        item {
            ListItem(
                headlineContent = { Text("Privacy policy") },
                supportingContent = { Text(Constants.PRIVACY_POLICY_URL) },
                modifier = Modifier.clickable { runCatching { uriHandler.openUri(Constants.PRIVACY_POLICY_URL) } },
            )
        }
        item {
            ListItem(
                headlineContent = { Text("Terms of use") },
                supportingContent = { Text(Constants.TERMS_OF_USE_URL) },
                modifier = Modifier.clickable { runCatching { uriHandler.openUri(Constants.TERMS_OF_USE_URL) } },
            )
        }
        item { SectionHeader("About") }
        item { ListItem(headlineContent = { Text("Backend") }, supportingContent = { Text(s.backendLabel) }) }
        item { ListItem(headlineContent = { Text("Version") }, supportingContent = { Text(s.appVersion) }) }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = vm::signOut, enabled = !s.busy) { Text("Sign out") }
                OutlinedButton(
                    onClick = { confirmDelete = true }, enabled = !s.busy,
                ) { Text("Delete account", color = MaterialTheme.colorScheme.error) }
            }
        }
        item { ErrorText(s.error) }
    }
}
