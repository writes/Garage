package com.writes.garage.feature.shared

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.writes.garage.core.model.Vehicle

@Composable
fun ScreenColumn(title: String, modifier: Modifier = Modifier, content: LazyListScope.() -> Unit) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { Text(title, style = MaterialTheme.typography.headlineMedium) }
        content()
    }
}

@Composable
fun SectionHeader(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
}

@Composable
fun EmptyState(message: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxWidth().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Placeholder body for screens whose real UI lands in a later pass. */
@Composable
fun PlaceholderBody(description: String, modifier: Modifier = Modifier) {
    Column(modifier = modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Text(description, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Horizontally scrolling chips to switch the active vehicle; hidden when there is nothing to switch between. */
@Composable
fun VehicleSwitcher(
    vehicles: List<Vehicle>,
    activeId: String?,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (vehicles.size < 2) return
    Row(
        modifier = modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        vehicles.forEach { v ->
            FilterChip(selected = v.id == activeId, onClick = { onSelect(v.id) }, label = { Text(v.displayName) })
        }
    }
}

/**
 * Gates a capability behind a plan. [isPro] = "the capability is unlocked" (a Pro entitlement, or a plan limit
 * that still has room); when false [locked] is shown (default: an upsell prompt).
 */
@Composable
fun ProGate(
    isPro: Boolean,
    onUpgrade: () -> Unit,
    modifier: Modifier = Modifier,
    lockedMessage: String = "This is a Garage Pro feature.",
    locked: @Composable () -> Unit = {
        Card(modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(lockedMessage, style = MaterialTheme.typography.bodyMedium)
                Button(onClick = onUpgrade) { Text("Upgrade to Pro") }
            }
        }
    },
    content: @Composable () -> Unit,
) {
    if (isPro) content() else locked()
}

/** Destructive-action confirmation. */
@Composable
fun ConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(confirmLabel) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
fun ErrorText(message: String?, modifier: Modifier = Modifier) {
    if (message == null) return
    Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = modifier)
}

/** First-use consent gate for features that send content to the AI backend. */
@Composable
fun AiConsentDialog(onGrant: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Allow AI processing?") },
        text = {
            Text(
                "Receipt photos and voice transcripts are sent to Garage's AI service (Claude) to draft " +
                    "log entries. Nothing is saved until you confirm. You can revoke this in Settings.",
            )
        },
        confirmButton = { TextButton(onClick = onGrant) { Text("Allow") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Not now") } },
    )
}
