package com.writes.garage.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.appViewModel

/** Full-screen paywall (route), used by upsell prompts elsewhere. */
@Composable
fun PaywallScreen(onBack: () -> Unit) {
    val vm = appViewModel { PaywallViewModel(it.purchases, it.analytics) }
    val s by vm.state.collectAsState()
    ScreenColumn("Garage Pro") {
        item { PaywallBody(s, vm::purchase, vm::restore) }
        item { OutlinedButton(onClick = onBack) { Text("Back") } }
    }
}

/** The same paywall as a bottom sheet (opened from Settings). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallSheet(onDismiss: () -> Unit) {
    val vm = appViewModel { PaywallViewModel(it.purchases, it.analytics) }
    val s by vm.state.collectAsState()
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Garage Pro", style = MaterialTheme.typography.headlineSmall)
            PaywallBody(s, vm::purchase, vm::restore)
            OutlinedButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text("Close") }
        }
    }
}

@Composable
private fun PaywallBody(s: PaywallUiState, onPurchase: (String) -> Unit, onRestore: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            if (s.isPro) "You have Garage Pro." else "Up to 5 vehicles, reminders and more receipt scans.",
            style = MaterialTheme.typography.bodyMedium,
        )
        if (s.busy || !s.loaded) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (s.loaded && s.packages.isEmpty() && !s.isPro) {
            Text(
                "Subscriptions aren't available in this build.",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        s.packages.forEach { pkg ->
            ListItem(
                headlineContent = { Text(pkg.title) },
                supportingContent = { Text("${pkg.priceLabel} / ${pkg.period}") },
                trailingContent = { Button(onClick = { onPurchase(pkg.id) }, enabled = !s.busy && !s.isPro) { Text("Buy") } },
            )
        }
        OutlinedButton(onClick = onRestore, enabled = !s.busy, modifier = Modifier.fillMaxWidth()) { Text("Restore purchases") }
        s.message?.let { Text(it, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodyMedium) }
        ErrorText(s.error)
    }
}
